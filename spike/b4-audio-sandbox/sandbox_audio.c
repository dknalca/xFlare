/* SPDX-License-Identifier: GPL-3.0-only */
#include "sandbox_audio.h"

#include <AudioToolbox/AudioToolbox.h>
#include <AudioUnit/AudioUnit.h>
#include <CoreAudio/CoreAudio.h>

#include <math.h>
#include <stdatomic.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#ifndef kAudioObjectPropertyElementMain
#define kAudioObjectPropertyElementMain kAudioObjectPropertyElementMaster
#endif

#define OUT_SR   48000.0
#define OUT_CH   2
#define MAX_SLICE 4096

/* --- buffers preasignados (se llenan en sandbox_load, NO en el callback) --- */
static float  *g_scr  = NULL;   /* sample de scratch, estereo intercalado */
static int64_t g_scr_frames = 0;
static float  *g_inst = NULL;   /* instrumental, estereo intercalado */
static int64_t g_inst_frames = 0;

/* --- parametros UI -> callback (atomicas) --- */
static _Atomic double g_target_vel = 0.0;
static _Atomic int    g_fader_open = 1;
static _Atomic int    g_reset      = 0;

/* --- HUD callback -> UI (atomicas, aproximadas) --- */
static _Atomic double g_hud_vel   = 0.0;
static _Atomic double g_hud_pos01 = 0.0;
static _Atomic double g_hud_peak  = 0.0;

/* --- estado que solo toca el hilo RT --- */
static double g_smoothed_vel = 0.0;
static double g_scr_ph  = 0.0;   /* indice de frame fraccionario en g_scr */
static double g_inst_ph = 0.0;
static double g_fader_gain = 1.0;

static AudioUnit g_unit = NULL;

/* ------------------------------------------------------------------ */
/* Decodificacion (NO RT-SAFE): ExtAudioFile a Float32 estereo 48 kHz. */
/* ------------------------------------------------------------------ */
static int decode_file(const char *path, float **out_buf, int64_t *out_frames) {
    CFStringRef cfPath = CFStringCreateWithCString(NULL, path, kCFStringEncodingUTF8);
    if (!cfPath) return -1;
    CFURLRef url = CFURLCreateWithFileSystemPath(NULL, cfPath, kCFURLPOSIXPathStyle, false);
    CFRelease(cfPath);
    if (!url) return -2;

    ExtAudioFileRef af = NULL;
    OSStatus st = ExtAudioFileOpenURL(url, &af);
    CFRelease(url);
    if (st != noErr || !af) { fprintf(stderr, "  no puedo abrir %s (%d)\n", path, (int)st); return -3; }

    AudioStreamBasicDescription client = {0};
    client.mSampleRate       = OUT_SR;
    client.mFormatID         = kAudioFormatLinearPCM;
    client.mFormatFlags      = kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked; /* intercalado */
    client.mBitsPerChannel   = 32;
    client.mChannelsPerFrame = OUT_CH;
    client.mFramesPerPacket  = 1;
    client.mBytesPerFrame    = sizeof(float) * OUT_CH;
    client.mBytesPerPacket   = sizeof(float) * OUT_CH;
    st = ExtAudioFileSetProperty(af, kExtAudioFileProperty_ClientDataFormat,
                                 sizeof(client), &client);
    if (st != noErr) { ExtAudioFileDispose(af); fprintf(stderr, "  ClientDataFormat %d\n", (int)st); return -4; }

    /* leer por bloques y acumular (una sola vez, no importa que no sea RT-safe) */
    const UInt32 CHUNK = 1 << 16;
    float *buf = NULL;
    int64_t cap = 0, n = 0;
    float *tmp = (float *)malloc((size_t)CHUNK * OUT_CH * sizeof(float));
    for (;;) {
        AudioBufferList abl;
        abl.mNumberBuffers = 1;
        abl.mBuffers[0].mNumberChannels = OUT_CH;
        abl.mBuffers[0].mDataByteSize   = CHUNK * OUT_CH * sizeof(float);
        abl.mBuffers[0].mData           = tmp;
        UInt32 got = CHUNK;
        st = ExtAudioFileRead(af, &got, &abl);
        if (st != noErr) { fprintf(stderr, "  Read %d\n", (int)st); free(tmp); free(buf); ExtAudioFileDispose(af); return -5; }
        if (got == 0) break;
        if (n + got > cap) {
            cap = (n + got) * 2;
            buf = (float *)realloc(buf, (size_t)cap * OUT_CH * sizeof(float));
        }
        memcpy(buf + n * OUT_CH, tmp, (size_t)got * OUT_CH * sizeof(float));
        n += got;
    }
    free(tmp);
    ExtAudioFileDispose(af);

    if (n < 2) { free(buf); return -6; }
    *out_buf = buf;
    *out_frames = n;
    return 0;
}

/* NO RT-SAFE */
int sandbox_load(const char *scratch_path, const char *instrumental_path) {
    int r = decode_file(scratch_path, &g_scr, &g_scr_frames);
    if (r != 0) return r;
    r = decode_file(instrumental_path, &g_inst, &g_inst_frames);
    if (r != 0) return r - 100;
    return 0;
}

/* ------------------------------------------------------------------ */
/* CALLBACK RT. C puro, sin malloc/locks/printf; atomicas para hablar con la UI. */
/* ------------------------------------------------------------------ */
static inline float lerp_ch(const float *b, int64_t frames, double ph, int ch) {
    int64_t i0 = (int64_t)ph;
    if (i0 < 0) i0 = 0;
    if (i0 > frames - 2) i0 = frames - 2;
    double f = ph - (double)i0;
    float a = b[i0 * OUT_CH + ch];
    float c = b[(i0 + 1) * OUT_CH + ch];
    return (float)(a + (c - a) * f);
}

static OSStatus render_cb(void *ref, AudioUnitRenderActionFlags *flags,
                          const AudioTimeStamp *ts, UInt32 bus, UInt32 frames,
                          AudioBufferList *out) {
    (void)ref; (void)flags; (void)ts; (void)bus;
    float *o = (float *)out->mBuffers[0].mData;   /* estereo intercalado */

    if (atomic_exchange_explicit(&g_reset, 0, memory_order_relaxed)) {
        g_scr_ph = 0.0;
    }
    const double target   = atomic_load_explicit(&g_target_vel, memory_order_relaxed);
    const int    faderOpen = atomic_load_explicit(&g_fader_open, memory_order_relaxed);

    /* coeficientes de suavizado por frame (a 48 kHz) */
    const double VEL_GLIDE  = 0.0020;   /* ~10 ms para alcanzar la velocidad objetivo */
    const double FADER_RAMP = 0.0100;   /* ~2 ms de rampa del corte, sin clicks */
    const double INST_LEVEL = 0.55;
    const double SCR_LEVEL  = 0.95;

    double peak = 0.0;

    for (UInt32 n = 0; n < frames; n++) {
        g_smoothed_vel += (target - g_smoothed_vel) * VEL_GLIDE;
        double fgTarget = faderOpen ? 1.0 : 0.0;
        g_fader_gain += (fgTarget - g_fader_gain) * FADER_RAMP;

        /* instrumental: velocidad fija 1.0, en bucle */
        double il = lerp_ch(g_inst, g_inst_frames, g_inst_ph, 0);
        double ir = lerp_ch(g_inst, g_inst_frames, g_inst_ph, 1);
        g_inst_ph += 1.0;
        if (g_inst_ph >= (double)(g_inst_frames - 2)) g_inst_ph = 0.0;

        /* scratch: velocidad del "plato" */
        double sl = lerp_ch(g_scr, g_scr_frames, g_scr_ph, 0);
        double sr = lerp_ch(g_scr, g_scr_frames, g_scr_ph, 1);
        g_scr_ph += g_smoothed_vel;
        if (g_scr_ph < 0.0) g_scr_ph = 0.0;
        if (g_scr_ph > (double)(g_scr_frames - 2)) g_scr_ph = (double)(g_scr_frames - 2);

        double L = il * INST_LEVEL + sl * SCR_LEVEL * g_fader_gain;
        double R = ir * INST_LEVEL + sr * SCR_LEVEL * g_fader_gain;
        /* saturacion suave por si el pico se pasa */
        L = tanh(L); R = tanh(R);
        o[n * 2 + 0] = (float)L;
        o[n * 2 + 1] = (float)R;

        double m = fabs(L) > fabs(R) ? fabs(L) : fabs(R);
        if (m > peak) peak = m;
    }

    atomic_store_explicit(&g_hud_vel,   g_smoothed_vel, memory_order_relaxed);
    atomic_store_explicit(&g_hud_pos01, g_scr_frames > 2 ? g_scr_ph / (double)g_scr_frames : 0.0,
                          memory_order_relaxed);
    /* pico con caida lenta para que el HUD no parpadee */
    double old = atomic_load_explicit(&g_hud_peak, memory_order_relaxed);
    atomic_store_explicit(&g_hud_peak, peak > old ? peak : old * 0.85, memory_order_relaxed);
    return noErr;
}

/* ------------------------------------------------------------------ */
/* NO RT-SAFE: arranque / parada.                                                */
/* ------------------------------------------------------------------ */
int sandbox_start(void) {
    AudioComponentDescription desc = {
        kAudioUnitType_Output, kAudioUnitSubType_DefaultOutput,
        kAudioUnitManufacturer_Apple, 0, 0
    };
    AudioComponent comp = AudioComponentFindNext(NULL, &desc);
    if (!comp) return -1;
    OSStatus st = AudioComponentInstanceNew(comp, &g_unit);
    if (st != noErr) return -2;

    AudioStreamBasicDescription fmt = {0};
    fmt.mSampleRate       = OUT_SR;
    fmt.mFormatID         = kAudioFormatLinearPCM;
    fmt.mFormatFlags      = kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked;
    fmt.mBitsPerChannel   = 32;
    fmt.mChannelsPerFrame = OUT_CH;
    fmt.mFramesPerPacket  = 1;
    fmt.mBytesPerFrame    = sizeof(float) * OUT_CH;
    fmt.mBytesPerPacket   = sizeof(float) * OUT_CH;
    st = AudioUnitSetProperty(g_unit, kAudioUnitProperty_StreamFormat,
                              kAudioUnitScope_Input, 0, &fmt, sizeof(fmt));
    if (st != noErr) return -3;

    UInt32 maxSlice = MAX_SLICE;
    AudioUnitSetProperty(g_unit, kAudioUnitProperty_MaximumFramesPerSlice,
                         kAudioUnitScope_Global, 0, &maxSlice, sizeof(maxSlice));

    AURenderCallbackStruct cb = { render_cb, NULL };
    st = AudioUnitSetProperty(g_unit, kAudioUnitProperty_SetRenderCallback,
                              kAudioUnitScope_Input, 0, &cb, sizeof(cb));
    if (st != noErr) return -4;

    st = AudioUnitInitialize(g_unit);
    if (st != noErr) return -5;
    st = AudioOutputUnitStart(g_unit);
    if (st != noErr) return -6;
    return 0;
}

void sandbox_stop(void) {
    if (!g_unit) return;
    AudioOutputUnitStop(g_unit);
    AudioUnitUninitialize(g_unit);
    AudioComponentInstanceDispose(g_unit);
    g_unit = NULL;
}

/* --- setters / getters --- */
void   sandbox_set_velocity(double v)   { atomic_store_explicit(&g_target_vel, v, memory_order_relaxed); }
void   sandbox_set_fader_open(bool op)  { atomic_store_explicit(&g_fader_open, op ? 1 : 0, memory_order_relaxed); }
void   sandbox_reset_scratch(void)      { atomic_store_explicit(&g_reset, 1, memory_order_relaxed); }
double sandbox_get_velocity(void)       { return atomic_load_explicit(&g_hud_vel, memory_order_relaxed); }
double sandbox_get_scratch_pos(void)    { return atomic_load_explicit(&g_hud_pos01, memory_order_relaxed); }
double sandbox_get_out_peak(void)       { return atomic_load_explicit(&g_hud_peak, memory_order_relaxed); }
bool   sandbox_get_fader_open(void)     { return atomic_load_explicit(&g_fader_open, memory_order_relaxed) != 0; }
double sandbox_get_scratch_seconds(void){ return g_scr_frames / OUT_SR; }
