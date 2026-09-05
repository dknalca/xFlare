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

/* RT-SAFE: escribe `nframes` muestras **mono** en `out` leyendo el sample.
 * (1.0 = normal, 0 = parado, negativo = hacia atras). La velocidad OBJETIVO no
 * es constante dentro del bloque: va de `target_velocity_start` (primera
 * muestra) a `target_velocity_end` (ultima) en RAMPA LINEAL (F.46) — asi un
 * bloque grande (varios ms) no le impone al player un escalon que perseguir,
 * sino un objetivo que ya se mueve solo. Para velocidad constante, pasa el
 * mismo valor en los dos (`start == end`). La velocidad REAL se sigue
 * deslizando hacia ese objetivo (ya movil) con la constante de
 * `xf_player_set_glide_ms`, para no meter clicks. El cabezal se satura a los
 * extremos del sample (no hace loop). */
void xf_player_render(xf_player *p, float *out, int nframes,
                      double target_velocity_start, double target_velocity_end);

/* RT-SAFE: posicion actual del cabezal, en frames fraccionarios. */
double xf_player_playhead(const xf_player *p);

/* NO RT-SAFE recomendado (salta el cabezal): coloca el cabezal en `frame`
 * (se satura a [0, frames-1]). Util al empezar un ejercicio. */
void xf_player_set_playhead(xf_player *p, double frame);

/* RT-SAFE: ancla de posicion, en forma de TRIM anti-deriva (NO es el driver del
 * cabezal: lo es `target_velocity`). Si `frame >= 0`, cada muestra se suma a la
 * velocidad `(frame - cabezal) * k` con k de one-pole ~250 ms, ACOTADO a
 * +-0.015 frames/muestra (~1.5% de pitch) para que la correccion no se oiga
 * nunca como un barrido. Sirve para que el scratch no se separe de la posicion
 * de la autopista a la larga (ADR-042). `frame < 0` suelta el ancla. */
void xf_player_set_target_playhead(xf_player *p, double frame);

/* RT-SAFE: velocidad instantanea ya suavizada. */
double xf_player_velocity(const xf_player *p);

/* NO RT-SAFE: si `loop` != 0, el cabezal da la vuelta en los extremos (modulo
 * `frames`) en vez de saturarse, y la lectura sinc envuelve por los bordes. Para
 * bases instrumentales en bucle. Por defecto 0 (se satura, como el plato). */
void xf_player_set_loop(xf_player *p, bool loop);

/* NO RT-SAFE: acota el bucle a la region `[start, end)` en frames (solo tiene
 * efecto con `loop` activo). El cabezal envuelve dentro de esa parte y la
 * lectura sinc tambien, asi que el bucle de una PARTE de la base es igual de
 * continuo que el del sample entero. `start < 0`, `end > frames` o menos de 2
 * frames de region -> se usa el sample entero (0..frames). El cambio se aplica
 * en el siguiente bloque de render. */
void xf_player_set_loop_region(xf_player *p, int64_t start, int64_t end);

/* NO RT-SAFE: puerta por velocidad. Si `gate_velocity > 0`, la amplitud de
 * salida sube de 0 a 1 con un TAPER DE COSENO ALZADO (pendiente cero en los
 * dos extremos, sin esquinas — F.47) segun `|v|` se acerca a `gate_velocity`:
 * el disco casi parado casi no suena (como un vinilo de verdad). Dentro de
 * esa zona (SOLO ahi — fuera, a velocidad normal, no se toca la senal) va
 * ademas un bloqueador de DC de un polo, que quita el zumbido de continua
 * del cabezal casi quieto (deja bajar el umbral sin que vuelva). `0` =
 * desactivada (por defecto; asi la base instrumental suena plana). */
void xf_player_set_speed_gate(xf_player *p, double gate_velocity);

/* NO RT-SAFE: tiempo (ms) que tarda la velocidad en alcanzar el objetivo.
 * `0` = sin suavizado (salta). Por defecto 5 ms. */
void xf_player_set_glide_ms(xf_player *p, double ms);

/* NO RT-SAFE (F.75, ADR-079): afina el TRIM del ancla de `set_target_playhead`
 * — cuanto tarda en corregir (`ms`, one-pole, por defecto ~250 ms) y cuanto
 * puede corregir por muestra como maximo (`max_trim`, frames/muestra, por
 * defecto 0.015 = 1.5% de pitch). Con una fuente de posicion RUIDOSA (raton)
 * hace falta lento para no oírse como un barrido; con una FIABLE (timecode
 * real) puede hacer falta mas rapido si el trim por defecto no da abasto y
 * el audio se queda atras del gesto ("sticker drift" en el audio, aunque la
 * pantalla ya vaya bien). `ms <= 0` corrige de golpe; `max_trim <= 0` apaga
 * el trim (dentro de los limites que aplique `xf_engine_set_scratch_seek_trim`
 * si se llega por ahi). */
void xf_player_set_seek_trim(xf_player *p, double ms, double max_trim);

#endif /* XF_PLAYER_H */
