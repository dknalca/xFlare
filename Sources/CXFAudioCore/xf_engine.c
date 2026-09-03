/* SPDX-License-Identifier: GPL-3.0-only */
#include "xf_engine.h"
#include "xf_player.h"
#include "xf_eq.h"
#include "xf_rt.h"

#include <math.h>
#include <stdatomic.h>
#include <stdlib.h>
#include <string.h>

/* ================================================================== *
 *  ESTADO
 * ================================================================== */

struct xf_engine {
    double       sample_rate;
    uint32_t     max_frames;
    int          ppq;

    /* buffers preasignados (nunca se reservan en RT) */
    int16_t     *in_i16;        /* max_frames * 2 (estereo intercalado) */
    float       *mono;          /* max_frames */
    float       *mono2;         /* max_frames — mezcla auxiliar de la instrumental */
    uint8_t     *ring_storage;
    xf_ring_t    input_ring;

    xf_metronome *metronome;

    /* reproductor: puntero atomico + un retiro de 1 generacion */
    _Atomic(xf_player *) player;
    xf_player           *retired_player;

    /* base instrumental en bucle: mismo patron de swap que `player` */
    _Atomic(xf_player *) instrumental;
    xf_player           *retired_instrumental;
    double               instr_native_bpm;   /* solo lo toca el hilo normal */
    _Atomic double       instr_ratio;        /* bpm sesion / native_bpm */
    _Atomic double       instr_gain;

    /* control desde Swift (atomico) */
    _Atomic double  target_velocity;
    _Atomic double  bpm;
    _Atomic int     playing;      /* 0/1 */
    _Atomic double  master_gain;  /* guardado como double para simplificar */
    _Atomic double  scratch_gain_target;  /* 0..1, solo el player de scratch */
    double          scratch_gain_cur;     /* suavizado, solo lo toca el hilo RT */
    double          scratch_gain_coef;    /* one-pole ~5 ms, precalculado */
    xf_eq           sample_eq;            /* EQ Lo/Mid/Hi SOLO del sample de scratch */
    /* ajustes de "tacto" del plato (ventana Debug). Solo los toca el hilo normal;
     * se aplican al player de scratch al cargarlo y al cambiarlos. */
    double          scratch_glide_ms;     /* suavizado de velocidad; menos = mas seco */
    double          scratch_speed_gate;   /* |v| por debajo de la cual no suena */
    _Atomic double  out_peak;             /* pico de salida ANTES de limitar, para la UI */
    _Atomic double  scratch_target;       /* frame objetivo del cabezal; <0 = suelto */

    /* reloj musical: avanzado en RT, leido por Swift */
    _Atomic double  reported_tick;   /* tick al inicio del ultimo bloque */
    double          tick;            /* posicion en curso (solo lo toca RT o seek) */
    /* Desfase (ticks) que se le suma AL METRONOMO para que siga a la rejilla
     * cuando el usuario la mueve con los botones ◀/▶ (`gridShift` de la UI). No
     * toca el reloj ni la base, solo dónde caen los clics. `dirty` -> el RT
     * re-fasea el metronomo (sin meter un clic) al próximo bloque. */
    _Atomic double  metro_offset;
    _Atomic int     metro_offset_dirty;
    /* Corrección CONTINUA de la deriva entre el reloj del motor (`e->tick`,
     * cristal de audio) y el de la sesión que dibuja la rejilla (timer de pared):
     * se le suma al tick del metronomo cada bloque. Cambia poquito a poco (la
     * capa Swift la suaviza), así que NO lleva `dirty` ni re-fasea. Un `seek` la
     * pone a 0. */
    _Atomic double  metro_drift;

    /* diagnostico */
    _Atomic uint64_t overloads;
    _Atomic uint64_t render_errors;
    _Atomic uint64_t input_ring_drops;

    /* --- host CoreAudio (opaco fuera de xf_engine_start/stop) --- */
    void        *au;             /* AudioUnit, o NULL si no arrancado */
    void        *in_abl;         /* AudioBufferList preasignada para la entrada */
    float       *in_scratch;     /* max_frames * 2 (L,R no intercalado) */
    void        *workgroup;      /* os_workgroup_t, o NULL */
    unsigned char wg_token[64];  /* os_workgroup_join_token_s (tamano de sobra) */
    _Atomic int  rt_promoted;    /* 0 hasta el primer callback */
    int          capture_input;  /* 1 = duplex; 0 = solo salida. Fijo antes de arrancar */
};

/* pow2 >= n */
static size_t xf_next_pow2(size_t n) {
    size_t p = 1;
    while (p < n) p <<= 1;
    return p;
}

/* ================================================================== *
 *  CREACION / DESTRUCCION
 * ================================================================== */

xf_engine *xf_engine_create(double sample_rate, uint32_t max_frames) {
    if (sample_rate <= 0.0 || max_frames == 0) return NULL;

    xf_engine *e = (xf_engine *)calloc(1, sizeof(*e));
    if (!e) return NULL;

    e->sample_rate = sample_rate;
    e->max_frames  = max_frames;
    e->ppq         = 480;

    e->in_i16 = (int16_t *)malloc((size_t)max_frames * 2 * sizeof(int16_t));
    e->mono   = (float *)malloc((size_t)max_frames * sizeof(float));
    e->mono2  = (float *)malloc((size_t)max_frames * sizeof(float));

    /* ring de entrada: ~32 bloques de PCM estereo int16 */
    size_t block_bytes = (size_t)max_frames * 2 * sizeof(int16_t);
    size_t ring_cap = xf_next_pow2(block_bytes * 32);
    e->ring_storage = (uint8_t *)malloc(ring_cap);

    e->in_scratch = (float *)malloc((size_t)max_frames * 2 * sizeof(float));
    e->metronome  = xf_metronome_create((unsigned int)sample_rate);

    if (!e->in_i16 || !e->mono || !e->mono2 || !e->ring_storage || !e->in_scratch ||
        !e->metronome || !xf_ring_init(&e->input_ring, e->ring_storage, ring_cap)) {
        xf_engine_destroy(e);
        return NULL;
    }

    atomic_store(&e->player, (xf_player *)NULL);
    atomic_store(&e->instrumental, (xf_player *)NULL);
    atomic_store(&e->instr_ratio, 1.0);
    atomic_store(&e->instr_gain, 0.5);
    atomic_store(&e->target_velocity, 0.0);
    atomic_store(&e->bpm, 120.0);
    atomic_store(&e->playing, 0);
    atomic_store(&e->master_gain, 1.0);
    atomic_store(&e->scratch_gain_target, 1.0);
    atomic_store(&e->scratch_target, -1.0);
    e->scratch_gain_cur = 1.0;
    e->scratch_gain_coef = 1.0 - exp(-1.0 / (0.005 * sample_rate));
    e->scratch_glide_ms = 3.0;      /* antes 5; mas seco = el audio sigue mejor al gesto */
    e->scratch_speed_gate = 0.12;
    xf_eq_init(&e->sample_eq, sample_rate);   /* plano por defecto */
    atomic_store(&e->reported_tick, 0.0);
    atomic_store(&e->metro_offset, 0.0);
    atomic_store(&e->metro_offset_dirty, 0);
    atomic_store(&e->metro_drift, 0.0);
    e->capture_input = 1;
    return e;
}

void xf_engine_destroy(xf_engine *e) {
    if (!e) return;
    xf_engine_stop(e);

    xf_player *p = atomic_load(&e->player);
    if (p) xf_player_destroy(p);
    if (e->retired_player) xf_player_destroy(e->retired_player);
    xf_player *ip = atomic_load(&e->instrumental);
    if (ip) xf_player_destroy(ip);
    if (e->retired_instrumental) xf_player_destroy(e->retired_instrumental);
    if (e->metronome) xf_metronome_destroy(e->metronome);

    free(e->in_i16);
    free(e->mono);
    free(e->mono2);
    free(e->ring_storage);
    free(e->in_scratch);
    free(e->in_abl);
    free(e);
}

/* ================================================================== *
 *  CONTROL (NO RT-SAFE)
 * ================================================================== */

void xf_engine_load_sample(xf_engine *e, const float *sample, int64_t frames) {
    if (!e) return;
    xf_player *np = (sample && frames >= 2)
        ? xf_player_create(sample, frames, (unsigned int)e->sample_rate)
        : NULL;
    if (np) {
        /* el plato casi parado no debe sonar (ni zumbar): puerta por velocidad */
        xf_player_set_speed_gate(np, e->scratch_speed_gate);
        xf_player_set_glide_ms(np, e->scratch_glide_ms);
    }

    /* el retiro de 2 generaciones ya no puede estar en uso por el hilo RT */
    if (e->retired_player) { xf_player_destroy(e->retired_player); }
    e->retired_player = atomic_exchange(&e->player, np);
}

void xf_engine_set_scratch_glide_ms(xf_engine *e, double ms) {
    if (!e) return;
    if (ms < 0.0) ms = 0.0;
    if (ms > 50.0) ms = 50.0;
    e->scratch_glide_ms = ms;
    xf_player *p = atomic_load(&e->player);
    if (p) xf_player_set_glide_ms(p, ms);   /* escribe un `double`: torn-safe en la practica */
}

void xf_engine_set_scratch_speed_gate(xf_engine *e, double gate) {
    if (!e) return;
    if (gate < 0.0) gate = 0.0;
    if (gate > 1.0) gate = 1.0;
    e->scratch_speed_gate = gate;
    xf_player *p = atomic_load(&e->player);
    if (p) xf_player_set_speed_gate(p, gate);
}

void xf_engine_set_transport(xf_engine *e, double bpm, int ppq, bool playing) {
    if (!e) return;
    if (bpm > 0.0) {
        atomic_store(&e->bpm, bpm);
        /* la base instrumental sigue el tempo de la sesion */
        if (e->instr_native_bpm > 0.0)
            atomic_store(&e->instr_ratio, bpm / e->instr_native_bpm);
    }
    if (ppq >= 1) { e->ppq = ppq; xf_metronome_set_time_signature(e->metronome, 4, ppq); }
    atomic_store(&e->playing, playing ? 1 : 0);
}

void xf_engine_load_instrumental(xf_engine *e, const float *mono, int64_t frames,
                                 double native_bpm) {
    if (!e) return;
    xf_player *np = NULL;
    if (mono && frames >= 2 && native_bpm > 0.0) {
        np = xf_player_create(mono, frames, (unsigned int)e->sample_rate);
        if (np) {
            xf_player_set_loop(np, true);
            xf_player_set_glide_ms(np, 0.0);   /* ratio constante: no hace falta glide */
        }
    }
    e->instr_native_bpm = (native_bpm > 0.0 && np) ? native_bpm : 0.0;
    double bpm = atomic_load(&e->bpm);
    atomic_store(&e->instr_ratio, e->instr_native_bpm > 0.0 ? bpm / e->instr_native_bpm : 1.0);

    if (e->retired_instrumental) xf_player_destroy(e->retired_instrumental);
    e->retired_instrumental = atomic_exchange(&e->instrumental, np);
}

void xf_engine_set_instrumental_gain(xf_engine *e, float gain) {
    if (!e) return;
    if (gain < 0.0f) gain = 0.0f;
    if (gain > 1.0f) gain = 1.0f;
    atomic_store(&e->instr_gain, (double)gain);
}

void xf_engine_set_instrumental_native_bpm(xf_engine *e, double native_bpm) {
    if (!e || native_bpm <= 0.0 || e->instr_native_bpm <= 0.0) return;
    /* NO recrea el player: solo reinterpreta a que tempo se grabo, para que el
     * ratio (bpm sesion / native) cambie sin reiniciar el cabezal. Lo usa el TAP
     * tempo / la edicion del BPM a mano: cambia la rejilla en caliente y la base
     * se sigue oyendo donde estaba, a su velocidad real. */
    e->instr_native_bpm = native_bpm;
    atomic_store(&e->instr_ratio, atomic_load(&e->bpm) / native_bpm);
}

void xf_engine_seek_tick(xf_engine *e, double tick) {
    if (!e) return;
    e->tick = tick;
    atomic_store(&e->reported_tick, tick);
    /* un `seek` re-cuadra el metronomo desde `tick`: el desfase de rejilla y la
     * deriva acumulada dejan de tener sentido, a 0. */
    atomic_store(&e->metro_offset, 0.0);
    atomic_store(&e->metro_offset_dirty, 0);
    atomic_store(&e->metro_drift, 0.0);
    /* el tiempo del punto al que saltamos suena (es el "1" de la cuenta atras) */
    xf_metronome_arm(e->metronome, tick);
}

void xf_engine_set_metronome_offset(xf_engine *e, double ticks) {
    if (!e) return;
    atomic_store(&e->metro_offset, ticks);
    atomic_store(&e->metro_offset_dirty, 1);   /* el RT re-fasea sin meter un clic */
}

void xf_engine_set_metronome_drift(xf_engine *e, double ticks) {
    /* corrección continua motor<->sesión. Sin `dirty`: la capa Swift la mueve
     * suave, el RT solo la suma al tick del metronomo. */
    if (e) atomic_store(&e->metro_drift, ticks);
}

void xf_engine_set_velocity(xf_engine *e, double velocity) {
    if (e) atomic_store(&e->target_velocity, velocity);
}

void xf_engine_seek_scratch(xf_engine *e, double frame) {
    if (!e) return;
    xf_player *p = atomic_load(&e->player);
    if (p) xf_player_set_playhead(p, frame);
}

void xf_engine_set_scratch_target(xf_engine *e, double frame) {
    if (e) atomic_store(&e->scratch_target, frame);
}

void xf_engine_set_master_gain(xf_engine *e, float gain) {
    if (!e) return;
    if (gain < 0.0f) gain = 0.0f;
    atomic_store(&e->master_gain, (double)gain);
}

void xf_engine_set_scratch_gain(xf_engine *e, float gain) {
    if (!e) return;
    if (gain < 0.0f) gain = 0.0f;
    if (gain > 1.0f) gain = 1.0f;
    atomic_store(&e->scratch_gain_target, (double)gain);
}

void xf_engine_set_sample_eq(xf_engine *e, float low_db, float mid_db, float high_db) {
    if (!e) return;
    xf_eq_set_gains_db(&e->sample_eq, low_db, mid_db, high_db);
}

xf_ring_t   *xf_engine_input_ring(xf_engine *e) { return e ? &e->input_ring : NULL; }
xf_metronome *xf_engine_metronome(xf_engine *e) { return e ? e->metronome : NULL; }

double xf_engine_tick(const xf_engine *e) {
    return e ? atomic_load(&((xf_engine *)e)->reported_tick) : 0.0;
}

double xf_engine_scratch_playhead(const xf_engine *e) {
    if (!e) return 0.0;
    xf_player *p = atomic_load(&((xf_engine *)e)->player);
    return p ? xf_player_playhead(p) : 0.0;
}
double xf_engine_instrumental_playhead(const xf_engine *e) {
    if (!e) return -1.0;
    xf_player *ip = atomic_load(&((xf_engine *)e)->instrumental);
    return ip ? xf_player_playhead(ip) : -1.0;   /* <0 = no hay base cargada */
}
uint64_t xf_engine_overload_count(const xf_engine *e) {
    return e ? atomic_load(&((xf_engine *)e)->overloads) : 0;
}
uint64_t xf_engine_render_error_count(const xf_engine *e) {
    return e ? atomic_load(&((xf_engine *)e)->render_errors) : 0;
}
double xf_engine_output_peak(const xf_engine *e) {
    return e ? atomic_load(&((xf_engine *)e)->out_peak) : 0.0;
}

int xf_engine_api_version(void) { return 1; }

/* ================================================================== *
 *  NUCLEO RT  (sin CoreAudio, testeable)
 * ================================================================== */

static inline int16_t xf_f32_to_i16(float x) {
    float v = x * 32767.0f;
    if (v > 32767.0f) v = 32767.0f;
    if (v < -32767.0f) v = -32767.0f;
    return (int16_t)v;
}

void xf_engine_render(xf_engine *e,
                      const float *in_l, const float *in_r,
                      float *out_l, float *out_r,
                      int nframes, uint64_t host_time) {
    (void)host_time;
    if (!e || !out_l || !out_r || nframes <= 0) return;
    if ((uint32_t)nframes > e->max_frames) nframes = (int)e->max_frames;

    const double bpm     = atomic_load(&e->bpm);
    const int    playing = atomic_load(&e->playing);
    const double vel     = atomic_load(&e->target_velocity);
    const float  gain    = (float)atomic_load(&e->master_gain);

    /* --- reloj musical: publica el tick del inicio del bloque, luego avanza --- */
    const double block_start_tick = e->tick;
    atomic_store(&e->reported_tick, block_start_tick);
    if (playing) {
        e->tick += bpm / 60.0 * (double)e->ppq / e->sample_rate * (double)nframes;
    }

    /* --- entrada del dispositivo -> ring (estereo int16 intercalado) --- */
    if (in_l && in_r) {
        for (int n = 0; n < nframes; n++) {
            e->in_i16[n * 2 + 0] = xf_f32_to_i16(in_l[n]);
            e->in_i16[n * 2 + 1] = xf_f32_to_i16(in_r[n]);
        }
        size_t want = (size_t)nframes * 2 * sizeof(int16_t);
        size_t wrote = xf_ring_write(&e->input_ring, e->in_i16, want);
        if (wrote < want) atomic_fetch_add(&e->input_ring_drops, 1);
    }

    /* --- salida: reproductor + base instrumental + metronomo --- */
    xf_player *p = atomic_load(&e->player);
    if (p) {
        /* Ancla de posicion (ADR-042). La velocidad que manda Swift (`vel`) es el
         * driver del cabezal; el objetivo de posicion solo aporta un TRIM
         * anti-deriva acotado dentro del player (<=1.5% de pitch), que NO se
         * oye. Historia: primero fue un salto de cabezal 15%/bloque (crujido),
         * luego velocidad media de bloque (overshoot), luego one-pole rapido
         * (barrido "laser" al perseguir los escalones de 60 Hz del objetivo).
         * `< 0` suelta el ancla. */
        xf_player_set_target_playhead(p, atomic_load(&e->scratch_target));
        xf_player_render(p, e->mono, nframes, vel);
    } else {
        memset(e->mono, 0, (size_t)nframes * sizeof(float));
    }

    /* ganancia SOLO del scratch, suavizada: el mute/fader no toca la base */
    {
        const double tgt  = atomic_load(&e->scratch_gain_target);
        const double coef = e->scratch_gain_coef;
        double g = e->scratch_gain_cur;
        for (int n = 0; n < nframes; n++) {
            g += (tgt - g) * coef;
            e->mono[n] *= (float)g;
        }
        e->scratch_gain_cur = g;
    }

    /* EQ de 3 bandas SOLO sobre el scratch (la base y el metronomo NO se tocan).
     * En plano (por defecto) `xf_eq_process_block` no hace nada. */
    xf_eq_process_block(&e->sample_eq, e->mono, nframes);

    /* La base instrumental solo suena con el transporte EN MARCHA. Al pausar
     * (`set_transport(..., false)`, p. ej. la tecla P de "congelar" en la
     * practica) no se llama a su render, asi que su cabezal se queda quieto y
     * al reanudar sigue justo donde estaba. El reproductor de scratch NO se
     * toca: se puede seguir scratcheando sobre la imagen congelada. */
    xf_player *ip = atomic_load(&e->instrumental);
    if (ip && playing) {
        const double iratio = atomic_load(&e->instr_ratio);
        const float  igain  = (float)atomic_load(&e->instr_gain);
        xf_player_render(ip, e->mono2, nframes, iratio);
        for (int n = 0; n < nframes; n++) e->mono[n] += e->mono2[n] * igain;
    }

    /* El metronomo va con el reloj del motor MAS el desfase de rejilla (◀/▶) MAS
     * la corrección de deriva motor<->sesión: asi el clic cae en la linea de
     * compas DIBUJADA y sigue cayendo ahi aunque los dos relojes se separen a la
     * larga. Al cambiar el desfase, `dirty` -> re-fasear (marca el compas actual
     * como ya sonado) para no meter un clic de mas; la deriva NO re-fasea (se
     * mueve muy poco a poco). */
    {
        const double moff = atomic_load(&e->metro_offset) + atomic_load(&e->metro_drift);
        if (atomic_exchange(&e->metro_offset_dirty, 0)) {
            xf_metronome_resync(e->metronome, block_start_tick + moff);
        }
        xf_metronome_render(e->metronome, e->mono, nframes, block_start_tick + moff, bpm);
    }

    /* Salida: soft-clip en vez de recorte duro (el recorte duro suena a
     * crujido). Transparente hasta |s| = 0,7; por encima, rodilla suave con
     * tanh. Ademas se guarda el pico ANTES de limitar, para el medidor de la UI
     * (si supera 1,0, la mezcla estaba clipeando). */
    float peak = 0.0f;
    for (int n = 0; n < nframes; n++) {
        float s = e->mono[n] * gain;
        float a = s < 0.0f ? -s : s;
        if (a > peak) peak = a;

        const float knee = 0.7f;
        if (a > knee) {
            float over = (a - knee) / (1.0f - knee);   /* >0 */
            float shaped = knee + (1.0f - knee) * tanhf(over);
            s = s < 0.0f ? -shaped : shaped;
        }
        out_l[n] = s;
        out_r[n] = s;
    }
    /* pico con decaimiento lento entre bloques, para que el medidor no parpadee */
    double prev = atomic_load(&e->out_peak);
    double decayed = prev * 0.85;
    atomic_store(&e->out_peak, (double)peak > decayed ? (double)peak : decayed);
}

/* ================================================================== *
 *  HOST CoreAudio  (compila; sin tests, necesita dispositivo)
 * ================================================================== */

#include <AudioUnit/AudioUnit.h>
#include <AudioToolbox/AudioToolbox.h>
#include <CoreAudio/CoreAudio.h>
#include <mach/mach_time.h>
#include <os/workgroup.h>

#ifndef kAudioObjectPropertyElementMain
#define kAudioObjectPropertyElementMain kAudioObjectPropertyElementMaster
#endif

static OSStatus xf_engine_render_cb(void *ref, AudioUnitRenderActionFlags *flags,
                                    const AudioTimeStamp *ts, UInt32 bus, UInt32 frames,
                                    AudioBufferList *out) {
    (void)bus;
    xf_engine *e = (xf_engine *)ref;

    /* 1) primer callback: promocionar el hilo y unirse al workgroup */
    if (atomic_exchange(&e->rt_promoted, 1) == 0) {
        xf_rt_promote_current_thread(e->sample_rate, e->max_frames);
        if (e->workgroup) {
            os_workgroup_join((os_workgroup_t)e->workgroup,
                              (os_workgroup_join_token_t)e->wg_token);
        }
    }

    /* 2) tirar de la entrada a la ABL preasignada (solo en modo duplex) */
    const float *inL = NULL, *inR = NULL;
    if (e->capture_input) {
        AudioBufferList *inABL = (AudioBufferList *)e->in_abl;
        for (UInt32 c = 0; c < 2; c++) {
            inABL->mBuffers[c].mNumberChannels = 1;
            inABL->mBuffers[c].mDataByteSize   = frames * (UInt32)sizeof(float);
            inABL->mBuffers[c].mData           = e->in_scratch + (size_t)c * e->max_frames;
        }
        inABL->mNumberBuffers = 2;

        OSStatus err = AudioUnitRender((AudioUnit)e->au, flags, ts, 1 /* bus entrada */, frames, inABL);
        if (err == noErr) {
            inL = (const float *)inABL->mBuffers[0].mData;
            inR = (const float *)inABL->mBuffers[1].mData;
        } else {
            atomic_fetch_add(&e->render_errors, 1);
        }
    }

    /* 3) nucleo RT */
    float *outL = (out->mNumberBuffers > 0) ? (float *)out->mBuffers[0].mData : NULL;
    float *outR = (out->mNumberBuffers > 1) ? (float *)out->mBuffers[1].mData : outL;
    if (outL && outR) {
        xf_engine_render(e, inL, inR, outL, outR, (int)frames, mach_absolute_time());
    }
    return noErr;
}

static OSStatus xf_engine_on_overload(AudioObjectID obj, UInt32 n,
                                      const AudioObjectPropertyAddress *addr, void *ref) {
    (void)obj; (void)n; (void)addr;
    atomic_fetch_add(&((xf_engine *)ref)->overloads, 1);
    return noErr;
}

static AudioDeviceID xf_engine_default_output_device(void) {
    AudioDeviceID dev = kAudioObjectUnknown;
    UInt32 size = sizeof(dev);
    AudioObjectPropertyAddress addr = {
        kAudioHardwarePropertyDefaultOutputDevice,
        kAudioObjectPropertyScopeGlobal, kAudioObjectPropertyElementMain
    };
    AudioObjectGetPropertyData(kAudioObjectSystemObject, &addr, 0, NULL, &size, &dev);
    return dev;
}

static AudioDeviceID xf_engine_device_by_uid(const char *uid) {
    if (!uid) return xf_engine_default_output_device();
    CFStringRef cf = CFStringCreateWithCString(NULL, uid, kCFStringEncodingUTF8);
    AudioDeviceID dev = kAudioObjectUnknown;
    AudioValueTranslation tr = { &cf, sizeof(cf), &dev, sizeof(dev) };
    UInt32 size = sizeof(tr);
    AudioObjectPropertyAddress addr = {
        kAudioHardwarePropertyDeviceForUID,
        kAudioObjectPropertyScopeGlobal, kAudioObjectPropertyElementMain
    };
    AudioObjectGetPropertyData(kAudioObjectSystemObject, &addr, 0, NULL, &size, &tr);
    CFRelease(cf);
    return dev != kAudioObjectUnknown ? dev : xf_engine_default_output_device();
}

static int xf_engine_start_impl(xf_engine *e, const char *device_uid, int with_input) {
    if (!e || e->au) return -1;
    e->capture_input = with_input ? 1 : 0;

    AudioDeviceID dev = xf_engine_device_by_uid(device_uid);
    if (dev == kAudioObjectUnknown) return -1;

    /* El motor (metronomo, tablas de resampling, ratios) esta calibrado a
     * `e->sample_rate`. Si el dispositivo corre a otra frecuencia (44,1k es
     * comun) todo suena desafinado y el click "raro". Forzamos el dispositivo a
     * `e->sample_rate`; si no la acepta, seguimos y CoreAudio hara la conversion. */
    Float64 targetSR = e->sample_rate;
    AudioObjectPropertyAddress srAddr = {
        kAudioDevicePropertyNominalSampleRate,
        kAudioObjectPropertyScopeGlobal, kAudioObjectPropertyElementMain
    };
    Float64 curSR = 0;
    UInt32 srSize = sizeof(curSR);
    if (AudioObjectGetPropertyData(dev, &srAddr, 0, NULL, &srSize, &curSR) == noErr &&
        curSR != targetSR) {
        AudioObjectSetPropertyData(dev, &srAddr, 0, NULL, sizeof(targetSR), &targetSR);
    }

    /* buffer del dispositivo = max_frames */
    UInt32 want = e->max_frames;
    AudioObjectPropertyAddress bufAddr = {
        kAudioDevicePropertyBufferFrameSize,
        kAudioObjectPropertyScopeGlobal, kAudioObjectPropertyElementMain
    };
    AudioObjectSetPropertyData(dev, &bufAddr, 0, NULL, sizeof(want), &want);

    AudioComponentDescription desc = {
        kAudioUnitType_Output, kAudioUnitSubType_HALOutput,
        kAudioUnitManufacturer_Apple, 0, 0
    };
    AudioComponent comp = AudioComponentFindNext(NULL, &desc);
    if (!comp) return -1;
    AudioUnit unit = NULL;
    if (AudioComponentInstanceNew(comp, &unit) != noErr || !unit) return -1;

    UInt32 yes = 1, no = 0;
    AudioUnitSetProperty(unit, kAudioOutputUnitProperty_EnableIO,
                         kAudioUnitScope_Input, 1, with_input ? &yes : &no, sizeof(yes));
    AudioUnitSetProperty(unit, kAudioOutputUnitProperty_EnableIO,
                         kAudioUnitScope_Output, 0, &yes, sizeof(yes));
    AudioUnitSetProperty(unit, kAudioOutputUnitProperty_CurrentDevice,
                         kAudioUnitScope_Global, 0, &dev, sizeof(dev));

    AudioStreamBasicDescription fmt = {0};
    fmt.mSampleRate       = e->sample_rate;
    fmt.mFormatID         = kAudioFormatLinearPCM;
    fmt.mFormatFlags      = kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked |
                            kAudioFormatFlagIsNonInterleaved;
    fmt.mBitsPerChannel   = 32;
    fmt.mChannelsPerFrame = 2;
    fmt.mFramesPerPacket  = 1;
    fmt.mBytesPerFrame    = 4;
    fmt.mBytesPerPacket   = 4;
    if (with_input) {
        AudioUnitSetProperty(unit, kAudioUnitProperty_StreamFormat,
                             kAudioUnitScope_Output, 1, &fmt, sizeof(fmt));
    }
    AudioUnitSetProperty(unit, kAudioUnitProperty_StreamFormat,
                         kAudioUnitScope_Input, 0, &fmt, sizeof(fmt));

    UInt32 slice = e->max_frames;
    AudioUnitSetProperty(unit, kAudioUnitProperty_MaximumFramesPerSlice,
                         kAudioUnitScope_Global, 0, &slice, sizeof(slice));

    /* ABL preasignada para la entrada (2 buffers no intercalados) */
    if (!e->in_abl) {
        e->in_abl = calloc(1, sizeof(AudioBufferList) + sizeof(AudioBuffer));
    }

    AURenderCallbackStruct cb = { .inputProc = xf_engine_render_cb, .inputProcRefCon = e };
    AudioUnitSetProperty(unit, kAudioUnitProperty_SetRenderCallback,
                         kAudioUnitScope_Input, 0, &cb, sizeof(cb));

    /* workgroup del hilo de IO (obligatorio en Apple Silicon) */
    e->workgroup = NULL;
    os_workgroup_t wg = NULL;
    UInt32 wgSize = sizeof(wg);
    AudioObjectPropertyAddress wgAddr = {
        kAudioDevicePropertyIOThreadOSWorkgroup,
        kAudioObjectPropertyScopeGlobal, kAudioObjectPropertyElementMain
    };
    if (AudioObjectGetPropertyData(dev, &wgAddr, 0, NULL, &wgSize, &wg) == noErr && wg) {
        e->workgroup = wg;   /* la referencia la retiene el engine hasta stop */
    }

    /* listener de overloads */
    AudioObjectPropertyAddress olAddr = {
        kAudioDeviceProcessorOverload,
        kAudioObjectPropertyScopeGlobal, kAudioObjectPropertyElementMain
    };
    AudioObjectAddPropertyListener(dev, &olAddr, xf_engine_on_overload, e);

    atomic_store(&e->rt_promoted, 0);
    if (AudioUnitInitialize(unit) != noErr) { AudioComponentInstanceDispose(unit); return -1; }
    if (AudioOutputUnitStart(unit) != noErr) {
        AudioUnitUninitialize(unit);
        AudioComponentInstanceDispose(unit);
        return -1;
    }
    e->au = unit;
    return 0;
}

int xf_engine_start(xf_engine *e, const char *device_uid) {
    return xf_engine_start_impl(e, device_uid, 1);
}

int xf_engine_start_output(xf_engine *e, const char *device_uid) {
    return xf_engine_start_impl(e, device_uid, 0);
}

void xf_engine_stop(xf_engine *e) {
    if (!e || !e->au) return;
    AudioOutputUnitStop((AudioUnit)e->au);
    AudioUnitUninitialize((AudioUnit)e->au);
    AudioComponentInstanceDispose((AudioUnit)e->au);
    e->au = NULL;
    /* El workgroup lo unio el HILO RT en el primer callback; `os_workgroup_leave`
     * TIENE que llamarse desde ese mismo hilo y aqui estamos en el hilo normal
     * (hacerlo aqui aborta con SIGILL). Al disponer la AudioUnit, el hilo de IO
     * desaparece y su pertenencia se limpia sola. Solo soltamos la referencia. */
    if (e->workgroup) {
        os_release(e->workgroup);
        e->workgroup = NULL;
    }
    atomic_store(&e->rt_promoted, 0);
}
