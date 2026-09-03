/* SPDX-License-Identifier: GPL-3.0-only */
#include "xf_eq.h"

#include <math.h>

#ifndef M_PI
#define M_PI 3.14159265358979323846
#endif

/* Frecuencias y Q fijos (ver xf_eq.h). */
#define XF_EQ_LO_HZ   200.0
#define XF_EQ_MID_HZ  1000.0
#define XF_EQ_MID_Q   0.9
#define XF_EQ_HI_HZ   4000.0

enum { XF_EQ_LO = 0, XF_EQ_MID = 1, XF_EQ_HI = 2 };

/* ---- diseno de coeficientes (RBJ Audio-EQ cookbook). NO RT-SAFE ---- */

static xf_biquad xf_eq_identity(void) {
    xf_biquad c = { 1.0f, 0.0f, 0.0f, 0.0f, 0.0f };
    return c;
}

/* Normaliza (b*, a*) por a0 y empaqueta en xf_biquad (a0 -> 1). */
static xf_biquad xf_eq_pack(double b0, double b1, double b2,
                            double a0, double a1, double a2) {
    xf_biquad c;
    double inv = (fabs(a0) > 1e-12) ? 1.0 / a0 : 0.0;
    c.b0 = (float)(b0 * inv);
    c.b1 = (float)(b1 * inv);
    c.b2 = (float)(b2 * inv);
    c.a1 = (float)(a1 * inv);
    c.a2 = (float)(a2 * inv);
    return c;
}

/* Peaking EQ: realza / atenua una campana centrada en f0. */
static xf_biquad xf_eq_peaking(double sr, double f0, double q, double gain_db) {
    if (fabs(gain_db) < 1e-4) return xf_eq_identity();
    double A  = pow(10.0, gain_db / 40.0);
    double w0 = 2.0 * M_PI * f0 / sr;
    double cw = cos(w0), sw = sin(w0);
    double alpha = sw / (2.0 * q);

    double b0 = 1.0 + alpha * A;
    double b1 = -2.0 * cw;
    double b2 = 1.0 - alpha * A;
    double a0 = 1.0 + alpha / A;
    double a1 = -2.0 * cw;
    double a2 = 1.0 - alpha / A;
    return xf_eq_pack(b0, b1, b2, a0, a1, a2);
}

/* Low-shelf: sube / baja todo lo que hay por debajo de f0. */
static xf_biquad xf_eq_low_shelf(double sr, double f0, double gain_db) {
    if (fabs(gain_db) < 1e-4) return xf_eq_identity();
    double A  = pow(10.0, gain_db / 40.0);
    double w0 = 2.0 * M_PI * f0 / sr;
    double cw = cos(w0), sw = sin(w0);
    /* pendiente S = 1 -> alpha = sw/2 * sqrt(2) */
    double alpha = sw / 2.0 * 1.41421356237309515;
    double tsa   = 2.0 * sqrt(A) * alpha;

    double b0 =        A * ((A + 1.0) - (A - 1.0) * cw + tsa);
    double b1 =  2.0 * A * ((A - 1.0) - (A + 1.0) * cw);
    double b2 =        A * ((A + 1.0) - (A - 1.0) * cw - tsa);
    double a0 =            ((A + 1.0) + (A - 1.0) * cw + tsa);
    double a1 = -2.0 *     ((A - 1.0) + (A + 1.0) * cw);
    double a2 =            ((A + 1.0) + (A - 1.0) * cw - tsa);
    return xf_eq_pack(b0, b1, b2, a0, a1, a2);
}

/* High-shelf: sube / baja todo lo que hay por encima de f0. */
static xf_biquad xf_eq_high_shelf(double sr, double f0, double gain_db) {
    if (fabs(gain_db) < 1e-4) return xf_eq_identity();
    double A  = pow(10.0, gain_db / 40.0);
    double w0 = 2.0 * M_PI * f0 / sr;
    double cw = cos(w0), sw = sin(w0);
    double alpha = sw / 2.0 * 1.41421356237309515;
    double tsa   = 2.0 * sqrt(A) * alpha;

    double b0 =        A * ((A + 1.0) + (A - 1.0) * cw + tsa);
    double b1 = -2.0 * A * ((A - 1.0) + (A + 1.0) * cw);
    double b2 =        A * ((A + 1.0) + (A - 1.0) * cw - tsa);
    double a0 =            ((A + 1.0) - (A - 1.0) * cw + tsa);
    double a1 =  2.0 *     ((A - 1.0) - (A + 1.0) * cw);
    double a2 =            ((A + 1.0) - (A - 1.0) * cw - tsa);
    return xf_eq_pack(b0, b1, b2, a0, a1, a2);
}

static float xf_eq_clamp_db(float db) {
    if (db < XF_EQ_MIN_DB) return XF_EQ_MIN_DB;
    if (db > XF_EQ_MAX_DB) return XF_EQ_MAX_DB;
    return db;
}

/* ---- API ---- */

void xf_eq_init(xf_eq *eq, double sample_rate) {
    if (!eq) return;
    eq->sample_rate = sample_rate > 0.0 ? sample_rate : 48000.0;
    for (int g = 0; g < 2; g++)
        for (int b = 0; b < 3; b++)
            eq->target[g][b] = xf_eq_identity();
    for (int b = 0; b < 3; b++) {
        eq->cur[b] = xf_eq_identity();
        eq->z[b].z1 = 0.0f; eq->z[b].z2 = 0.0f;
    }
    eq->gain_db[0] = eq->gain_db[1] = eq->gain_db[2] = 0.0f;
    eq->running = 0;
    __atomic_store_n(&eq->active_gen, 0, __ATOMIC_RELAXED);
    __atomic_store_n(&eq->want_flat, 1, __ATOMIC_RELAXED);
}

void xf_eq_set_gains_db(xf_eq *eq, float low_db, float mid_db, float high_db) {
    if (!eq) return;
    low_db  = xf_eq_clamp_db(low_db);
    mid_db  = xf_eq_clamp_db(mid_db);
    high_db = xf_eq_clamp_db(high_db);
    eq->gain_db[0] = low_db;
    eq->gain_db[1] = mid_db;
    eq->gain_db[2] = high_db;

    /* plano si las tres estan a ~0 dB */
    int flat = (fabsf(low_db) < 0.1f && fabsf(mid_db) < 0.1f && fabsf(high_db) < 0.1f);

    /* escribe en la generacion INACTIVA y luego la activa (torn-free para el RT,
     * como el swap de `xf_player` en `xf_engine`) */
    int cur  = __atomic_load_n(&eq->active_gen, __ATOMIC_RELAXED);
    int next = cur ^ 1;
    eq->target[next][XF_EQ_LO]  = xf_eq_low_shelf(eq->sample_rate,  XF_EQ_LO_HZ,  low_db);
    eq->target[next][XF_EQ_MID] = xf_eq_peaking(eq->sample_rate, XF_EQ_MID_HZ, XF_EQ_MID_Q, mid_db);
    eq->target[next][XF_EQ_HI]  = xf_eq_high_shelf(eq->sample_rate, XF_EQ_HI_HZ, high_db);

    __atomic_store_n(&eq->active_gen, next, __ATOMIC_RELEASE);
    __atomic_store_n(&eq->want_flat, flat ? 1 : 0, __ATOMIC_RELEASE);
}

/* RT-SAFE: un biquad TDF-II sobre una muestra. */
static inline float xf_biquad_tick(const xf_biquad *c, xf_biquad_z *s, float x) {
    float y = c->b0 * x + s->z1;
    s->z1 = c->b1 * x - c->a1 * y + s->z2;
    s->z2 = c->b2 * x - c->a2 * y;
    return y;
}

/* RT-SAFE: acerca `c` a `t` un paso `k`; devuelve la mayor desviacion restante. */
static inline float xf_biquad_ramp(xf_biquad *c, const xf_biquad *t, float k) {
    float *cf = &c->b0;          /* 5 floats contiguos, sin relleno */
    const float *tf = &t->b0;
    float dev = 0.0f;
    for (int j = 0; j < 5; j++) {
        cf[j] += (tf[j] - cf[j]) * k;
        float d = tf[j] - cf[j];
        if (d < 0.0f) d = -d;
        if (d > dev) dev = d;
    }
    return dev;
}

void xf_eq_process_block(xf_eq *eq, float *x, int n) {
    if (!eq || !x || n <= 0) return;

    const int want_flat = __atomic_load_n(&eq->want_flat, __ATOMIC_ACQUIRE);
    /* objetivo plano y `cur` ya convergido: no hay nada que filtrar */
    if (want_flat && !eq->running) return;

    const int g = __atomic_load_n(&eq->active_gen, __ATOMIC_ACQUIRE);
    const xf_biquad *T = eq->target[g];

    /* rampa por bloque de los coeficientes en uso hacia el objetivo (~20 ms),
     * una sola vez por bloque: evita el transitorio de cambiar de golpe */
    const float k = 1.0f - expf(-(float)n / (0.02f * (float)eq->sample_rate));
    float dev = 0.0f;
    for (int b = 0; b < 3; b++) {
        float d = xf_biquad_ramp(&eq->cur[b], &T[b], k);
        if (d > dev) dev = d;
    }
    if (dev < 1e-5f) {
        for (int b = 0; b < 3; b++) eq->cur[b] = T[b];
        eq->running = want_flat ? 0 : 1;   /* convergido: si es plano, apaga */
    } else {
        eq->running = 1;
    }

    xf_biquad_z *zlo = &eq->z[XF_EQ_LO], *zmid = &eq->z[XF_EQ_MID], *zhi = &eq->z[XF_EQ_HI];
    const xf_biquad *lo = &eq->cur[XF_EQ_LO], *mid = &eq->cur[XF_EQ_MID], *hi = &eq->cur[XF_EQ_HI];
    for (int i = 0; i < n; i++) {
        float s = x[i];
        s = xf_biquad_tick(lo, zlo, s);
        s = xf_biquad_tick(mid, zmid, s);
        s = xf_biquad_tick(hi, zhi, s);
        x[i] = s;
    }
}
