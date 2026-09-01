/* SPDX-License-Identifier: GPL-3.0-only */
#include "xf_player.h"

#include <math.h>
#include <stdlib.h>
#include <string.h>

#ifndef M_PI
#define M_PI 3.14159265358979323846
#endif

/* ------------------------------------------------------------------ *
 * Parametros de la tabla de resampling.
 *
 * TAPS   longitud del kernel sinc enventanado. 32 taps + Blackman-Harris da un
 *        rechazo de banda parada de ~90 dB, de sobra para que el aliasing quede
 *        muy por debajo de lo audible.
 * PHASES resolucion sub-muestra del cabezal. 512 -> el error de cuantizar la
 *        fase fraccionaria es despreciable frente al propio kernel.
 * RATIOS "cubos" de velocidad. Para |v| entre dos cubos se usa el cubo superior
 *        (se filtra de mas, nunca de menos -> nunca aliasing). Por debajo de 1.0
 *        (ir lento / parado / reverso lento) se usa el cubo 1.0: leer mas
 *        despacio que la fuente no puede generar aliasing.
 * ------------------------------------------------------------------ */
#define XF_PLAYER_TAPS   32
#define XF_PLAYER_HALF    (XF_PLAYER_TAPS / 2)   /* el tap central es HALF-1 */
#define XF_PLAYER_PHASES 512

static const double XF_PLAYER_RATIOS[] = { 1.0, 1.5, 2.0, 3.0, 4.0, 6.0, 8.0 };
#define XF_PLAYER_NRATIOS ((int)(sizeof(XF_PLAYER_RATIOS) / sizeof(XF_PLAYER_RATIOS[0])))

struct xf_player {
    const float *sample;      /* mono, propiedad del llamante */
    int64_t      frames;
    unsigned int sample_rate;

    double playhead;          /* frames fraccionarios */
    double velocity;          /* ya suavizada */
    double glide_coef;        /* [0,1] por frame; 1.0 = sin suavizado */
    int    loop;              /* 0 = satura en los extremos; 1 = da la vuelta */
    double speed_gate;        /* >0: amplitud ~ min(1, |v|/speed_gate). 0 = off */

    /* Tabla [ratio][fase][tap]. Cada kernel esta normalizado a ganancia DC 1. */
    float *table;             /* NRATIOS * PHASES * TAPS floats */
};

/* sinc normalizado: sin(pi x) / (pi x), con sinc(0) = 1. NO RT-SAFE (init). */
static double xf_sinc(double x) {
    if (fabs(x) < 1e-9) return 1.0;
    double px = M_PI * x;
    return sin(px) / px;
}

/* Ventana de Blackman-Harris de 4 terminos, indice n en [0, N-1]. */
static double xf_blackman_harris(int n, int N) {
    const double a0 = 0.35875, a1 = 0.48829, a2 = 0.14128, a3 = 0.01168;
    double w = 2.0 * M_PI * (double)n / (double)(N - 1);
    return a0 - a1 * cos(w) + a2 * cos(2.0 * w) - a3 * cos(3.0 * w);
}

/* Rellena la tabla de kernels. NO RT-SAFE. */
static void xf_player_build_table(xf_player *p) {
    for (int ri = 0; ri < XF_PLAYER_NRATIOS; ri++) {
        /* corte relativo a Nyquist de la fuente: al ir a ratio r hay que
         * limitar la fuente a 1/r de su banda para no plegar. */
        double cutoff = 1.0 / XF_PLAYER_RATIOS[ri];

        for (int ph = 0; ph < XF_PLAYER_PHASES; ph++) {
            double frac = (double)ph / (double)XF_PLAYER_PHASES;
            float *k = p->table + ((size_t)ri * XF_PLAYER_PHASES + (size_t)ph) * XF_PLAYER_TAPS;

            double sum = 0.0;
            for (int t = 0; t < XF_PLAYER_TAPS; t++) {
                /* el tap t corresponde al offset m respecto de floor(playhead) */
                int m = t - (XF_PLAYER_HALF - 1);
                double arg = (double)m - frac;
                double h = cutoff * xf_sinc(cutoff * arg) * xf_blackman_harris(t, XF_PLAYER_TAPS);
                k[t] = (float)h;
                sum += h;
            }
            /* normaliza a ganancia DC unidad para que la amplitud no dependa de
             * la fase */
            if (fabs(sum) > 1e-12) {
                float inv = (float)(1.0 / sum);
                for (int t = 0; t < XF_PLAYER_TAPS; t++) k[t] *= inv;
            }
        }
    }
}

xf_player *xf_player_create(const float *sample, int64_t frames, unsigned int sample_rate) {
    if (!sample || frames < 2 || sample_rate == 0) return NULL;

    xf_player *p = (xf_player *)calloc(1, sizeof(*p));
    if (!p) return NULL;

    size_t n = (size_t)XF_PLAYER_NRATIOS * XF_PLAYER_PHASES * XF_PLAYER_TAPS;
    p->table = (float *)malloc(n * sizeof(float));
    if (!p->table) { free(p); return NULL; }

    p->sample      = sample;
    p->frames      = frames;
    p->sample_rate = sample_rate;
    p->playhead    = 0.0;
    p->velocity    = 0.0;
    xf_player_set_glide_ms(p, 5.0);

    xf_player_build_table(p);
    return p;
}

void xf_player_destroy(xf_player *p) {
    if (!p) return;
    free(p->table);
    free(p);
}

void xf_player_set_glide_ms(xf_player *p, double ms) {
    if (!p) return;
    if (ms <= 0.0) {
        p->glide_coef = 1.0;   /* salta */
        return;
    }
    /* one-pole: coef tal que se alcanza ~63% del salto en `ms` */
    double tau_frames = ms * 0.001 * (double)p->sample_rate;
    p->glide_coef = 1.0 - exp(-1.0 / tau_frames);
}

double xf_player_playhead(const xf_player *p) { return p ? p->playhead : 0.0; }
double xf_player_velocity(const xf_player *p) { return p ? p->velocity : 0.0; }

void xf_player_set_loop(xf_player *p, bool loop) { if (p) p->loop = loop ? 1 : 0; }

void xf_player_set_speed_gate(xf_player *p, double gate_velocity) {
    if (p) p->speed_gate = gate_velocity > 0.0 ? gate_velocity : 0.0;
}

void xf_player_set_playhead(xf_player *p, double frame) {
    if (!p) return;
    if (frame < 0.0) frame = 0.0;
    double last = (double)(p->frames - 1);
    if (frame > last) frame = last;
    p->playhead = frame;
}

/* Elige el cubo de ratio: el mas pequeno que sea >= r (filtra de mas, nunca de
 * menos). RT-SAFE: bucle acotado a NRATIOS. */
static inline int xf_player_ratio_index(double r) {
    int k = 0;
    while (k < XF_PLAYER_NRATIOS - 1 && XF_PLAYER_RATIOS[k] < r) k++;
    return k;
}

/* RT-SAFE */
void xf_player_render(xf_player *p, float *out, int nframes, double target_velocity) {
    if (!p || !out || nframes <= 0) return;

    const float *src   = p->sample;
    const int64_t last = p->frames - 1;
    const double  coef = p->glide_coef;

    for (int n = 0; n < nframes; n++) {
        /* 1) suaviza la velocidad hacia el objetivo (evita clicks al cambiarla) */
        p->velocity += (target_velocity - p->velocity) * coef;
        double v = p->velocity;

        /* 2) elige el kernel segun |v| */
        double av = v < 0.0 ? -v : v;
        int ri = xf_player_ratio_index(av);

        /* 3) parte entera y fase fraccionaria del cabezal */
        double x = p->playhead;
        int64_t i = (int64_t)floor(x);
        double  f = x - (double)i;
        int ph = (int)(f * (double)XF_PLAYER_PHASES + 0.5);
        if (ph >= XF_PLAYER_PHASES) ph = XF_PLAYER_PHASES - 1;

        const float *k =
            p->table + ((size_t)ri * XF_PLAYER_PHASES + (size_t)ph) * XF_PLAYER_TAPS;

        /* 4) convolucion de TAPS puntos. Fuera del sample: 0 si el cabezal se
         *    satura, o envuelto por modulo si esta en bucle (base instrumental). */
        double acc = 0.0;
        for (int t = 0; t < XF_PLAYER_TAPS; t++) {
            int64_t si = i + (int64_t)(t - (XF_PLAYER_HALF - 1));
            double s;
            if (p->loop) {
                si %= p->frames;
                if (si < 0) si += p->frames;   /* modulo siempre en [0, frames) */
                s = (double)src[si];
            } else {
                s = (si >= 0 && si <= last) ? (double)src[si] : 0.0;
            }
            acc += s * (double)k[t];
        }

        /* puerta por velocidad: casi parado -> casi mudo (mata el zumbido de DC) */
        double amp = 1.0;
        if (p->speed_gate > 0.0) {
            double g = av / p->speed_gate;
            amp = g < 1.0 ? g : 1.0;
        }
        out[n] = (float)(acc * amp);

        /* 5) avanza el cabezal: se satura a los extremos (el plato no se sale
         *    del sample) o da la vuelta si esta en bucle. */
        p->playhead += v;
        if (p->loop) {
            double fr = (double)p->frames;
            p->playhead = fmod(p->playhead, fr);
            if (p->playhead < 0.0) p->playhead += fr;
        } else {
            if (p->playhead < 0.0) p->playhead = 0.0;
            if (p->playhead > (double)last) p->playhead = (double)last;
        }
    }
}
