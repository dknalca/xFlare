/* SPDX-License-Identifier: GPL-3.0-only */
#include "xf_metronome.h"

#include <limits.h>
#include <math.h>
#include <stdlib.h>

#ifndef M_PI
#define M_PI 3.14159265358979323846
#endif

/* Forma del click (ms). Ataque corto para que sea percusivo; caida exponencial
 * que a los ~60 ms ya esta > 40 dB por debajo (sin cola audible al truncar). */
#define XF_MET_CLICK_MS   60.0
#define XF_MET_ATTACK_MS   1.5
#define XF_MET_DECAY_MS   11.0
#define XF_MET_BEAT_HZ   1000.0
#define XF_MET_ACCENT_HZ 1600.0

struct xf_metronome {
    unsigned int sample_rate;
    int   enabled;               /* 0/1, atomico (builtins __atomic_*) */
    float level;
    int   beats_per_bar;
    int   ppq;                   /* ticks por negra */

    long long last_beat;         /* ultimo tiempo ya disparado; LLONG_MIN = ninguno */

    /* voz del click en curso */
    bool   voice_active;
    int    voice_age;            /* frames desde el disparo */
    double voice_phase;
    double voice_freq;

    /* derivados de sample_rate */
    double attack_frames;
    double decay_frames;
    int    len_frames;
};

static void xf_met_recalc(xf_metronome *m) {
    double sr = (double)m->sample_rate;
    m->attack_frames = XF_MET_ATTACK_MS * 0.001 * sr;
    m->decay_frames  = XF_MET_DECAY_MS  * 0.001 * sr;
    m->len_frames    = (int)(XF_MET_CLICK_MS * 0.001 * sr);
    if (m->len_frames < 1) m->len_frames = 1;
}

xf_metronome *xf_metronome_create(unsigned int sample_rate) {
    if (sample_rate == 0) return NULL;
    xf_metronome *m = (xf_metronome *)calloc(1, sizeof(*m));
    if (!m) return NULL;

    m->sample_rate   = sample_rate;
    m->enabled       = 1;
    m->level         = 0.35f;
    m->beats_per_bar = 4;
    m->ppq           = 480;
    m->last_beat     = LLONG_MIN;
    m->voice_active  = false;
    m->voice_phase   = 0.0;
    xf_met_recalc(m);
    return m;
}

void xf_metronome_destroy(xf_metronome *m) { free(m); }

void xf_metronome_set_enabled(xf_metronome *m, bool on) {
    if (!m) return;
    __atomic_store_n(&m->enabled, on ? 1 : 0, __ATOMIC_RELAXED);
}

bool xf_metronome_enabled(const xf_metronome *m) {
    if (!m) return false;
    return __atomic_load_n(&m->enabled, __ATOMIC_RELAXED) != 0;
}

void xf_metronome_set_level(xf_metronome *m, float level) {
    if (!m) return;
    if (level < 0.0f) level = 0.0f;
    if (level > 1.0f) level = 1.0f;
    m->level = level;
}

void xf_metronome_set_time_signature(xf_metronome *m, int beats_per_bar, int ppq) {
    if (!m) return;
    if (beats_per_bar >= 1) m->beats_per_bar = beats_per_bar;
    if (ppq >= 1)           m->ppq = ppq;
}

void xf_metronome_resync(xf_metronome *m, double tick) {
    if (!m) return;
    /* marca el tiempo actual como "ya disparado": el siguiente cruce si suena */
    m->last_beat = (long long)floor(tick / (double)m->ppq);
}

/* Envolvente del click en `age` frames (0..len). Ataque lineal, caida exp. */
static inline float xf_met_env(const xf_metronome *m, int age) {
    if (age < 0 || age >= m->len_frames) return 0.0f;
    if ((double)age < m->attack_frames) {
        return (float)((double)age / m->attack_frames);
    }
    return (float)exp(-((double)age - m->attack_frames) / m->decay_frames);
}

/* RT-SAFE */
void xf_metronome_render(xf_metronome *m, float *out, int nframes,
                         double tick_at_start, double bpm) {
    if (!m || !out || nframes <= 0 || bpm <= 0.0) return;

    const int  on          = __atomic_load_n(&m->enabled, __ATOMIC_RELAXED);
    const double ppq       = (double)m->ppq;
    const double tpf       = bpm / 60.0 * ppq / (double)m->sample_rate;  /* ticks/frame */
    const double w_beat    = 2.0 * M_PI * XF_MET_BEAT_HZ   / (double)m->sample_rate;
    const double w_accent  = 2.0 * M_PI * XF_MET_ACCENT_HZ / (double)m->sample_rate;

    double tick = tick_at_start;

    for (int n = 0; n < nframes; n++) {
        long long beat = (long long)floor(tick / ppq);
        if (beat != m->last_beat) {
            m->last_beat    = beat;
            long long b     = ((beat % m->beats_per_bar) + m->beats_per_bar) % m->beats_per_bar;
            m->voice_active = true;
            m->voice_age    = 0;
            m->voice_phase  = 0.0;
            m->voice_freq   = (b == 0) ? w_accent : w_beat;
        }

        if (m->voice_active) {
            float e = xf_met_env(m, m->voice_age);
            if (on) {
                out[n] += m->level * e * (float)sin(m->voice_phase);
            }
            m->voice_phase += m->voice_freq;
            if (m->voice_phase > 2.0 * M_PI) m->voice_phase -= 2.0 * M_PI;
            m->voice_age++;
            if (m->voice_age >= m->len_frames) m->voice_active = false;
        }

        tick += tpf;
    }
}
