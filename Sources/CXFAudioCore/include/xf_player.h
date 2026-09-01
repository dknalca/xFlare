/* SPDX-License-Identifier: GPL-3.0-only */
/*
 * xf_player — reproductor de un sample con **resampling por velocidad y
 * direccion** (B4.3). Es el "plato": un cabezal de lectura fraccionario que
 * avanza a la velocidad del disco (1.0 = normal, negativo = hacia atras) sobre
 * un sample mono cargado en memoria.
 *
 * Antialiasing (lo que lo separa del prototipo del spike, que usaba interpolacion
 * lineal): la lectura se hace con un **sinc enventanado** cuyo corte baja al
 * subir la velocidad. Al leer mas rapido que el sample (|v| > 1) estas
 * submuestreando la fuente; sin bajar el corte apareceria aliasing. La tabla de
 * kernels se precalcula en `xf_player_create` (NO RT-SAFE); el render no reserva
 * nada (CLAUDE.md seccion 7).
 *
 * Reparto de responsabilidades: aqui SOLO se resamplea. El corte de fader, el
 * metronomo y la mezcla a estereo van aguas abajo (B4.2 / B4.4).
 *
 * Portabilidad: header module-safe (tipo opaco, C plano, sin <stdatomic.h>),
 * como `xf_ring.h`.
 */
#ifndef XF_PLAYER_H
#define XF_PLAYER_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

typedef struct xf_player xf_player;

/* NO RT-SAFE: crea el reproductor y precalcula la tabla de resampling.
 *
 *  - `sample`: PCM **mono** en float, propiedad del llamante. Tiene que seguir
 *    vivo mientras viva el `xf_player` (no se copia).
 *  - `frames`: numero de muestras de `sample` (>= 2).
 *  - `sample_rate`: en Hz (p. ej. 48000), para el suavizado de velocidad.
 *
 * Devuelve NULL si `sample` es NULL, `frames < 2`, `sample_rate == 0`, o no hay
 * memoria. */
xf_player *xf_player_create(const float *sample, int64_t frames, unsigned int sample_rate);

/* NO RT-SAFE: libera. */
void xf_player_destroy(xf_player *p);

/* RT-SAFE: escribe `nframes` muestras **mono** en `out` leyendo el sample a
 * `target_velocity` (1.0 = normal, 0 = parado, negativo = hacia atras). La
 * velocidad real se desliza hacia `target_velocity` con la constante de
 * `xf_player_set_glide_ms` para no meter clicks al cambiarla de golpe. El cabezal
 * se satura a los extremos del sample (no hace loop). */
void xf_player_render(xf_player *p, float *out, int nframes, double target_velocity);

/* RT-SAFE: posicion actual del cabezal, en frames fraccionarios. */
double xf_player_playhead(const xf_player *p);

/* NO RT-SAFE recomendado (salta el cabezal): coloca el cabezal en `frame`
 * (se satura a [0, frames-1]). Util al empezar un ejercicio. */
void xf_player_set_playhead(xf_player *p, double frame);

/* RT-SAFE: velocidad instantanea ya suavizada. */
double xf_player_velocity(const xf_player *p);

/* NO RT-SAFE: si `loop` != 0, el cabezal da la vuelta en los extremos (modulo
 * `frames`) en vez de saturarse, y la lectura sinc envuelve por los bordes. Para
 * bases instrumentales en bucle. Por defecto 0 (se satura, como el plato). */
void xf_player_set_loop(xf_player *p, bool loop);

/* NO RT-SAFE: puerta por velocidad. Si `gate_velocity > 0`, la amplitud de
 * salida escala con `min(1, |v| / gate_velocity)`: el disco casi parado casi no
 * suena (como un vinilo de verdad), y desaparece el zumbido de DC del cabezal
 * quieto. `0` = desactivada (por defecto; asi la base instrumental suena plana). */
void xf_player_set_speed_gate(xf_player *p, double gate_velocity);

/* NO RT-SAFE: tiempo (ms) que tarda la velocidad en alcanzar el objetivo.
 * `0` = sin suavizado (salta). Por defecto 5 ms. */
void xf_player_set_glide_ms(xf_player *p, double ms);

#endif /* XF_PLAYER_H */
