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
    /* Con loop activo, el cabezal envuelve dentro de [loop_start, loop_end) en
     * vez de [0, frames). Por defecto 0..frames (= sample entero). Lo escribe el
     * hilo normal (`xf_player_set_loop_region`); una lectura rasgada del par en
     * el RT se auto-corrige en el siguiente bloque (el wrap re-encaja). */
    int64_t loop_start;
    int64_t loop_end;
    double speed_gate;        /* >0: amplitud ~ min(1, |v|/speed_gate). 0 = off */

    /* ancla de posicion (ADR-042): NO es el driver del cabezal (lo es la
     * velocidad), es un TRIM anti-deriva. Cada muestra suma a la velocidad
     * `(target_playhead - playhead) * seek_coef`, ACOTADO a +-`seek_max_trim`
     * frames/muestra para que la correccion no se oiga nunca como un barrido de
     * pitch. `seek_active` 0 = suelto. */
    int    seek_active;
    double target_playhead;
    double seek_coef;         /* [0,1] por frame, ~250 ms */
    double seek_max_trim;     /* tope de |trim|, frames/muestra (~1.5% de pitch) */

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
    p->loop_start  = 0;
    p->loop_end    = frames;
    p->playhead    = 0.0;
    p->velocity    = 0.0;
    p->seek_active = 0;
    /* trim del ancla: one-pole lento (~250 ms) y tope de 0.015 frames/muestra
     * (~1.5% de pitch). Lo justo para corregir deriva sin que se oiga. */
    p->seek_coef     = 1.0 - exp(-1.0 / (0.25 * (double)sample_rate));
    p->seek_max_trim = 0.015;
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

/* NO RT-SAFE recomendado: acota el bucle a [start, end) frames. `start<0`,
 * `end>frames`, o menos de 2 frames de region -> se usa el sample entero. Solo
 * tiene efecto con loop activo. El cabezal NO se toca aqui: si queda fuera de la
 * region nueva, el wrap del render lo mete dentro en el siguiente bloque. */
void xf_player_set_loop_region(xf_player *p, int64_t start, int64_t end) {
    if (!p) return;
    if (start < 0 || end > p->frames || end - start < 2) {
        start = 0;
        end   = p->frames;
    }
    /* El RT lee estos dos int64 sin candado; una combinacion rasgada la sanea
     * `xf_player_render` (acota `[rlo, rhi)` a `[0, frames)`), asi que el orden
     * de escritura solo afecta a que bloque ve el cambio, no a la seguridad. */
    p->loop_end   = end;
    p->loop_start = start;
}

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

/* RT-SAFE: escribe 2 campos (`target_playhead`, `seek_active`), sin bucles. */
void xf_player_set_target_playhead(xf_player *p, double frame) {
    if (!p) return;
    if (frame < 0.0) { p->seek_active = 0; return; }
    double last = (double)(p->frames - 1);
    if (frame > last) frame = last;
    p->target_playhead = frame;
    p->seek_active = 1;
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

    /* Region de bucle, leida UNA vez por bloque (un `set_loop_region` a mitad no
     * tiene efecto hasta el siguiente bloque). Se SANEA aqui: aunque el hilo
     * normal escriba los dos int64 sin candado y el RT lea una combinacion
     * rasgada, `[rlo, rhi)` queda siempre dentro de `[0, frames)` -> nunca hay
     * acceso fuera de rango. Sin loop: la region es el sample entero. */
    const int do_loop = p->loop;
    int64_t rlo = do_loop ? p->loop_start : 0;
    int64_t rhi = do_loop ? p->loop_end   : p->frames;   /* exclusivo */
    if (rlo < 0 || rlo >= p->frames) rlo = 0;
    if (rhi > p->frames || rhi <= rlo + 1) rhi = p->frames;
    const int64_t rspan = rhi - rlo;   /* >= 1, y [rlo, rhi) dentro de [0, frames) */

    for (int n = 0; n < nframes; n++) {
        /* 1) velocidad libre: se desliza hacia el objetivo de Swift. Se mantiene
         *    al dia aunque haya ancla de posicion, para que SOLTAR el ancla no
         *    meta un salto de velocidad. */
        p->velocity += (target_velocity - p->velocity) * coef;
        /* flush a cero: el one-pole nunca llega a 0 del todo y una velocidad
         *    denormal dispara el modo denormal de la FPU (~100x mas lento en
         *    Intel), que al scratchear despacio se nota como tirones. */
        if (p->velocity < 1e-12 && p->velocity > -1e-12) p->velocity = 0.0;

        /* 2) la velocidad manda. Si hay ancla de posicion (ADR-042) se le suma un
         *    TRIM anti-deriva one-pole (~250 ms) ACOTADO a +-seek_max_trim: pega
         *    el cabezal a la posicion de la autopista a la larga, pero como es
         *    <=1.5% de pitch NO se oye como un barrido (el bug del "laser": el
         *    objetivo llega a escalones de 60 Hz y un one-pole rapido perseguia
         *    cada escalon de forma audible). */
        double v = p->velocity;
        if (p->seek_active) {
            double trim = (p->target_playhead - p->playhead) * p->seek_coef;
            if (trim >  p->seek_max_trim) trim =  p->seek_max_trim;
            if (trim < -p->seek_max_trim) trim = -p->seek_max_trim;
            v += trim;
        }

        /* 3) |v| y puerta por velocidad. La puerta se calcula AHORA, antes de la
         *    convolucion: si el plato esta EXACTAMENTE parado (velocidad ya
         *    flushada a 0, sin ancla) la salida seria 0 igualmente, asi que nos
         *    saltamos los 32 taps — es el caso normal mientras NO scratcheas.
         *    Solo con `av == 0` exacto: nada de umbral con banda, para no meter
         *    cortes al cruzar velocidad ~0 al scratchear (el "tiron"). El cabezal
         *    y la fase siguen avanzando igual. */
        double av = v < 0.0 ? -v : v;
        float amp = 1.0f;
        if (p->speed_gate > 0.0) {
            double g = av / p->speed_gate;
            amp = g < 1.0 ? (float)g : 1.0f;
        }

        if (av == 0.0) {
            out[n] = 0.0f;
        } else {
            int ri = xf_player_ratio_index(av);

            /* 4) parte entera y fase fraccionaria. `x` siempre es >= 0 (no-bucle
             *    saturado a [0, last]; bucle con fmod a [0, frames)), asi que
             *    truncar == floor y nos ahorramos la llamada a libm. */
            double x = p->playhead;
            int64_t i = (int64_t)x;
            double  f = x - (double)i;
            int ph = (int)(f * (double)XF_PLAYER_PHASES + 0.5);
            if (ph >= XF_PLAYER_PHASES) ph = XF_PLAYER_PHASES - 1;

            const float *k =
                p->table + ((size_t)ri * XF_PLAYER_PHASES + (size_t)ph) * XF_PLAYER_TAPS;

            /* 5) convolucion de TAPS puntos, en `float` (32 taps de float*float:
             *    error ~1e-6, muy por debajo de lo audible, y el doble de rapido
             *    que en double — es el bucle mas caliente del motor).
             *    Camino rapido: si la ventana entera cae dentro del sample (el
             *    99% de las muestras) es una convolucion contigua sin ramas, que
             *    el compilador vectoriza. Los bordes y el envoltorio del bucle
             *    van tap a tap. */
            const int64_t base = i - (XF_PLAYER_HALF - 1);   /* primer tap */
            float acc = 0.0f;
            /* camino rapido: la ventana de 32 taps cae entera dentro de la
             * region (con loop) o del sample (sin loop). Para el caso normal
             * (region = sample entero) es la misma comprobacion de antes. */
            if (base >= rlo && base + (XF_PLAYER_TAPS - 1) < rhi) {
                const float *s0 = src + base;
                for (int t = 0; t < XF_PLAYER_TAPS; t++) acc += s0[t] * k[t];
            } else {
                for (int t = 0; t < XF_PLAYER_TAPS; t++) {
                    int64_t si = base + t;
                    float s;
                    if (do_loop) {
                        /* envuelve DENTRO de la region -> el bucle de la parte
                         * es igual de continuo que el del sample entero. */
                        si = rlo + ((si - rlo) % rspan);
                        if (si < rlo) si += rspan;
                        s = src[si];
                    } else {
                        s = (si >= 0 && si <= last) ? src[si] : 0.0f;
                    }
                    acc += s * k[t];
                }
            }
            out[n] = acc * amp;
        }

        /* 6) avanza el cabezal: se satura a los extremos (el plato no se sale
         *    del sample) o da la vuelta dentro de la region si esta en bucle. */
        p->playhead += v;
        if (do_loop) {
            const double a = (double)rlo, b = (double)rhi;
            /* si el cabezal quedo MUY fuera (region recien reducida), acercalo
             * de un salto con un unico fmod; en regimen no se entra aqui. */
            if (p->playhead >= b + rspan || p->playhead < a - rspan) {
                double rel = fmod(p->playhead - a, (double)rspan);
                if (rel < 0.0) rel += (double)rspan;
                p->playhead = a + rel;
            }
            /* ajuste fino sin `fmod`: |v| <<< rspan, 0-1 vueltas en regimen. */
            while (p->playhead >= b) p->playhead -= (double)rspan;
            while (p->playhead <  a) p->playhead += (double)rspan;
        } else {
            if (p->playhead < 0.0) p->playhead = 0.0;
            if (p->playhead > (double)last) p->playhead = (double)last;
        }
    }
}
