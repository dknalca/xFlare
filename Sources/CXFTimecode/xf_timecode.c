/* SPDX-License-Identifier: GPL-3.0-only */
#include "xf_timecode.h"

#include "timecoder.h"   /* xwax, vendorizado INTACTO. Solo se incluye aqui. */

#include <math.h>
#include <stdlib.h>
#include <string.h>

/* Buffer maximo por trozo al copiar/intercambiar canales (frames). Un submit
 * mas largo se procesa en varios trozos. */
#define CHUNK_FRAMES 8192

/* Nivel RMS de referencia de una senal de timecode "sana" (int16). Muy por
 * debajo de lo que da un vinilo real (~8000-12000); sirve para que la confianza
 * suba con poca senal y baje del todo con silencio. */
#define RMS_REF 1500.0

struct xf_timecoder {
    struct timecoder tc;
    struct timecode_def *def;
    double sr;
    bool reversed;

    double vel;        /* ultima velocidad con signo */
    double pos;        /* posicion relativa acumulada */
    double rms_env;    /* envolvente del RMS de entrada */
    float  conf;

    int16_t chunk[CHUNK_FRAMES * 2];
};

/* NO RT-SAFE */
xf_timecoder *xf_timecoder_create(const char *def_name, unsigned int sample_rate) {
    if (sample_rate == 0) return NULL;
    struct timecode_def *def = timecoder_find_definition(def_name ? def_name : "serato_2a");
    if (def == NULL) return NULL;

    xf_timecoder *x = (xf_timecoder *)calloc(1, sizeof(*x));
    if (x == NULL) return NULL;

    x->def = def;
    x->sr = (double)sample_rate;
    x->reversed = false;
    x->vel = 0.0;
    x->pos = 0.0;
    x->rms_env = 0.0;
    x->conf = 0.0f;

    /* speed = 1.0 (velocidad de referencia), phono = false (entrada de linea
     * por USB, no un previo de phono). */
    timecoder_init(&x->tc, def, 1.0, sample_rate, false);
    return x;
}

/* NO RT-SAFE */
void xf_timecoder_destroy(xf_timecoder *x) {
    if (x == NULL) return;
    timecoder_clear(&x->tc);
    free(x);
}

/* Procesa un trozo ya copiado en x->chunk (nframes <= CHUNK_FRAMES), con los
 * canales intercambiados si toca. Actualiza vel/pos/rms. */
static void process_chunk(xf_timecoder *x, size_t nframes) {
    if (x->reversed) {
        for (size_t i = 0; i < nframes; i++) {
            int16_t l = x->chunk[i * 2 + 0];
            x->chunk[i * 2 + 0] = x->chunk[i * 2 + 1];
            x->chunk[i * 2 + 1] = l;
        }
    }

    /* RMS del trozo (canal izquierdo, suficiente como indicador de presencia) */
    double sumsq = 0.0;
    for (size_t i = 0; i < nframes; i++) {
        double s = (double)x->chunk[i * 2 + 0];
        sumsq += s * s;
    }
    double chunk_rms = nframes ? sqrt(sumsq / (double)nframes) : 0.0;
    /* un polo, ~coeficiente por trozo; con trozos de 8192 @ 48k es ~170 ms */
    x->rms_env += (chunk_rms - x->rms_env) * 0.35;

    timecoder_submit(&x->tc, x->chunk, nframes);

    x->vel = timecoder_get_pitch(&x->tc);
    x->pos += x->vel * (double)nframes / x->sr;

    /* confianza: presencia de senal (RMS) recortada a 0..1, penalizada si la
     * velocidad es absurda. Si xwax ademas ha enganchado el bitstream
     * (get_position >= 0), confianza plena. */
    float rms_conf = (float)(x->rms_env / RMS_REF);
    if (rms_conf > 1.0f) rms_conf = 1.0f;
    if (rms_conf < 0.0f) rms_conf = 0.0f;
    if (fabs(x->vel) > 4.0) rms_conf *= 0.3f;

    double when;
    bool locked = (timecoder_get_position(&x->tc, &when) >= 0);
    x->conf = locked ? 1.0f : rms_conf;
}

/* RT-SAFE */
void xf_timecoder_submit(xf_timecoder *x, const int16_t *pcm, size_t nframes) {
    if (x == NULL || pcm == NULL) return;
    size_t off = 0;
    while (off < nframes) {
        size_t n = nframes - off;
        if (n > CHUNK_FRAMES) n = CHUNK_FRAMES;
        memcpy(x->chunk, pcm + off * 2, n * 2 * sizeof(int16_t));
        process_chunk(x, n);
        off += n;
    }
    if (nframes == 0) {
        /* aun con 0 frames dejamos la confianza decaer hacia el ultimo RMS */
        x->conf = (float)(x->rms_env / RMS_REF);
        if (x->conf > 1.0f) x->conf = 1.0f;
        if (x->conf < 0.0f) x->conf = 0.0f;
    }
}

double xf_timecoder_velocity(const xf_timecoder *x)   { return x ? x->vel : 0.0; }
double xf_timecoder_position(const xf_timecoder *x)   { return x ? x->pos : 0.0; }
float  xf_timecoder_confidence(const xf_timecoder *x) { return x ? x->conf : 0.0f; }

/* F.76 (ADR-080). `timecoder_get_position` es una lectura pura (no muta
 * estado real: solo mira `bitstream`/`valid_counter`, ya actualizados por
 * `process_chunk`); el cast quita el `const` para llamar a xwax, que no es
 * const-correcto en esta firma. El entero crudo (bits desde el arranque del
 * LFSR) se divide aqui por `resolution` (bits/segundo a velocidad nominal,
 * `x->def->resolution` -- el mismo campo que usa `timecoder_get_resolution`
 * dentro de xwax) para devolver SEGUNDOS NOMINALES, la misma unidad que
 * `xf_timecoder_position()`: quien llama puede restar directamente sin tener
 * que conocer la resolucion de cada formato de vinilo. */
double xf_timecoder_absolute_position(const xf_timecoder *x, double *when) {
    double w = 0.0;
    double result = -1.0;
    if (x) {
        int r = timecoder_get_position((struct timecoder *)&x->tc, &w);
        if (r >= 0) result = (double)r / (double)x->def->resolution;
    }
    if (when) *when = w;
    return result;
}

bool xf_timecoder_locked(const xf_timecoder *x) {
    return xf_timecoder_absolute_position(x, NULL) >= 0;
}

bool xf_timecoder_forwards(const xf_timecoder *x) {
    return x ? x->tc.forwards : true;
}

/* NO RT-SAFE */
void xf_timecoder_set_reversed(xf_timecoder *x, bool reversed) {
    if (x) x->reversed = reversed;
}

/* NO RT-SAFE */
void xf_timecoder_reset_position(xf_timecoder *x) {
    if (x) x->pos = 0.0;
}

int xf_timecode_scaffolding_version(void) { return 1; }
