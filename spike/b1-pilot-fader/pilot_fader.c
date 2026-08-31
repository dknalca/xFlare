/* SPDX-License-Identifier: GPL-3.0-only */
/*
 * xFlare · spike B1.4 — deteccion del crossfader por tono piloto (ADR-021).
 *
 * QUE ES: un prototipo DESECHABLE que valida el metodo `audio_return` de
 * ADR-021. El crossfader de una mesa de battle (Rane 72, DJM-S11) NO manda su
 * posicion por MIDI. El plan: xFlare mezcla en su salida un tono piloto
 * inaudible (~19,5 kHz a -40 dBFS), captura el retorno del master de la mesa por
 * USB y mira si el tono llega o no. Tono presente = fader abierto; ausente =
 * cerrado. Este spike hace eso y mide con que rapidez y regularidad ve los
 * flancos de abrir/cerrar.
 *
 * CRITERIO (B1.4): detectar abrir/cerrar con jitter < 5 ms. Si no se logra ->
 * ADR con el plan C (fader MIDI externo barato) ANTES de seguir.
 *
 * CONEXION:
 *   - salida del ordenador -> entrada de linea de la mesa (al canal que
 *     gobierna el crossfader).
 *   - retorno USB del master de la mesa -> entrada del ordenador.
 *   (con --selfcheck basta un cable salida->entrada, sin mesa.)
 *
 * USO:
 *   ./build.sh
 *   ./pilot_fader --list
 *   ./pilot_fader --in-out "Rane" --selfcheck        # calibra umbrales, 3 s
 *   ./pilot_fader --in-out "Rane" --seconds 60       # abre y cierra el fader
 *
 * Reglas del hilo de audio (CLAUDE.md seccion 7): el callback solo hace
 * aritmetica acotada (Goertzel + histeresis), copia de una tabla precalculada
 * para el piloto y encola eventos en un ring SPSC. Cero malloc / locks / printf.
 */

#include <AudioToolbox/AudioToolbox.h>
#include <CoreAudio/CoreAudio.h>
#include <AudioUnit/AudioUnit.h>
#include <CoreFoundation/CoreFoundation.h>

#include <mach/mach_time.h>
#include <math.h>
#include <stdatomic.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <signal.h>
#include <time.h>

#ifndef kAudioObjectPropertyElementMain
#define kAudioObjectPropertyElementMain kAudioObjectPropertyElementMaster
#endif

/* ------------------------------------------------------------------ */
/* Parametros: se fijan en el arranque, el callback solo los lee.                */
/* ------------------------------------------------------------------ */
static double g_fs         = 48000.0;
static double g_freq       = 19500.0;   /* tono piloto */
static double g_level      = 0.01;      /* ~ -40 dBFS  (10^(-40/20)) */
static UInt32 g_hop        = 64;        /* muestras por analisis Goertzel */
static double g_on_dbfs    = -60.0;     /* histeresis: por encima -> abierto */
static double g_off_dbfs   = -72.0;     /* por debajo -> cerrado */
static UInt32 g_channels   = 1;
static UInt32 g_max_frames = 4096;

static double g_ns_per_tick    = 1.0;   /* mach ticks -> ns */
static double g_ticks_per_samp = 1.0;   /* muestras -> mach ticks */

/* Tabla del piloto: 1 s de sinusoide precalculada. A 48 kHz / 19,5 kHz son
 * 19500 ciclos exactos en 48000 muestras -> el bucle no tiene junta. Con otra
 * frecuencia habra un microsalto por vuelta, inaudible (ultrasonico, -40 dB). */
static float  *g_pilot     = NULL;
static UInt32  g_pilot_len = 48000;
static _Atomic uint64_t g_pilot_idx = 0;

/* Analizador -> hilo main. */
static _Atomic int32_t  g_tone_dbfs_x10 = -1200;  /* nivel actual, dBFS*10 */
static _Atomic uint64_t g_hops_done     = 0;

/* Ring SPSC de flancos. Productor: callback RT. Consumidor: main. */
#define EV_CAP 512
struct edge_ev { uint64_t tick; int32_t open; };
static struct edge_ev  g_ev[EV_CAP];
static _Atomic uint32_t g_ev_head = 0;
static _Atomic uint32_t g_ev_tail = 0;

/* Estado del detector: SOLO lo toca el hilo RT -> no necesita ser atomico. */
static bool rt_open = false;

static AudioUnit g_unit = NULL;
static AudioBufferList *g_in_abl = NULL;
static float *g_in_storage = NULL;

static volatile sig_atomic_t g_stop = 0;
static void on_sigint(int s) { (void)s; g_stop = 1; }

/* ------------------------------------------------------------------ */
/* Helpers de CoreAudio (hilo normal). Duplicados a proposito: es un spike       */
/* desechable, no un modulo. No creamos "utils comun" (CLAUDE.md).               */
/* ------------------------------------------------------------------ */
static const char *osstatus_str(OSStatus s, char buf[8]) {
    uint32_t be = CFSwapInt32HostToBig((uint32_t)s);
    memcpy(buf, &be, 4);
    if (buf[0] >= ' ' && buf[0] < 127 && buf[3] >= ' ' && buf[3] < 127) { buf[4] = 0; return buf; }
    snprintf(buf, 8, "%d", (int)s);
    return buf;
}
#define CHECK(expr, msg) do { OSStatus _s = (expr); if (_s != noErr) { char _b[8]; \
    fprintf(stderr, "  ERROR: %s  (%s)\n", (msg), osstatus_str(_s, _b)); return _s; } } while (0)

static AudioDeviceID default_output(void) {
    AudioObjectPropertyAddress a = { kAudioHardwarePropertyDefaultOutputDevice,
        kAudioObjectPropertyScopeGlobal, kAudioObjectPropertyElementMain };
    AudioDeviceID d = 0; UInt32 sz = sizeof(d);
    AudioObjectGetPropertyData(kAudioObjectSystemObject, &a, 0, NULL, &sz, &d);
    return d;
}
static UInt32 device_channels(AudioDeviceID dev, bool input) {
    AudioObjectPropertyAddress a = { kAudioDevicePropertyStreamConfiguration,
        input ? kAudioObjectPropertyScopeInput : kAudioObjectPropertyScopeOutput,
        kAudioObjectPropertyElementMain };
    UInt32 sz = 0;
    if (AudioObjectGetPropertyDataSize(dev, &a, 0, NULL, &sz) != noErr || sz == 0) return 0;
    AudioBufferList *bl = (AudioBufferList *)malloc(sz);
    UInt32 ch = 0;
    if (AudioObjectGetPropertyData(dev, &a, 0, NULL, &sz, bl) == noErr)
        for (UInt32 i = 0; i < bl->mNumberBuffers; i++) ch += bl->mBuffers[i].mNumberChannels;
    free(bl);
    return ch;
}
static void device_name(AudioDeviceID dev, char *out, size_t n) {
    AudioObjectPropertyAddress a = { kAudioObjectPropertyName,
        kAudioObjectPropertyScopeGlobal, kAudioObjectPropertyElementMain };
    CFStringRef s = NULL; UInt32 sz = sizeof(s); out[0] = 0;
    if (AudioObjectGetPropertyData(dev, &a, 0, NULL, &sz, &s) == noErr && s) {
        CFStringGetCString(s, out, (CFIndex)n, kCFStringEncodingUTF8); CFRelease(s);
    }
}
static double device_sr(AudioDeviceID dev) {
    AudioObjectPropertyAddress a = { kAudioDevicePropertyNominalSampleRate,
        kAudioObjectPropertyScopeGlobal, kAudioObjectPropertyElementMain };
    Float64 sr = 0; UInt32 sz = sizeof(sr);
    AudioObjectGetPropertyData(dev, &a, 0, NULL, &sz, &sr);
    return (double)sr;
}
static void set_buffer_frames(AudioDeviceID dev, UInt32 f) {
    AudioObjectPropertyAddress a = { kAudioDevicePropertyBufferFrameSize,
        kAudioObjectPropertyScopeGlobal, kAudioObjectPropertyElementMain };
    AudioObjectSetPropertyData(dev, &a, 0, NULL, sizeof(f), &f);
}

/* ------------------------------------------------------------------ */
/* Goertzel de un solo bin sobre 'n' muestras: cuanta energia hay a g_freq.      */
/* Acotado y sin memoria -> RT-safe. sin/cos/log10 son libm (no syscalls); en    */
/* produccion se usaria una LUT, aqui vale.                                      */
/* ------------------------------------------------------------------ */
static double goertzel_dbfs(const float *x, UInt32 n) {
    double w = 2.0 * M_PI * g_freq / g_fs;
    double coeff = 2.0 * cos(w);
    double s1 = 0, s2 = 0, s0;
    for (UInt32 i = 0; i < n; i++) {
        s0 = (double)x[i] + coeff * s1 - s2;
        s2 = s1; s1 = s0;
    }
    double power = s1 * s1 + s2 * s2 - coeff * s1 * s2;
    double mag = sqrt(power > 0 ? power : 0) * (2.0 / (double)n);
    return 20.0 * log10(mag + 1e-12);
}

/* ------------------------------------------------------------------ */
/* CALLBACK RT.                                                                  */
/* ------------------------------------------------------------------ */
static OSStatus render_cb(void *ref, AudioUnitRenderActionFlags *flags,
                          const AudioTimeStamp *ts, UInt32 bus, UInt32 frames,
                          AudioBufferList *out) {
    (void)ref; (void)bus;
    if (frames > g_max_frames) frames = g_max_frames;

    /* 1) Piloto en todos los canales de salida, desde la tabla precalculada. */
    uint64_t pidx = atomic_load_explicit(&g_pilot_idx, memory_order_relaxed);
    for (UInt32 b = 0; b < out->mNumberBuffers; b++) {
        float *o = (float *)out->mBuffers[b].mData;
        uint64_t k = pidx;
        for (UInt32 i = 0; i < frames; i++) {
            o[i] = g_pilot[k];
            if (++k >= g_pilot_len) k = 0;
        }
    }
    atomic_store_explicit(&g_pilot_idx, (pidx + frames) % g_pilot_len, memory_order_relaxed);

    /* 2) Tirar de la entrada a buffers preasignados. */
    for (UInt32 c = 0; c < g_channels; c++) {
        g_in_abl->mBuffers[c].mNumberChannels = 1;
        g_in_abl->mBuffers[c].mDataByteSize   = frames * (UInt32)sizeof(float);
        g_in_abl->mBuffers[c].mData           = g_in_storage + (size_t)c * g_max_frames;
    }
    g_in_abl->mNumberBuffers = g_channels;
    OSStatus err = AudioUnitRender(g_unit, flags, ts, 1, frames, g_in_abl);
    if (err != noErr) return noErr;   /* sin entrada este tic */

    /* 3) Analizar la entrada (canal 0) por hops: nivel del tono + histeresis.
     *    Al cambiar de estado, encolar el flanco con su instante aproximado. */
    const float *in0 = (const float *)g_in_abl->mBuffers[0].mData;
    uint64_t now = mach_absolute_time();
    for (UInt32 off = 0; off + g_hop <= frames; off += g_hop) {
        double db = goertzel_dbfs(in0 + off, g_hop);
        atomic_store_explicit(&g_tone_dbfs_x10, (int32_t)lround(db * 10.0), memory_order_relaxed);
        atomic_fetch_add_explicit(&g_hops_done, 1, memory_order_relaxed);

        bool next = rt_open;
        if (!rt_open && db > g_on_dbfs)  next = true;
        if ( rt_open && db < g_off_dbfs) next = false;
        if (next != rt_open) {
            rt_open = next;
            uint64_t tick = now + (uint64_t)((double)off * g_ticks_per_samp);
            uint32_t h = atomic_load_explicit(&g_ev_head, memory_order_relaxed);
            uint32_t t = atomic_load_explicit(&g_ev_tail, memory_order_acquire);
            if (h - t < EV_CAP) {
                g_ev[h % EV_CAP].tick = tick;
                g_ev[h % EV_CAP].open = next ? 1 : 0;
                atomic_store_explicit(&g_ev_head, h + 1, memory_order_release);
            }
        }
    }
    return noErr;
}

/* ------------------------------------------------------------------ */
static int list_devices(void) {
    AudioObjectPropertyAddress a = { kAudioHardwarePropertyDevices,
        kAudioObjectPropertyScopeGlobal, kAudioObjectPropertyElementMain };
    UInt32 sz = 0;
    if (AudioObjectGetPropertyDataSize(kAudioObjectSystemObject, &a, 0, NULL, &sz) != noErr) return 1;
    UInt32 count = sz / (UInt32)sizeof(AudioDeviceID);
    AudioDeviceID *devs = (AudioDeviceID *)malloc(sz);
    AudioObjectGetPropertyData(kAudioObjectSystemObject, &a, 0, NULL, &sz, devs);
    printf("  %-40s  in  out   sr(Hz)\n", "nombre");
    printf("  ---------------------------------------- ---- ----  -------\n");
    for (UInt32 i = 0; i < count; i++) {
        char nm[128]; device_name(devs[i], nm, sizeof(nm));
        printf("  %-40.40s %3u  %3u  %7.0f\n", nm,
               device_channels(devs[i], true), device_channels(devs[i], false),
               device_sr(devs[i]));
    }
    free(devs);
    printf("\n  necesitas un dispositivo con in>0 Y out>0 (duplex).\n");
    return 0;
}

/* ------------------------------------------------------------------ */
static void build_pilot(void) {
    g_pilot_len = (UInt32)llround(g_fs);          /* 1 segundo */
    g_pilot = (float *)malloc((size_t)g_pilot_len * sizeof(float));
    for (UInt32 i = 0; i < g_pilot_len; i++)
        g_pilot[i] = (float)(g_level * sin(2.0 * M_PI * g_freq * (double)i / g_fs));
}

static OSStatus build_unit(AudioDeviceID dev) {
    AudioComponentDescription desc = {
        kAudioUnitType_Output, kAudioUnitSubType_HALOutput,
        kAudioUnitManufacturer_Apple, 0, 0 };
    AudioComponent comp = AudioComponentFindNext(NULL, &desc);
    if (!comp) { fprintf(stderr, "  no encuentro la HAL AudioUnit\n"); return -1; }
    CHECK(AudioComponentInstanceNew(comp, &g_unit), "AudioComponentInstanceNew");

    UInt32 yes = 1;
    CHECK(AudioUnitSetProperty(g_unit, kAudioOutputUnitProperty_EnableIO,
          kAudioUnitScope_Input, 1, &yes, sizeof(yes)), "EnableIO input");
    CHECK(AudioUnitSetProperty(g_unit, kAudioOutputUnitProperty_EnableIO,
          kAudioUnitScope_Output, 0, &yes, sizeof(yes)), "EnableIO output");
    CHECK(AudioUnitSetProperty(g_unit, kAudioOutputUnitProperty_CurrentDevice,
          kAudioUnitScope_Global, 0, &dev, sizeof(dev)), "CurrentDevice");

    AudioStreamBasicDescription fmt = {0};
    fmt.mSampleRate = g_fs;
    fmt.mFormatID = kAudioFormatLinearPCM;
    fmt.mFormatFlags = kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked | kAudioFormatFlagIsNonInterleaved;
    fmt.mBitsPerChannel = 32;
    fmt.mChannelsPerFrame = g_channels;
    fmt.mFramesPerPacket = 1;
    fmt.mBytesPerFrame = 4;
    fmt.mBytesPerPacket = 4;
    CHECK(AudioUnitSetProperty(g_unit, kAudioUnitProperty_StreamFormat,
          kAudioUnitScope_Output, 1, &fmt, sizeof(fmt)), "StreamFormat entrada");
    CHECK(AudioUnitSetProperty(g_unit, kAudioUnitProperty_StreamFormat,
          kAudioUnitScope_Input, 0, &fmt, sizeof(fmt)), "StreamFormat salida");
    CHECK(AudioUnitSetProperty(g_unit, kAudioUnitProperty_MaximumFramesPerSlice,
          kAudioUnitScope_Global, 0, &g_max_frames, sizeof(g_max_frames)), "MaxFramesPerSlice");

    AURenderCallbackStruct cb = { render_cb, NULL };
    CHECK(AudioUnitSetProperty(g_unit, kAudioUnitProperty_SetRenderCallback,
          kAudioUnitScope_Input, 0, &cb, sizeof(cb)), "SetRenderCallback");
    CHECK(AudioUnitInitialize(g_unit), "AudioUnitInitialize");
    return noErr;
}

/* ------------------------------------------------------------------ */
static void usage(const char *p) {
    printf("uso: %s [--list] [--in-out <substr>] [--seconds N] [--selfcheck]\n", p);
    printf("           [--freq HZ] [--level-db DB] [--hop N] [--on DB] [--off DB]\n");
    printf("  --list         enumera dispositivos y sale\n");
    printf("  --in-out <s>   dispositivo (mismo in y out) cuyo nombre contenga <s>\n");
    printf("  --seconds N    duracion (por defecto 60)\n");
    printf("  --selfcheck    3 s midiendo el tono en bucle directo; sugiere umbrales\n");
    printf("  --freq / --level-db / --hop / --on / --off   ajustes finos\n");
}

int main(int argc, char **argv) {
    setvbuf(stdout, NULL, _IOLBF, 0);   /* logs legibles aunque se redirija a fichero */
    const char *pick = NULL;
    int seconds = 60;
    bool selfcheck = false;

    for (int i = 1; i < argc; i++) {
        if (!strcmp(argv[i], "--list")) { /* se resuelve tras nada mas */ return list_devices(); }
        else if (!strcmp(argv[i], "--in-out") && i+1 < argc) pick = argv[++i];
        else if (!strcmp(argv[i], "--seconds") && i+1 < argc) seconds = atoi(argv[++i]);
        else if (!strcmp(argv[i], "--selfcheck")) selfcheck = true;
        else if (!strcmp(argv[i], "--freq") && i+1 < argc) g_freq = atof(argv[++i]);
        else if (!strcmp(argv[i], "--level-db") && i+1 < argc) g_level = pow(10.0, atof(argv[++i]) / 20.0);
        else if (!strcmp(argv[i], "--hop") && i+1 < argc) g_hop = (UInt32)atoi(argv[++i]);
        else if (!strcmp(argv[i], "--on") && i+1 < argc) g_on_dbfs = atof(argv[++i]);
        else if (!strcmp(argv[i], "--off") && i+1 < argc) g_off_dbfs = atof(argv[++i]);
        else { usage(argv[0]); return strcmp(argv[i], "--help") ? 2 : 0; }
    }

    mach_timebase_info_data_t tb; mach_timebase_info(&tb);
    g_ns_per_tick = (double)tb.numer / (double)tb.denom;

    /* --- dispositivo --- */
    AudioDeviceID dev = 0;
    if (pick) {
        AudioObjectPropertyAddress a = { kAudioHardwarePropertyDevices,
            kAudioObjectPropertyScopeGlobal, kAudioObjectPropertyElementMain };
        UInt32 sz = 0;
        AudioObjectGetPropertyDataSize(kAudioObjectSystemObject, &a, 0, NULL, &sz);
        UInt32 count = sz / (UInt32)sizeof(AudioDeviceID);
        AudioDeviceID *devs = (AudioDeviceID *)malloc(sz);
        AudioObjectGetPropertyData(kAudioObjectSystemObject, &a, 0, NULL, &sz, devs);
        for (UInt32 i = 0; i < count; i++) {
            char nm[128]; device_name(devs[i], nm, sizeof(nm));
            if (strcasestr(nm, pick)) { dev = devs[i]; break; }
        }
        free(devs);
        if (!dev) { fprintf(stderr, "  no hay dispositivo con \"%s\". Prueba --list\n", pick); return 1; }
    } else {
        dev = default_output();
        printf("  sin --in-out: uso la salida por defecto. Si no tiene entrada, no habra deteccion.\n");
    }

    char dname[128]; device_name(dev, dname, sizeof(dname));
    UInt32 ci = device_channels(dev, true), co = device_channels(dev, false);
    g_channels = (ci < co ? ci : co); if (g_channels < 1) g_channels = 1; if (g_channels > 8) g_channels = 8;
    double sr = device_sr(dev);
    if (sr > 0) g_fs = sr;
    g_ticks_per_samp = (1e9 / g_ns_per_tick) / g_fs;

    printf("\n  dispositivo : \"%s\"   in=%u  out=%u\n", dname, ci, co);
    printf("  piloto      : %.0f Hz  a  %.1f dBFS   (hop %u = %.2f ms)\n",
           g_freq, 20.0 * log10(g_level), g_hop, 1000.0 * g_hop / g_fs);
    printf("  histeresis  : abre > %.0f dBFS   cierra < %.0f dBFS\n", g_on_dbfs, g_off_dbfs);
    if (g_fs != 48000.0)
        printf("  NOTA: fs=%.0f (no 48000): la tabla del piloto tendra un microsalto por vuelta.\n", g_fs);
    if (ci == 0) { fprintf(stderr, "  este dispositivo no tiene entrada; no se puede validar nada.\n"); return 1; }

    set_buffer_frames(dev, 64);
    build_pilot();
    g_in_storage = (float *)calloc((size_t)g_channels * g_max_frames, sizeof(float));
    g_in_abl = (AudioBufferList *)calloc(1, sizeof(AudioBufferList) + (g_channels - 1) * sizeof(AudioBuffer));
    if (!g_pilot || !g_in_storage || !g_in_abl) { fprintf(stderr, "  sin memoria\n"); return 1; }

    if (build_unit(dev) != noErr) return 1;
    OSStatus started = AudioOutputUnitStart(g_unit);
    if (started != noErr) { char b[8]; fprintf(stderr, "  AudioOutputUnitStart: %s\n", osstatus_str(started, b)); return 1; }

    signal(SIGINT, on_sigint);
    struct timespec tenths = { .tv_sec = 0, .tv_nsec = 100 * 1000 * 1000 };

    /* ---------------- SELFCHECK ---------------- */
    if (selfcheck) {
        printf("\n  === SELFCHECK ===  bucle directo salida->entrada, 3 s. No toques nada.\n");
        double lo = 1e9, hi = -1e9, sum = 0; int k = 0;
        for (int i = 0; i < 30 && !g_stop; i++) {
            nanosleep(&tenths, NULL);
            double db = atomic_load(&g_tone_dbfs_x10) / 10.0;
            if (i >= 3) { if (db < lo) lo = db; if (db > hi) hi = db; sum += db; k++; }
            printf("\r  tono ahora: %6.1f dBFS   ", db); fflush(stdout);
        }
        printf("\n");
        AudioOutputUnitStop(g_unit); AudioUnitUninitialize(g_unit);
        AudioComponentInstanceDispose(g_unit);
        double mean = k ? sum / k : -120;
        printf("\n  tono presente (bucle directo): min %.1f  media %.1f  max %.1f dBFS\n", lo, mean, hi);
        printf("  ruido de fondo esperado con el fader CERRADO: bastante por debajo de %.1f.\n", lo);
        printf("  sugerencia de umbrales:  --on %.0f   --off %.0f\n",
               floor(mean - 8), floor(mean - 20));
        printf("  (si 'min' < -70 el piloto no sobrevive el viaje: sube --level-db o revisa el cableado)\n");
        free(g_pilot); free(g_in_abl); free(g_in_storage);
        return 0;
    }

    /* ---------------- DETECCION ---------------- */
    printf("\n  === DETECCION EN MARCHA ===  abre y cierra el crossfader. (Ctrl-C para parar)\n\n");
    uint64_t last_tick = 0;
    int n_edges = 0;
    double intervals_ms[EV_CAP];
    int n_int = 0;

    for (int i = 0; i < seconds * 10 && !g_stop; i++) {
        nanosleep(&tenths, NULL);

        /* drenar el ring de flancos */
        uint32_t t = atomic_load_explicit(&g_ev_tail, memory_order_relaxed);
        uint32_t h = atomic_load_explicit(&g_ev_head, memory_order_acquire);
        while (t != h) {
            struct edge_ev e = g_ev[t % EV_CAP];
            atomic_store_explicit(&g_ev_tail, ++t, memory_order_release);
            n_edges++;
            double dt_ms = last_tick ? (double)(e.tick - last_tick) * g_ns_per_tick / 1e6 : 0.0;
            if (last_tick && n_int < EV_CAP) intervals_ms[n_int++] = dt_ms;
            last_tick = e.tick;
            printf("  %-6s   t=%8.1f ms desde el flanco anterior\n",
                   e.open ? "ABRE" : "cierra", dt_ms);
        }

        double db = atomic_load(&g_tone_dbfs_x10) / 10.0;
        printf("\r  [tono %6.1f dBFS  estado %-7s  flancos %d]   ",
               db, atomic_load(&g_ev_head) != atomic_load(&g_ev_tail) ? "?" : (db > g_on_dbfs ? "ABIERTO" : "cerrado"),
               n_edges);
        fflush(stdout);
    }
    printf("\n");

    AudioOutputUnitStop(g_unit);
    AudioUnitUninitialize(g_unit);
    AudioComponentInstanceDispose(g_unit);

    printf("\n  ---------------- RESUMEN B1.4 ----------------\n");
    printf("  dispositivo   : %s\n", dname);
    printf("  hops analizados: %llu   (%.2f ms de resolucion por hop)\n",
           (unsigned long long)atomic_load(&g_hops_done), 1000.0 * g_hop / g_fs);
    printf("  flancos vistos : %d\n", n_edges);
    if (n_int > 0) {
        double mn = 1e9, mx = -1e9, s = 0;
        for (int i = 0; i < n_int; i++) { double v = intervals_ms[i]; if (v<mn)mn=v; if (v>mx)mx=v; s+=v; }
        double mean = s / n_int;
        double var = 0;
        for (int i = 0; i < n_int; i++) { double d = intervals_ms[i] - mean; var += d*d; }
        double sd = sqrt(var / n_int);
        printf("  intervalos entre flancos: min %.1f  media %.1f  max %.1f ms\n", mn, mean, mx);
        printf("  dispersion (desv. tipica): %.2f ms\n", sd);
        printf("\n  la resolucion de deteccion es 1 hop = %.2f ms. Para el criterio de\n"
               "  B1.4 (< 5 ms de jitter) haz aperturas/cierres a ritmo constante con el\n"
               "  metronomo y comprueba que la desv. tipica de los intervalos se queda\n"
               "  por debajo de 5 ms. Si no -> ADR con el plan C.\n", 1000.0 * g_hop / g_fs);
    } else {
        printf("  (no hubo flancos: mueve el crossfader, o ajusta --on/--off con --selfcheck)\n");
    }
    printf("  ---------------------------------------------\n");

    free(g_pilot); free(g_in_abl); free(g_in_storage);
    return n_edges > 0 ? 0 : 1;
}
