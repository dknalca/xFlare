/* SPDX-License-Identifier: GPL-3.0-only */
/*
 * xFlare · spike B5.5 — sonda de timecode con vinilo real.
 *
 * QUE ES: un prototipo DESECHABLE. Abre la ENTRADA de audio de la mesa (el deck
 * al que llega el vinilo de control), se la pasa al wrapper `xf_timecoder`
 * (Sources/CXFTimecode, ya escrito y probado con senal sintetica en B5.2-B5.4)
 * y te ensena en vivo lo que decodifica: velocidad con signo, posicion
 * relativa, confianza y direccion.
 *
 * PARA QUE: cerrar B5.5 (sellar CXFTimecode). El procedimiento completo esta en
 * docs/HW_BRINGUP.md paso 6. En resumen, con el plato girando a 33 1/3:
 *
 *     - `vel` debe rondar 1.00  (a 45 rpm -> ~1.35)
 *     - al scratchear, `vel` cambia de signo con el sentido
 *     - `--reverse` (hamster) invierte el signo
 *     - al levantar la aguja, `conf` cae y `vel` decae a 0 SIN colgarse;
 *       al bajarla, re-engancha
 *
 * QUE NO ES: la captura de verdad. Esa es `TimecodeMotionSource` en XFCapture
 * (B6.3), que ya existe; este spike solo evita tener que escribir un banco de
 * pruebas el dia que llegue el vinilo.
 *
 * USO:  ./build.sh  &&  ./tcprobe --list
 *       ./tcprobe --in-out "Seventy-Two" --seconds 60
 *       ./tcprobe --in-out "Seventy-Two" --def serato_2a --reverse
 *
 * Reglas del hilo de audio (CLAUDE.md seccion 7): el callback no reserva
 * memoria, no bloquea, no imprime; habla con `main` solo por un ring SPSC
 * lock-free y atomicas. `xf_timecoder_submit` se llama desde `main`, no en RT.
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
#include <math.h>
#include <time.h>

#include "xf_timecode.h"   /* el wrapper que estamos validando */

#ifndef kAudioObjectPropertyElementMain
#define kAudioObjectPropertyElementMain kAudioObjectPropertyElementMaster
#endif

/* ------------------------------------------------------------------ */
/* Ring SPSC lock-free de int16 INTERLEAVED (L,R,L,R...). El callback              */
/* (productor) escribe, `main` (consumidor) lee. Capacidad potencia de 2.         */
/* ------------------------------------------------------------------ */
#define RING_CAP (1u << 16)          /* 65536 int16 = 16384 frames estereo ~= 340 ms @48k */
static int16_t         g_ring[RING_CAP];
static _Atomic uint32_t g_ring_head = 0;   /* escribe el productor */
static _Atomic uint32_t g_ring_tail = 0;   /* escribe el consumidor */
static _Atomic uint64_t g_ring_drops = 0;  /* muestras perdidas por ring lleno */

/* productor: intenta meter `n` int16; si no caben, cuenta el drop. RT-SAFE. */
static void ring_push(const int16_t *src, uint32_t n) {
    uint32_t head = atomic_load_explicit(&g_ring_head, memory_order_relaxed);
    uint32_t tail = atomic_load_explicit(&g_ring_tail, memory_order_acquire);
    uint32_t used = head - tail;
    uint32_t free_slots = RING_CAP - used;
    if (n > free_slots) {
        atomic_fetch_add_explicit(&g_ring_drops, n - free_slots, memory_order_relaxed);
        n = free_slots;
    }
    for (uint32_t i = 0; i < n; i++) g_ring[(head + i) & (RING_CAP - 1)] = src[i];
    atomic_store_explicit(&g_ring_head, head + n, memory_order_release);
}

/* consumidor: saca hasta `max` int16 a `dst`; devuelve cuantos. NO RT (main). */
static uint32_t ring_pop(int16_t *dst, uint32_t max) {
    uint32_t tail = atomic_load_explicit(&g_ring_tail, memory_order_relaxed);
    uint32_t head = atomic_load_explicit(&g_ring_head, memory_order_acquire);
    uint32_t used = head - tail;
    if (used > max) used = max;
    for (uint32_t i = 0; i < used; i++) dst[i] = g_ring[(tail + i) & (RING_CAP - 1)];
    atomic_store_explicit(&g_ring_tail, tail + used, memory_order_release);
    return used;
}

/* ------------------------------------------------------------------ */
static volatile sig_atomic_t g_stop = 0;
static void on_sigint(int sig) { (void)sig; g_stop = 1; }

static AudioUnit       g_unit        = NULL;
static AudioBufferList *g_in_abl     = NULL;
static float          *g_in_storage  = NULL;
static UInt32          g_max_frames  = 4096;
static _Atomic uint64_t g_cb_count   = 0;
static _Atomic uint64_t g_render_errs = 0;

/* ------------------------------------------------------------------ */
/* Helpers CoreAudio (hilo normal). Copiados del spike b1-latency.               */
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

static AudioDeviceID default_input_device(void) {
    AudioObjectPropertyAddress a = { kAudioHardwarePropertyDefaultInputDevice,
        kAudioObjectPropertyScopeGlobal, kAudioObjectPropertyElementMain };
    AudioDeviceID dev = 0; UInt32 size = sizeof(dev);
    AudioObjectGetPropertyData(kAudioObjectSystemObject, &a, 0, NULL, &size, &dev);
    return dev;
}
static UInt32 device_channels(AudioDeviceID dev, bool input) {
    AudioObjectPropertyAddress a = { kAudioDevicePropertyStreamConfiguration,
        input ? kAudioObjectPropertyScopeInput : kAudioObjectPropertyScopeOutput,
        kAudioObjectPropertyElementMain };
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
    AudioObjectPropertyAddress a = { kAudioObjectPropertyName,
        kAudioObjectPropertyScopeGlobal, kAudioObjectPropertyElementMain };
    CFStringRef name = NULL; UInt32 size = sizeof(name); out[0] = 0;
    if (AudioObjectGetPropertyData(dev, &a, 0, NULL, &size, &name) == noErr && name) {
        CFStringGetCString(name, out, (CFIndex)out_len, kCFStringEncodingUTF8);
        CFRelease(name);
    }
}
static double device_sample_rate(AudioDeviceID dev) {
    AudioObjectPropertyAddress a = { kAudioDevicePropertyNominalSampleRate,
        kAudioObjectPropertyScopeGlobal, kAudioObjectPropertyElementMain };
    Float64 sr = 0; UInt32 size = sizeof(sr);
    AudioObjectGetPropertyData(dev, &a, 0, NULL, &size, &sr);
    return (double)sr;
}

static int list_devices(void) {
    AudioObjectPropertyAddress a = { kAudioHardwarePropertyDevices,
        kAudioObjectPropertyScopeGlobal, kAudioObjectPropertyElementMain };
    UInt32 size = 0;
    if (AudioObjectGetPropertyDataSize(kAudioObjectSystemObject, &a, 0, NULL, &size) != noErr) {
        fprintf(stderr, "  no se pudo enumerar dispositivos\n"); return 1;
    }
    UInt32 count = size / (UInt32)sizeof(AudioDeviceID);
    AudioDeviceID *devs = (AudioDeviceID *)malloc(size);
    AudioObjectGetPropertyData(kAudioObjectSystemObject, &a, 0, NULL, &size, devs);
    AudioDeviceID din = default_input_device();
    printf("  dispositivos de audio (%u):\n", count);
    printf("  %-40s  in  out   sr(Hz)\n", "nombre");
    printf("  ---------------------------------------- ---- ----  -------\n");
    for (UInt32 i = 0; i < count; i++) {
        char name[128]; device_name(devs[i], name, sizeof(name));
        printf("  %-40.40s %3u  %3u  %7.0f%s\n",
               name, device_channels(devs[i], true), device_channels(devs[i], false),
               device_sample_rate(devs[i]), devs[i] == din ? "  <-in por defecto" : "");
    }
    free(devs);
    printf("\n  elige con --in-out el dispositivo cuya ENTRADA lleva el vinilo de timecode.\n");
    return 0;
}

/* ------------------------------------------------------------------ */
/* EL CALLBACK. Tira de la entrada, convierte a int16 interleaved y lo mete en    */
/* el ring. Nada mas. CLAUDE.md seccion 7.                                        */
/* ------------------------------------------------------------------ */
static OSStatus input_cb(void *ref, AudioUnitRenderActionFlags *flags,
                         const AudioTimeStamp *ts, UInt32 bus, UInt32 frames,
                         AudioBufferList *ioData) {
    (void)ref; (void)bus; (void)ioData;
    if (frames > g_max_frames) frames = g_max_frames;

    for (UInt32 c = 0; c < 2; c++) {
        g_in_abl->mBuffers[c].mNumberChannels = 1;
        g_in_abl->mBuffers[c].mDataByteSize   = frames * (UInt32)sizeof(float);
        g_in_abl->mBuffers[c].mData           = g_in_storage + (size_t)c * g_max_frames;
    }
    g_in_abl->mNumberBuffers = 2;

    OSStatus err = AudioUnitRender(g_unit, flags, ts, 1 /* bus de entrada */, frames, g_in_abl);
    if (err != noErr) {
        atomic_fetch_add_explicit(&g_render_errs, 1, memory_order_relaxed);
        atomic_fetch_add_explicit(&g_cb_count, 1, memory_order_relaxed);
        return noErr;
    }

    /* float [-1,1] no entrelazado -> int16 interleaved, en trozos de 512 frames
     * para no pisar la pila. */
    const float *L = (const float *)g_in_abl->mBuffers[0].mData;
    const float *R = (const float *)g_in_abl->mBuffers[1].mData;
    int16_t tmp[1024];
    UInt32 done = 0;
    while (done < frames) {
        UInt32 n = frames - done; if (n > 512) n = 512;
        for (UInt32 i = 0; i < n; i++) {
            float l = L[done + i], r = R[done + i];
            if (l >  1.0f) l =  1.0f; if (l < -1.0f) l = -1.0f;
            if (r >  1.0f) r =  1.0f; if (r < -1.0f) r = -1.0f;
            tmp[i * 2 + 0] = (int16_t)lrintf(l * 32767.0f);
            tmp[i * 2 + 1] = (int16_t)lrintf(r * 32767.0f);
        }
        ring_push(tmp, n * 2);
        done += n;
    }
    atomic_fetch_add_explicit(&g_cb_count, 1, memory_order_relaxed);
    return noErr;
}

/* ------------------------------------------------------------------ */
static void usage(const char *p) {
    printf("uso: %s [--list] [--in-out <substr>] [--seconds N] [--def NOMBRE] [--reverse] [--hz N]\n", p);
    printf("  --list            enumera dispositivos y sale\n");
    printf("  --in-out <substr> dispositivo cuya ENTRADA lleva el timecode\n");
    printf("  --seconds N       duracion (por defecto 60)\n");
    printf("  --def NOMBRE      definicion de timecode: serato_2a (def.), serato_cd, traktor_a, mixvibes_v2...\n");
    printf("  --reverse         hamster: invierte el sentido\n");
    printf("  --hz N            lineas por segundo en pantalla (por defecto 10)\n");
}

int main(int argc, char **argv) {
    setvbuf(stdout, NULL, _IOLBF, 0);
    const char *pick = NULL, *defname = "serato_2a";
    int seconds = 60, hz = 10;
    bool reverse = false;

    for (int i = 1; i < argc; i++) {
        if (!strcmp(argv[i], "--list")) return list_devices();
        else if (!strcmp(argv[i], "--in-out") && i + 1 < argc) pick = argv[++i];
        else if (!strcmp(argv[i], "--seconds") && i + 1 < argc) seconds = atoi(argv[++i]);
        else if (!strcmp(argv[i], "--def") && i + 1 < argc) defname = argv[++i];
        else if (!strcmp(argv[i], "--reverse")) reverse = true;
        else if (!strcmp(argv[i], "--hz") && i + 1 < argc) hz = atoi(argv[++i]);
        else { usage(argv[0]); return strcmp(argv[i], "--help") == 0 ? 0 : 2; }
    }
    if (hz < 1) hz = 1; if (hz > 100) hz = 100;

    /* --- dispositivo --- */
    AudioDeviceID dev = 0;
    if (pick) {
        AudioObjectPropertyAddress a = { kAudioHardwarePropertyDevices,
            kAudioObjectPropertyScopeGlobal, kAudioObjectPropertyElementMain };
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
        if (!dev) { fprintf(stderr, "  no hay dispositivo con \"%s\". Prueba --list\n", pick); return 1; }
    } else {
        dev = default_input_device();
        printf("  sin --in-out: uso la entrada por defecto del sistema.\n");
    }

    char dname[128]; device_name(dev, dname, sizeof(dname));
    UInt32 ci = device_channels(dev, true);
    double sr = device_sample_rate(dev);
    printf("\n  dispositivo: \"%s\"   canales de entrada=%u   sr=%.0f Hz\n", dname, ci, sr);
    if (ci < 2) { fprintf(stderr, "  necesita >= 2 canales de entrada (timecode es estereo en cuadratura).\n"); return 1; }
    if (sr <= 0) sr = 48000.0;

    /* --- wrapper de timecode --- */
    xf_timecoder *tc = xf_timecoder_create(defname, (unsigned int)(sr + 0.5));
    if (!tc) { fprintf(stderr, "  xf_timecoder_create fallo (definicion \"%s\" desconocida?)\n", defname); return 1; }
    xf_timecoder_set_reversed(tc, reverse);
    xf_timecoder_reset_position(tc);
    printf("  timecode: def=\"%s\"  reverse=%s\n", defname, reverse ? "SI (hamster)" : "no");

    /* --- buffers de entrada --- */
    g_in_storage = (float *)calloc((size_t)2 * g_max_frames, sizeof(float));
    g_in_abl = (AudioBufferList *)calloc(1, sizeof(AudioBufferList) + 1 * sizeof(AudioBuffer));
    if (!g_in_storage || !g_in_abl) { fprintf(stderr, "  sin memoria\n"); return 1; }

    /* --- AudioUnit HAL, SOLO entrada --- */
    AudioComponentDescription desc = { .componentType = kAudioUnitType_Output,
        .componentSubType = kAudioUnitSubType_HALOutput,
        .componentManufacturer = kAudioUnitManufacturer_Apple, 0, 0 };
    AudioComponent comp = AudioComponentFindNext(NULL, &desc);
    if (!comp) { fprintf(stderr, "  no encuentro la HAL AudioUnit\n"); return 1; }
    CHECK(AudioComponentInstanceNew(comp, &g_unit), "AudioComponentInstanceNew");

    UInt32 yes = 1, no = 0;
    CHECK(AudioUnitSetProperty(g_unit, kAudioOutputUnitProperty_EnableIO,
          kAudioUnitScope_Input, 1, &yes, sizeof(yes)), "EnableIO input");
    CHECK(AudioUnitSetProperty(g_unit, kAudioOutputUnitProperty_EnableIO,
          kAudioUnitScope_Output, 0, &no, sizeof(no)), "DisableIO output");
    CHECK(AudioUnitSetProperty(g_unit, kAudioOutputUnitProperty_CurrentDevice,
          kAudioUnitScope_Global, 0, &dev, sizeof(dev)), "CurrentDevice");

    AudioStreamBasicDescription fmt = {0};
    fmt.mSampleRate       = sr;
    fmt.mFormatID         = kAudioFormatLinearPCM;
    fmt.mFormatFlags      = kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked | kAudioFormatFlagIsNonInterleaved;
    fmt.mBitsPerChannel   = 32;
    fmt.mChannelsPerFrame = 2;
    fmt.mFramesPerPacket  = 1;
    fmt.mBytesPerFrame    = 4;
    fmt.mBytesPerPacket   = 4;
    CHECK(AudioUnitSetProperty(g_unit, kAudioUnitProperty_StreamFormat,
          kAudioUnitScope_Output, 1, &fmt, sizeof(fmt)), "StreamFormat entrada");

    CHECK(AudioUnitSetProperty(g_unit, kAudioUnitProperty_MaximumFramesPerSlice,
          kAudioUnitScope_Global, 0, &g_max_frames, sizeof(g_max_frames)), "MaxFramesPerSlice");

    AURenderCallbackStruct cb = { .inputProc = input_cb, .inputProcRefCon = NULL };
    CHECK(AudioUnitSetProperty(g_unit, kAudioOutputUnitProperty_SetInputCallback,
          kAudioUnitScope_Global, 0, &cb, sizeof(cb)), "SetInputCallback");

    CHECK(AudioUnitInitialize(g_unit), "AudioUnitInitialize");
    CHECK(AudioOutputUnitStart(g_unit), "AudioOutputUnitStart");

    signal(SIGINT, on_sigint);
    printf("\n  === sonda de timecode EN MARCHA ===  (Ctrl-C para parar)\n");
    printf("  pon el plato a 33 1/3: vel deberia rondar 1.00. Scratchea, levanta la aguja...\n\n");

    /* --- bucle de main: drena el ring, alimenta el wrapper, imprime --- */
    static int16_t buf[RING_CAP];
    struct timespec slice = { .tv_sec = 0, .tv_nsec = (long)(1000000000L / hz) };
    mach_timebase_info_data_t tbi; mach_timebase_info(&tbi);
    double ns_per_tick = (double)tbi.numer / (double)tbi.denom;
    uint64_t start = mach_absolute_time();

    double vmin = 1e9, vmax = -1e9, vsum = 0; long vcount = 0;
    bool ever_locked = false;
    float conf_min = 1.0f, conf_max = 0.0f;

    while (!g_stop) {
        double elapsed = (double)(mach_absolute_time() - start) * ns_per_tick / 1e9;
        if (elapsed >= seconds) break;
        nanosleep(&slice, NULL);

        uint32_t got = ring_pop(buf, RING_CAP);
        if (got >= 2) xf_timecoder_submit(tc, buf, got / 2);

        double vel = xf_timecoder_velocity(tc);
        double pos = xf_timecoder_position(tc);
        float  conf = xf_timecoder_confidence(tc);
        bool   fwd = xf_timecoder_forwards(tc);

        if (got >= 2) {
            if (vel < vmin) vmin = vel;
            if (vel > vmax) vmax = vel;
            vsum += vel; vcount++;
            if (conf >= 0.999f) ever_locked = true;
            if (conf < conf_min) conf_min = conf;
            if (conf > conf_max) conf_max = conf;
        }

        printf("\r  t=%5.1fs  vel=%+7.4f  ~%5.1f rpm  pos=%+9.4f  conf=%.2f  dir=%s  drops=%llu   ",
               elapsed, vel, vel * 33.333, pos, conf, fwd ? "fwd" : "REV",
               (unsigned long long)atomic_load(&g_ring_drops));
        fflush(stdout);
    }
    printf("\n");

    AudioOutputUnitStop(g_unit);
    AudioUnitUninitialize(g_unit);
    AudioComponentInstanceDispose(g_unit);

    uint64_t re = atomic_load(&g_render_errs);
    uint64_t dr = atomic_load(&g_ring_drops);
    printf("\n  ---------------- RESUMEN B5.5 ----------------\n");
    printf("  dispositivo   : %s  @ %.0f Hz\n", dname, sr);
    printf("  definicion    : %s%s\n", defname, reverse ? "  (reverse)" : "");
    printf("  callbacks     : %llu   render_err: %llu   ring drops: %llu\n",
           (unsigned long long)atomic_load(&g_cb_count), (unsigned long long)re, (unsigned long long)dr);
    if (vcount) {
        printf("  velocidad     : min %+.4f   media %+.4f   max %+.4f\n",
               vmin, vsum / (double)vcount, vmax);
        printf("  confianza     : min %.2f   max %.2f   engancho bitstream: %s\n",
               conf_min, conf_max, ever_locked ? "SI" : "no (solo por RMS)");
        printf("\n  Que comprobar (docs/HW_BRINGUP.md paso 6):\n");
        printf("   - plato a 33 1/3 estable -> media ~ 1.00 (a 45 -> ~1.35)\n");
        printf("   - al invertir el sentido, vel cambia de signo y dir pasa a REV\n");
        printf("   - al levantar la aguja, conf -> ~0 y vel -> 0 sin colgarse\n");
        printf("   - drops debe ser 0; si sube, el bucle de main va lento (mira --hz)\n");
    } else {
        printf("  no llego ni una muestra. Revisa el enrutado del deck a la entrada y el permiso de microfono.\n");
    }
    printf("  ---------------------------------------------\n");

    xf_timecoder_destroy(tc);
    free(g_in_abl); free(g_in_storage);
    return (vcount && re == 0) ? 0 : 1;
}
