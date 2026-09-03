/* SPDX-License-Identifier: GPL-3.0-only */
/*
 * xf_eq — EQ de 3 bandas (Lo / Mid / Hi) para una senal **mono**. Pensada para
 * el sample de scratch: barata, estable, y **sin clicks al mover los mandos**.
 *
 *   Lo   low-shelf   @ 200 Hz
 *   Mid  peaking      @ 1 kHz, Q 0.9
 *   Hi   high-shelf   @ 4 kHz
 *
 * Biquads en forma directa II traspuesta (TDF-II): al cambiar los coeficientes
 * en caliente el estado no revienta ni pega un salto. Ademas los coeficientes
 * se publican por **doble buffer** (el hilo normal calcula en el inactivo y lo
 * voltea; el hilo RT lee el activo una vez por bloque), asi que
 * `xf_eq_set_gains_db` puede llamarse mientras suena.
 *
 * Reparto: `xf_eq_set_gains_db` NO es RT-safe (usa sin/cos/sqrt para disenar los
 * filtros) y se llama desde el hilo normal cuando el usuario mueve un mando;
 * `xf_eq_process_block` SI es RT-safe (solo multiplica y suma) y filtra el
 * bloque in-place en el hilo de audio.
 *
 * Estructura concreta (como `xf_ring_t`): C plano, sin <stdatomic.h> en el
 * header — el .c usa los builtins `__atomic_*` para el indice del doble buffer.
 */
#ifndef XF_EQ_H
#define XF_EQ_H

/* Un biquad con a0 ya normalizado a 1. */
typedef struct { float b0, b1, b2, a1, a2; } xf_biquad;

/* Estado TDF-II de un biquad (dos retardos). Propiedad del hilo RT. */
typedef struct { float z1, z2; } xf_biquad_z;

typedef struct {
    double     sample_rate;
    xf_biquad  target[2][3];   /* [generacion][banda] — coeficientes objetivo, doble buffer */
    xf_biquad  cur[3];         /* coeficientes en uso: rampa hacia `target` (solo RT) */
    xf_biquad_z z[3];          /* estado por banda, solo lo toca el hilo RT */
    int        active_gen;     /* atomico en el .c: la generacion de `target` que sigue el RT */
    int        want_flat;      /* atomico en el .c: 1 si el objetivo es plano (0/0/0 dB) */
    int        running;        /* RT: 1 mientras `cur` no sea identidad (hay que filtrar) */
    float      gain_db[3];     /* ultimo Lo/Mid/Hi pedido (solo hilo normal) */
} xf_eq;

/* Rango de ganancia por banda, en dB (se acota a esto). */
#define XF_EQ_MIN_DB (-24.0f)
#define XF_EQ_MAX_DB (12.0f)

/* NO RT-SAFE: deja la EQ **plana** y a `sample_rate` Hz. */
void xf_eq_init(xf_eq *eq, double sample_rate);

/* NO RT-SAFE: fija Lo/Mid/Hi en dB (se acotan a [XF_EQ_MIN_DB, XF_EQ_MAX_DB]) y
 * disena los tres biquads objetivo. El hilo RT hace una **rampa de ~20 ms** de
 * los coeficientes en uso hacia esos, asi que mover un mando de golpe no mete un
 * click. Si las tres quedan a ~0 dB, el objetivo es "plano" y cuando la rampa
 * llega, el filtrado se salta entero. */
void xf_eq_set_gains_db(xf_eq *eq, float low_db, float mid_db, float high_db);

/* RT-SAFE: filtra `n` muestras de `x` in-place. Si el objetivo es plano y la
 * rampa ya ha llegado, no hace nada. */
void xf_eq_process_block(xf_eq *eq, float *x, int n);

#endif /* XF_EQ_H */
