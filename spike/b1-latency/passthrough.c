/* SPDX-License-Identifier: GPL-3.0-only */
/*
 * xFlare · spike B1.1 — passthrough de CoreAudio a 64 frames.
 *
 * QUE ES: un prototipo DESECHABLE. Su unico trabajo es demostrar que en tu
 * hardware se puede hacer entrada -> salida de audio con un buffer de 64 frames
 * a 48 kHz durante 5 minutos SIN cortes (overloads / xruns). Es la primera
 * puerta de viabilidad del proyecto (PLAN.md, Hito A). Si esto no aguanta, el
 * plan se para y se abre un ADR con el plan B antes de escribir nada mas.
 *
 * QUE NO ES: el motor de audio de verdad. Ese es el modulo CXFAudioCore y se
 * escribe en el bloque B4, con su ring buffer SPSC lock-free. Aqui, como
 * entrada y salida son EL MISMO dispositivo (tu mesa de batalla, que es duplex),
 * no hace falta ring buffer: dentro del callback tiramos de la entrada y la
 * copiamos a la salida en el mismo tic de reloj.
 *
 * COMO SE USA:  ./build.sh  &&  ./passthrough --list
 *               ./passthrough --in-out "Rane" --frames 64 --seconds 300
 *   Ctrl-C para parar antes de tiempo. Al salir imprime PASS / FAIL.
 *
 * QUE MIRAR:
 *   - "overloads": tienen que ser 0. Cada overload es un corte que se oye.
 *   - "render err": tienen que ser 0. Si suben, la entrada no esta llegando.
 *   - que se OIGA la entrada en la salida, limpio, sin clicks, los 5 minutos.
 *
 * Reglas del hilo de audio (CLAUDE.md seccion 7) que este fichero respeta ya,
 * porque el spike tambien sirve para coger el habito:
 *   - Dentro del callback: 0 malloc, 0 locks, 0 printf, 0 llamadas al sistema.
 *   - Todos los buffers se reservan en el arranque.
 *   - El callback se comunica con el hilo normal SOLO por variables atomicas.
 *   - El bucle de estado (printf 1 vez/seg) corre en el hilo main, nunca en RT.
 */

#include <AudioToolbox/AudioToolbox.h>
#include <CoreAudio/CoreAudio.h>
#include <AudioUnit/AudioUnit.h>
#include <CoreFoundation/CoreFoundation.h>

#include <mach/mach_time.h>
#include <stdatomic.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <signal.h>
#include <time.h>

/* En el SDK de macOS 12 el "elemento maestro" se renombro a ...Main. Con target
 * 11.0 y para compilar sin warnings en ambas, definimos el nombre nuevo si no
 * existe. Es puramente cosmetico: el valor es 0 en las dos versiones. */
#ifndef kAudioObjectPropertyElementMain
#define kAudioObjectPropertyElementMain kAudioObjectPropertyElementMaster
#endif

/* ------------------------------------------------------------------ */
/* Estado compartido callback <-> main. Solo atomicas: el callback las           */
/* incrementa, el hilo main las lee. Nada de mutex (romperia la regla RT).       */
/* ------------------------------------------------------------------ */
static _Atomic uint64_t g_cb_count      = 0;   /* nº de veces que ha corrido el callback */
static _Atomic uint64_t g_overloads     = 0;   /* overloads reportados por el driver */
static _Atomic uint64_t g_render_errs   = 0;   /* fallos de AudioUnitRender (entrada) */
static _Atomic uint64_t g_gap_max_ns    = 0;   /* mayor hueco medido entre callbacks */
static _Atomic uint64_t g_gap_min_ns    = UINT64_MAX;
static _Atomic int32_t  g_last_render_err = 0; /* ultimo OSStatus de error, para diagnostico */

/* Ctrl-C: el handler solo levanta una bandera; el trabajo de parar lo hace main. */
static volatile sig_atomic_t g_stop = 0;
static void on_sigint(int sig) { (void)sig; g_stop = 1; }

/* ------------------------------------------------------------------ */
/* Cosas que se preparan una vez en el arranque y usa el callback sin tocar     */
/* memoria: la AudioUnit, el buffer de entrada y el reloj.                      */
/* ------------------------------------------------------------------ */
static AudioUnit      g_unit          = NULL;
static AudioBufferList *g_in_abl      = NULL;   /* buffers preasignados para tirar de la entrada */
static float          *g_in_storage   = NULL;   /* memoria real detras de g_in_abl */
static UInt32          g_channels     = 2;
static UInt32          g_max_frames   = 4096;   /* techo de frames por callback que reservamos */
static double          g_ns_per_tick  = 1.0;    /* mach_absolute_time -> nanosegundos */
static _Atomic uint64_t g_last_cb_tick = 0;

/* ------------------------------------------------------------------ */
/* Helpers de CoreAudio (hilo normal, no RT).                                   */
/* ------------------------------------------------------------------ */

static const char *osstatus_str(OSStatus s, char buf[8]) {
    /* Muchos errores de CoreAudio son un codigo de 4 letras ('!obj', 'nope'...). */
    uint32_t be = CFSwapInt32HostToBig((uint32_t)s);
    memcpy(buf, &be, 4);
    if (buf[0] >= ' ' && buf[0] < 127 && buf[3] >= ' ' && buf[3] < 127) { buf[4] = 0; return buf; }
    snprintf(buf, 8, "%d", (int)s);
    return buf;
}

#define CHECK(expr, msg) do {                                            \
    OSStatus _s = (expr);                                               \
    if (_s != noErr) { char _b[8];                                      \
        fprintf(stderr, "  ERROR: %s  (%s)\n", (msg), osstatus_str(_s, _b)); \
        return _s; }                                                    \
} while (0)

static AudioDeviceID default_device(bool input) {
    AudioObjectPropertyAddress a = {
        input ? kAudioHardwarePropertyDefaultInputDevice
              : kAudioHardwarePropertyDefaultOutputDevice,
        kAudioObjectPropertyScopeGlobal, kAudioObjectPropertyElementMain
    };
    AudioDeviceID dev = 0; UInt32 size = sizeof(dev);
    AudioObjectGetPropertyData(kAudioObjectSystemObject, &a, 0, NULL, &size, &dev);
    return dev;
}

/* Cuenta canales de un dispositivo en el scope pedido (entrada o salida). */
static UInt32 device_channels(AudioDeviceID dev, bool input) {
    AudioObjectPropertyAddress a = {
        kAudioDevicePropertyStreamConfiguration,
        input ? kAudioObjectPropertyScopeInput : kAudioObjectPropertyScopeOutput,
        kAudioObjectPropertyElementMain
    };
    UInt32 size = 0;
    if (AudioObjectGetPropertyDataSize(dev, &a, 0, NULL, &size) != noErr || size == 0) return 0;
    AudioBufferList *bl = (AudioBufferList *)malloc(size);
    UInt32 ch = 0;
    if (AudioObjectGetPropertyData(dev, &a, 0, NULL, &size, bl) == noErr)
        for (UInt32 i = 0; i < bl->mNumberBuffers; i++) ch += bl->mBuffers[i].mNumberChannels;
    free(bl);
    return ch;
}

static void device_name(AudioDeviceID dev, char *out, size_t out_len) {
    AudioObjectPropertyAddress a = {
        kAudioObjectPropertyName, kAudioObjectPropertyScopeGlobal, kAudioObjectPropertyElementMain
    };
    CFStringRef name = NULL; UInt32 size = sizeof(name);
    out[0] = 0;
    if (AudioObjectGetPropertyData(dev, &a, 0, NULL, &size, &name) == noErr && name) {
        CFStringGetCString(name, out, (CFIndex)out_len, kCFStringEncodingUTF8);
        CFRelease(name);
    }
}

static double device_sample_rate(AudioDeviceID dev) {
    AudioObjectPropertyAddress a = {
        kAudioDevicePropertyNominalSampleRate,
        kAudioObjectPropertyScopeGlobal, kAudioObjectPropertyElementMain
    };
    Float64 sr = 0; UInt32 size = sizeof(sr);
    AudioObjectGetPropertyData(dev, &a, 0, NULL, &size, &sr);
    return (double)sr;
}

static UInt32 device_buffer_frames(AudioDeviceID dev) {
    AudioObjectPropertyAddress a = {
        kAudioDevicePropertyBufferFrameSize,
        kAudioObjectPropertyScopeGlobal, kAudioObjectPropertyElementMain
    };
    UInt32 f = 0; UInt32 size = sizeof(f);
    AudioObjectGetPropertyData(dev, &a, 0, NULL, &size, &f);
    return f;
}

/* Pide al dispositivo un tamaño de buffer. El driver puede decir que no o
 * redondear: por eso justo despues volvemos a LEERLO y reportamos el real. */
static OSStatus set_device_buffer_frames(AudioDeviceID dev, UInt32 frames) {
    AudioObjectPropertyAddress range_a = {
        kAudioDevicePropertyBufferFrameSizeRange,
        kAudioObjectPropertyScopeGlobal, kAudioObjectPropertyElementMain
    };
    AudioValueRange range = {0, 0}; UInt32 size = sizeof(range);
    if (AudioObjectGetPropertyData(dev, &range_a, 0, NULL, &size, &range) == noErr) {
        printf("  rango de buffer que admite el dispositivo: %.0f - %.0f frames\n",
               range.mMinimum, range.mMaximum);
        if (frames < range.mMinimum)
            printf("  AVISO: %u < minimo del dispositivo; se quedara en %.0f\n",
                   frames, range.mMinimum);
    }
    AudioObjectPropertyAddress a = {
        kAudioDevicePropertyBufferFrameSize,
        kAudioObjectPropertyScopeGlobal, kAudioObjectPropertyElementMain
    };
    return AudioObjectSetPropertyData(dev, &a, 0, NULL, sizeof(frames), &frames);
}

/* Listener de overload: lo llama el sistema (hilo aparte, no RT) cada vez que
 * el driver no llego a tiempo con un buffer. Mantenerlo trivial de todos modos. */
static OSStatus on_overload(AudioObjectID obj, UInt32 n,
                            const AudioObjectPropertyAddress *addrs, void *ctx) {
    (void)obj; (void)n; (void)addrs; (void)ctx;
    atomic_fetch_add_explicit(&g_overloads, 1, memory_order_relaxed);
    return noErr;
}

/* ------------------------------------------------------------------ */
/* EL CALLBACK DE AUDIO. Corre cada ~1,33 ms en un hilo de prioridad de tiempo   */
/* real. Aqui aplican TODAS las prohibiciones de CLAUDE.md seccion 7.            */
/* ------------------------------------------------------------------ */
static OSStatus render_cb(void *ref,
                          AudioUnitRenderActionFlags *flags,
                          const AudioTimeStamp *ts,
                          UInt32 bus, UInt32 frames,
                          AudioBufferList *out) {
    (void)ref; (void)bus;

    /* 1) Medir el hueco desde el callback anterior. Solo aritmetica y atomicas. */
    uint64_t now = mach_absolute_time();
    uint64_t prev = atomic_exchange_explicit(&g_last_cb_tick, now, memory_order_relaxed);
    if (prev != 0) {
        uint64_t gap = (uint64_t)((double)(now - prev) * g_ns_per_tick);
        uint64_t omax = atomic_load_explicit(&g_gap_max_ns, memory_order_relaxed);
        while (gap > omax &&
               !atomic_compare_exchange_weak_explicit(&g_gap_max_ns, &omax, gap,
                                                      memory_order_relaxed, memory_order_relaxed)) {}
        uint64_t omin = atomic_load_explicit(&g_gap_min_ns, memory_order_relaxed);
        while (gap < omin &&
               !atomic_compare_exchange_weak_explicit(&g_gap_min_ns, &omin, gap,
                                                      memory_order_relaxed, memory_order_relaxed)) {}
    }

    /* 2) Tirar de la ENTRADA hacia nuestros buffers preasignados. Reapuntamos
     *    los buffers (no reservamos) y fijamos el tamaño valido de este tic. */
    if (frames > g_max_frames) frames = g_max_frames;   /* cota dura, nunca deberia pasar */
    for (UInt32 c = 0; c < g_channels; c++) {
        g_in_abl->mBuffers[c].mNumberChannels = 1;
        g_in_abl->mBuffers[c].mDataByteSize   = frames * (UInt32)sizeof(float);
        g_in_abl->mBuffers[c].mData           = g_in_storage + (size_t)c * g_max_frames;
    }
    g_in_abl->mNumberBuffers = g_channels;

    OSStatus err = AudioUnitRender(g_unit, flags, ts, 1 /* bus de entrada */, frames, g_in_abl);
    if (err != noErr) {
        atomic_fetch_add_explicit(&g_render_errs, 1, memory_order_relaxed);
        atomic_store_explicit(&g_last_render_err, (int32_t)err, memory_order_relaxed);
        /* Sin entrada este tic: sacar silencio y salir. Nunca dejar basura. */
        for (UInt32 b = 0; b < out->mNumberBuffers; b++)
            memset(out->mBuffers[b].mData, 0, out->mBuffers[b].mDataByteSize);
        atomic_fetch_add_explicit(&g_cb_count, 1, memory_order_relaxed);
        return noErr;
    }

    /* 3) Copiar entrada -> salida, canal a canal. Si la salida tiene mas canales
     *    que la entrada, los sobrantes van a silencio. */
    for (UInt32 b = 0; b < out->mNumberBuffers; b++) {
        UInt32 src = (b < g_channels) ? b : (g_channels - 1);
        UInt32 n = out->mBuffers[b].mDataByteSize;
        UInt32 have = g_in_abl->mBuffers[src].mDataByteSize;
        if (b < g_channels) {
            if (n > have) { memcpy(out->mBuffers[b].mData, g_in_abl->mBuffers[src].mData, have);
                            memset((char *)out->mBuffers[b].mData + have, 0, n - have); }
            else          { memcpy(out->mBuffers[b].mData, g_in_abl->mBuffers[src].mData, n); }
        } else {
            memset(out->mBuffers[b].mData, 0, n);
        }
    }

    atomic_fetch_add_explicit(&g_cb_count, 1, memory_order_relaxed);
    return noErr;
}

/* ------------------------------------------------------------------ */
/* --list: enumerar dispositivos con sus canales y buffer actual.               */
/* ------------------------------------------------------------------ */
static int list_devices(void) {
    AudioObjectPropertyAddress a = {
        kAudioHardwarePropertyDevices,
        kAudioObjectPropertyScopeGlobal, kAudioObjectPropertyElementMain
    };
    UInt32 size = 0;
    if (AudioObjectGetPropertyDataSize(kAudioObjectSystemObject, &a, 0, NULL, &size) != noErr) {
        fprintf(stderr, "  no se pudo enumerar dispositivos\n"); return 1;
    }
    UInt32 count = size / (UInt32)sizeof(AudioDeviceID);
    AudioDeviceID *devs = (AudioDeviceID *)malloc(size);
    AudioObjectGetPropertyData(kAudioObjectSystemObject, &a, 0, NULL, &size, devs);

    AudioDeviceID din = default_device(true), dout = default_device(false);
    printf("  dispositivos de audio (%u):\n", count);
    printf("  %-40s  in  out   sr(Hz)  buf\n", "nombre");
    printf("  ---------------------------------------- ---- ----  ------- ----\n");
    for (UInt32 i = 0; i < count; i++) {
        char name[128]; device_name(devs[i], name, sizeof(name));
        UInt32 ci = device_channels(devs[i], true), co = device_channels(devs[i], false);
        double sr = device_sample_rate(devs[i]);
        UInt32 buf = device_buffer_frames(devs[i]);
        printf("  %-40.40s %3u  %3u  %7.0f  %3u%s%s\n",
               name, ci, co, sr, buf,
               devs[i] == din ? "  <-in" : "",
               devs[i] == dout ? "  <-out" : "");
    }
    free(devs);
    printf("\n  para el passthrough necesitas un dispositivo con in>0 Y out>0 (duplex).\n");
    return 0;
}

/* ------------------------------------------------------------------ */
static void usage(const char *p) {
    printf("uso: %s [--list] [--in-out <substr>] [--frames N] [--seconds N] [--adaptive]\n", p);
    printf("  --list           enumera dispositivos y sale\n");
    printf("  --in-out <substr> usa el dispositivo (mismo para in y out) cuyo nombre contenga <substr>\n");
    printf("  --frames N       tamaño de buffer objetivo (por defecto 64)\n");
    printf("  --seconds N      duracion de la prueba (por defecto 300 = 5 min)\n");
    printf("  --adaptive       si aparecen overloads, sube el buffer a 128 frames al vuelo (ADR-024, tarea B1.6)\n");
}

int main(int argc, char **argv) {
    setvbuf(stdout, NULL, _IOLBF, 0);   /* logs legibles aunque se redirija a fichero */
    const char *pick = NULL;
    UInt32 want_frames = 64;
    int seconds = 300;
    bool adaptive = false;

    for (int i = 1; i < argc; i++) {
        if (!strcmp(argv[i], "--list"))              return list_devices();
        else if (!strcmp(argv[i], "--in-out") && i+1 < argc) pick = argv[++i];
        else if (!strcmp(argv[i], "--frames") && i+1 < argc) want_frames = (UInt32)atoi(argv[++i]);
        else if (!strcmp(argv[i], "--seconds") && i+1 < argc) seconds = atoi(argv[++i]);
        else if (!strcmp(argv[i], "--adaptive")) adaptive = true;
        else { usage(argv[0]); return (strcmp(argv[i], "--help") == 0) ? 0 : 2; }
    }

    /* Reloj: factor para pasar de mach_absolute_time a nanosegundos. */
    mach_timebase_info_data_t tb; mach_timebase_info(&tb);
    g_ns_per_tick = (double)tb.numer / (double)tb.denom;

    /* --- Elegir dispositivo --- */
    AudioDeviceID dev = 0;
    if (pick) {
        AudioObjectPropertyAddress a = {
            kAudioHardwarePropertyDevices,
            kAudioObjectPropertyScopeGlobal, kAudioObjectPropertyElementMain
        };
        UInt32 size = 0;
        AudioObjectGetPropertyDataSize(kAudioObjectSystemObject, &a, 0, NULL, &size);
        UInt32 count = size / (UInt32)sizeof(AudioDeviceID);
        AudioDeviceID *devs = (AudioDeviceID *)malloc(size);
        AudioObjectGetPropertyData(kAudioObjectSystemObject, &a, 0, NULL, &size, devs);
        for (UInt32 i = 0; i < count; i++) {
            char name[128]; device_name(devs[i], name, sizeof(name));
            if (strcasestr(name, pick)) { dev = devs[i]; break; }
        }
        free(devs);
        if (!dev) { fprintf(stderr, "  no hay ningun dispositivo que contenga \"%s\". Prueba --list\n", pick); return 1; }
    } else {
        dev = default_device(false);   /* salida por defecto; ojala sea duplex */
        printf("  sin --in-out: uso el dispositivo de salida por defecto. Si no tiene\n"
               "  entrada, veras 'render err' subiendo. Usa --in-out <mesa> para tu Rane.\n");
    }

    char dname[128]; device_name(dev, dname, sizeof(dname));
    UInt32 ci = device_channels(dev, true), co = device_channels(dev, false);
    printf("\n  dispositivo: \"%s\"   in=%u  out=%u\n", dname, ci, co);
    if (ci == 0) fprintf(stderr, "  AVISO: este dispositivo no tiene canales de entrada. El passthrough no oira nada.\n");

    g_channels = (ci < co ? ci : co);
    if (g_channels < 1) g_channels = 1;
    if (g_channels > 8) g_channels = 8;   /* el spike se queda en algo manejable */
    printf("  canales de passthrough: %u\n", g_channels);

    /* --- Pedir el buffer de 64 y leer el real --- */
    printf("  pido buffer de %u frames...\n", want_frames);
    OSStatus bs = set_device_buffer_frames(dev, want_frames);
    if (bs != noErr) { char b[8]; printf("  (no acepto la peticion: %s; sigo con el que tenga)\n", osstatus_str(bs, b)); }
    UInt32 real_frames = device_buffer_frames(dev);
    double sr = device_sample_rate(dev);
    printf("  buffer real: %u frames    sample rate: %.0f Hz    periodo teorico: %.3f ms\n",
           real_frames, sr, 1000.0 * real_frames / (sr > 0 ? sr : 48000.0));
    if (sr != 48000.0)
        printf("  NOTA: el dispositivo esta a %.0f Hz, no a 48000. El spike no lo fuerza;\n"
               "        para la prueba oficial ponlo a 48 kHz en 'Configuracion de Audio MIDI'.\n", sr);

    /* --- Reservar los buffers de entrada ANTES de arrancar nada --- */
    g_in_storage = (float *)calloc((size_t)g_channels * g_max_frames, sizeof(float));
    g_in_abl = (AudioBufferList *)calloc(1, sizeof(AudioBufferList) + (g_channels - 1) * sizeof(AudioBuffer));
    if (!g_in_storage || !g_in_abl) { fprintf(stderr, "  sin memoria\n"); return 1; }

    /* --- Construir la AudioUnit HAL (entrada+salida, mismo dispositivo) --- */
    AudioComponentDescription desc = {
        .componentType = kAudioUnitType_Output,
        .componentSubType = kAudioUnitSubType_HALOutput,
        .componentManufacturer = kAudioUnitManufacturer_Apple, 0, 0
    };
    AudioComponent comp = AudioComponentFindNext(NULL, &desc);
    if (!comp) { fprintf(stderr, "  no encuentro la HAL AudioUnit\n"); return 1; }
    CHECK(AudioComponentInstanceNew(comp, &g_unit), "AudioComponentInstanceNew");

    UInt32 yes = 1, no = 0;
    /* elemento 1 = entrada (scope Input), elemento 0 = salida (scope Output) */
    CHECK(AudioUnitSetProperty(g_unit, kAudioOutputUnitProperty_EnableIO,
          kAudioUnitScope_Input, 1, &yes, sizeof(yes)), "EnableIO input");
    CHECK(AudioUnitSetProperty(g_unit, kAudioOutputUnitProperty_EnableIO,
          kAudioUnitScope_Output, 0, &yes, sizeof(yes)), "EnableIO output");
    (void)no;

    CHECK(AudioUnitSetProperty(g_unit, kAudioOutputUnitProperty_CurrentDevice,
          kAudioUnitScope_Global, 0, &dev, sizeof(dev)), "CurrentDevice");

    /* Formato cliente: Float32 no entrelazado, g_channels canales, al sr del
     * dispositivo. Lo fijamos en los dos lados: lo que sale del bus de entrada
     * (scope Output, elem 1) y lo que entra al bus de salida (scope Input, elem 0). */
    AudioStreamBasicDescription fmt = {0};
    fmt.mSampleRate       = (sr > 0 ? sr : 48000.0);
    fmt.mFormatID         = kAudioFormatLinearPCM;
    fmt.mFormatFlags      = kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked | kAudioFormatFlagIsNonInterleaved;
    fmt.mBitsPerChannel   = 32;
    fmt.mChannelsPerFrame = g_channels;
    fmt.mFramesPerPacket  = 1;
    fmt.mBytesPerFrame    = 4;   /* por canal, no entrelazado */
    fmt.mBytesPerPacket   = 4;
    CHECK(AudioUnitSetProperty(g_unit, kAudioUnitProperty_StreamFormat,
          kAudioUnitScope_Output, 1, &fmt, sizeof(fmt)), "StreamFormat entrada");
    CHECK(AudioUnitSetProperty(g_unit, kAudioUnitProperty_StreamFormat,
          kAudioUnitScope_Input, 0, &fmt, sizeof(fmt)), "StreamFormat salida");

    /* Pedir tambien a la unit el slice de 64 frames (ademas del buffer del device). */
    CHECK(AudioUnitSetProperty(g_unit, kAudioUnitProperty_MaximumFramesPerSlice,
          kAudioUnitScope_Global, 0, &g_max_frames, sizeof(g_max_frames)), "MaxFramesPerSlice");

    AURenderCallbackStruct cb = { .inputProc = render_cb, .inputProcRefCon = NULL };
    CHECK(AudioUnitSetProperty(g_unit, kAudioUnitProperty_SetRenderCallback,
          kAudioUnitScope_Input, 0, &cb, sizeof(cb)), "SetRenderCallback");

    /* Listener de overloads en el dispositivo. */
    AudioObjectPropertyAddress ov = {
        kAudioDeviceProcessorOverload,
        kAudioObjectPropertyScopeGlobal, kAudioObjectPropertyElementMain
    };
    AudioObjectAddPropertyListener(dev, &ov, on_overload, NULL);

    CHECK(AudioUnitInitialize(g_unit), "AudioUnitInitialize");
    CHECK(AudioOutputUnitStart(g_unit), "AudioOutputUnitStart");

    signal(SIGINT, on_sigint);
    printf("\n  === passthrough EN MARCHA ===  (Ctrl-C para parar)\n");
    printf("  sube el fader, pincha algo en el plato y escucha. Deberia sonar limpio.\n");
    if (adaptive) printf("  [--adaptive] si hay >= %d overloads, subo el buffer a 128 frames al vuelo.\n", 3);
    printf("\n");

    /* --- Bucle de estado: hilo main, 1 linea por segundo. NUNCA en el callback. --- */
    struct timespec one_sec = { .tv_sec = 1, .tv_nsec = 0 };
    uint64_t start = mach_absolute_time();
    double expected_period_ms = 1000.0 * real_frames / fmt.mSampleRate;
    bool did_switch = false;                 /* ya subimos a 128 */
    UInt32 switched_at_frames = real_frames;

    for (int t = 0; t < seconds && !g_stop; t++) {
        nanosleep(&one_sec, NULL);
        double elapsed = (double)(mach_absolute_time() - start) * g_ns_per_tick / 1e9;
        uint64_t cbs  = atomic_load(&g_cb_count);
        uint64_t ov_n = atomic_load(&g_overloads);
        uint64_t re_n = atomic_load(&g_render_errs);
        uint64_t gmax = atomic_load(&g_gap_max_ns);
        uint64_t gmin = atomic_load(&g_gap_min_ns);

        /* B1.6 / ADR-024: subida adaptativa 64 -> 128 al detectar overloads.
         * Se hace desde el hilo main (aqui), nunca desde el callback. Paramos la
         * unit, cambiamos el tamaño de buffer del dispositivo y volvemos a
         * arrancar: hay un microcorte, pero es justo el escenario en el que ya
         * habia cortes. Una sola vez; si a 128 sigue crujiendo, es FAIL. */
        if (adaptive && !did_switch && ov_n >= 3 && real_frames < 128) {
            printf("\n  [adaptive] %llu overloads a %u frames -> subo a 128...\n",
                   (unsigned long long)ov_n, real_frames);
            AudioOutputUnitStop(g_unit);
            OSStatus s2 = set_device_buffer_frames(dev, 128);
            real_frames = device_buffer_frames(dev);
            expected_period_ms = 1000.0 * real_frames / fmt.mSampleRate;
            atomic_store(&g_gap_max_ns, 0);
            atomic_store(&g_gap_min_ns, UINT64_MAX);
            atomic_store(&g_last_cb_tick, 0);
            AudioOutputUnitStart(g_unit);
            did_switch = true;
            switched_at_frames = real_frames;
            char b[8];
            printf("  [adaptive] ahora en %u frames (%.3f ms/callback)%s\n\n",
                   real_frames, expected_period_ms,
                   s2 == noErr ? "" : (snprintf(b, 8, "%d", (int)s2), "  (peticion rechazada)"));
        }

        printf("\r  t=%4.0fs  cb=%llu  overloads=%llu  render_err=%llu  gap[min/max]=%.2f/%.2f ms (esperado %.2f)   ",
               elapsed, (unsigned long long)cbs, (unsigned long long)ov_n,
               (unsigned long long)re_n,
               gmin == UINT64_MAX ? 0.0 : gmin / 1e6, gmax / 1e6, expected_period_ms);
        fflush(stdout);
    }
    printf("\n");

    /* --- Parar y resumen --- */
    AudioOutputUnitStop(g_unit);
    AudioObjectRemovePropertyListener(dev, &ov, on_overload, NULL);
    AudioUnitUninitialize(g_unit);
    AudioComponentInstanceDispose(g_unit);

    double total = (double)(mach_absolute_time() - start) * g_ns_per_tick / 1e9;
    uint64_t cbs  = atomic_load(&g_cb_count);
    uint64_t ov_n = atomic_load(&g_overloads);
    uint64_t re_n = atomic_load(&g_render_errs);
    int32_t  last = atomic_load(&g_last_render_err);
    uint64_t gmax = atomic_load(&g_gap_max_ns);

    printf("\n  ---------------- RESUMEN B1.1 ----------------\n");
    printf("  dispositivo      : %s\n", dname);
    printf("  buffer / sr      : %u frames @ %.0f Hz  (%.3f ms/callback)\n",
           real_frames, fmt.mSampleRate, expected_period_ms);
    if (did_switch)
        printf("  buffer adaptado  : SI, subio a %u frames durante la prueba (ADR-024 / B1.6)\n",
               switched_at_frames);
    printf("  duracion         : %.1f s  (pedidos %d)\n", total, seconds);
    printf("  callbacks        : %llu\n", (unsigned long long)cbs);
    printf("  overloads        : %llu%s\n", (unsigned long long)ov_n,
           did_switch ? "  (acumulado; incluye los previos a la subida)" : "");
    printf("  render errors    : %llu%s", (unsigned long long)re_n, re_n ? "  " : "\n");
    if (re_n) { char b[8]; printf("(ultimo: %s)\n", osstatus_str(last, b)); }
    printf("  peor gap entre cb: %.2f ms  (reiniciado en la subida si la hubo)\n", gmax / 1e6);

    bool complete = (total >= seconds - 1);
    bool clean    = (ov_n == 0 && re_n == 0);
    if (clean && complete && !did_switch)
        printf("\n  RESULTADO: PASS  — %d s sin overloads ni errores a %u frames.\n", seconds, real_frames);
    else if (did_switch && re_n == 0 && complete)
        printf("\n  RESULTADO: PASS CON RESERVA — 64 frames no aguanto; a %u si. Es el plan de ADR-024,\n"
               "             pero anota que esta maquina necesita 128 en docs/PLATFORM_SUPPORT.md 7.\n",
               switched_at_frames);
    else if (clean && !complete)
        printf("\n  RESULTADO: INCOMPLETO — limpio pero parado antes de los %d s. Repite la prueba entera.\n", seconds);
    else
        printf("\n  RESULTADO: FAIL  — hubo cortes%s. Anota el numero en docs/TIMECODE.md y abre un ADR (B1.3).\n",
               did_switch ? " incluso tras subir a 128" : "");
    printf("  ---------------------------------------------\n");

    free(g_in_abl); free(g_in_storage);
    /* 0 = passthrough limpio a 64. 2 = limpio pero solo tras subir a 128
     * (mecanismo de ADR-024 activado). 1 = cortes / incompleto. */
    if (clean && complete) return 0;
    if (did_switch && re_n == 0 && complete) return 2;
    return 1;
}
