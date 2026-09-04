/* SPDX-License-Identifier: GPL-3.0-only */
/*
 * xf_engine — el motor de audio en tiempo real (B4.2). Une lo del bloque B4:
 * el ring buffer SPSC (B4.1), el reproductor con resampling (B4.3) y el
 * metronomo (B4.4), y los conecta a una AudioUnit HAL duplex a 64 frames.
 *
 * DOS PARTES:
 *
 *  1. El **nucleo RT** (`xf_engine_render`), sin CoreAudio: dado un bloque de
 *     entrada del dispositivo produce el bloque de salida (scratch + metronomo)
 *     y mete la entrada en el ring para que Swift la drene (timecode, fader).
 *     Se puede probar entero sin hardware.
 *
 *  2. El **host CoreAudio** (`xf_engine_start` / `xf_engine_stop`): abre la
 *     AudioUnit HAL, fija 64 frames, instala el callback que llama a
 *     `xf_engine_render`, y en el primer callback promociona el hilo
 *     (`THREAD_TIME_CONSTRAINT_POLICY`) y lo une al workgroup del dispositivo
 *     (obligatorio en Apple Silicon). **Sin tests: necesita un dispositivo.**
 *
 * Reglas del hilo de audio (CLAUDE.md 7): `xf_engine_render` no reserva memoria,
 * no bloquea, no hace syscalls. Habla con Swift solo por atomicas y el ring.
 *
 * Header module-safe (tipo opaco, C plano).
 */
#ifndef XF_ENGINE_H
#define XF_ENGINE_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#include "xf_ring.h"
#include "xf_metronome.h"

typedef struct xf_engine xf_engine;

/* NO RT-SAFE: crea el motor. `sample_rate` en Hz, `max_frames` = tope de frames
 * por callback (64, o 128 si el buffer sube). Reserva todos los buffers y el
 * ring de entrada aqui. Devuelve NULL si algo es 0 o falta memoria. */
xf_engine *xf_engine_create(double sample_rate, uint32_t max_frames);

/* NO RT-SAFE: libera. Si estaba sonando, para primero. */
void xf_engine_destroy(xf_engine *e);

/* ---- carga y transporte (NO RT-SAFE, desde el hilo normal) ---- */

/* Carga el sample de scratch (PCM **mono** float, propiedad del llamante, tiene
 * que seguir vivo). Se puede llamar sonando: el cambio de reproductor es
 * atomico y el anterior se retira sin `free` en el hilo RT. */
void xf_engine_load_sample(xf_engine *e, const float *sample, int64_t frames);

/* Fija el transporte: BPM, PPQ del patron y si esta sonando. */
void xf_engine_set_transport(xf_engine *e, double bpm, int ppq, bool playing);

/* Carga la base instrumental (PCM **mono** float, propiedad del llamante, tiene
 * que seguir vivo). `native_bpm` es el tempo al que se grabo: el motor la
 * reproduce en bucle a `bpm / native_bpm` para que quede pegada al tempo de la
 * sesion (cambia de pitch, como tirar de un break en el plato). `native_bpm <= 0`
 * o `mono == NULL` la quita. Se puede llamar sonando (swap atomico, 1 retiro). */
void xf_engine_load_instrumental(xf_engine *e, const float *mono, int64_t frames,
                                 double native_bpm);

/* Ganancia de la base instrumental (0..1). Atomica. Por defecto 0.5. */
void xf_engine_set_instrumental_gain(xf_engine *e, float gain);

/* Reinterpreta a que tempo se grabo la base **sin recrear el player** (no toca
 * el cabezal, no reinicia el bucle). Recalcula el ratio de reproduccion con el
 * BPM de sesion actual. Para TAP tempo / edicion del BPM a mano: la rejilla
 * cambia en caliente y la base sigue sonando donde estaba. No hace nada si no
 * hay base cargada. */
void xf_engine_set_instrumental_native_bpm(xf_engine *e, double native_bpm);

/* Acota el bucle de la base a la region `[start, end)` en frames: la base
 * repite SOLO esa parte (loops infinitos de un trozo, editor de instrumental).
 * `start < 0`, `end` fuera de rango o menos de 2 frames -> base entera. No hace
 * nada si no hay base. Se aplica en el siguiente bloque. NO RT-SAFE. */
void xf_engine_set_instrumental_loop_region(xf_engine *e, int64_t start, int64_t end);

/* Coloca el reloj musical en `tick` (p. ej. el inicio de la cuenta atras, que es
 * negativo). Resincroniza el metronomo. */
void xf_engine_seek_tick(xf_engine *e, double tick);

/* Desfase (en ticks) que se le suma al METRONOMO para que siga a la rejilla
 * cuando el usuario la mueve con los botones ◀/▶ de la práctica (`gridShift`).
 * No toca el reloj musical ni la base — solo dónde caen los clics. El cambio se
 * re-fasea en el hilo RT sin meter un clic de más. Un `xf_engine_seek_tick` lo
 * vuelve a poner a 0. NO RT-SAFE. */
void xf_engine_set_metronome_offset(xf_engine *e, double ticks);

/* Corrección CONTINUA de la deriva entre el reloj del motor (cristal de audio) y
 * el reloj de pared de la sesión que dibuja la rejilla. La capa Swift la calcula
 * (`session.tick() + gridShift - engine.tick`) suavizada y la empuja unas veces
 * por segundo; el metronomo la suma a su tick sin re-fasear (cambia poquito).
 * Un `xf_engine_seek_tick` la pone a 0. NO RT-SAFE. */
void xf_engine_set_metronome_drift(xf_engine *e, double ticks);

/* Coloca el cabezal del reproductor de scratch en `frame` (se satura a
 * [0, frames-1]). Para arrancar el sample desde el principio al entrar. */
void xf_engine_seek_scratch(xf_engine *e, double frame);

/* Coloca el cabezal de la BASE instrumental en `frame` (se satura a
 * [0, frames-1]). Para el editor de instrumental (pinchar la onda = saltar).
 * NO RT-SAFE. */
void xf_engine_seek_instrumental(xf_engine *e, double frame);

/* Ancla el cabezal de scratch a `frame` como **trim anti-deriva ACOTADO**
 * (ADR-042): NO mueve el cabezal (lo hace `xf_engine_set_velocity`), solo evita
 * que el scratch se separe de la posicion de la autopista a la larga, con una
 * correccion <=1,5% de pitch que no se oye. `frame < 0` = suelta el ancla.
 * Atomica; el trim lo aplica `xf_player_set_target_playhead` en el hilo RT. */
void xf_engine_set_scratch_target(xf_engine *e, double frame);

/* Velocidad objetivo del plato (1.0 normal, negativo hacia atras). La pone la
 * capa de captura a partir del timecode / teclado. Atomica. */
void xf_engine_set_velocity(xf_engine *e, double velocity);

/* Ganancia de salida (0..1). Atomica. */
void xf_engine_set_master_gain(xf_engine *e, float gain);

/* Ganancia SOLO del reproductor de scratch (0..1). La base instrumental y el
 * metronomo no se ven afectados. Se suaviza en ~5 ms para no meter un click al
 * pasar de 1 a 0 (fader cerrado / mute). Atomica. Por defecto 1. */
void xf_engine_set_scratch_gain(xf_engine *e, float gain);

/* "Tacto" del plato (ventana Debug). Se aplican al reproductor de scratch al
 * cargarlo y al vuelo. NO RT-SAFE (se llaman desde el hilo normal).
 *  - `glide_ms`: suavizado de la velocidad del plato. Menos = mas seco, el audio
 *    sigue mejor al gesto; mas = mas suave pero con retardo. Por defecto 3 ms.
 *  - `speed_gate`: |v| por debajo de la cual el scratch no suena (mata el zumbido
 *    del cabezal quieto). Por defecto 0,12. `0` = sin puerta. */
void xf_engine_set_scratch_glide_ms(xf_engine *e, double glide_ms);
void xf_engine_set_scratch_speed_gate(xf_engine *e, double speed_gate);

/* EQ de 3 bandas (Lo / Mid / Hi) **solo sobre el sample de scratch** — la base
 * instrumental y el metronomo no se tocan. Ganancias en dB, se acotan a
 * [-24, +12]; 0/0/0 = plano y el motor se salta el filtrado. NO RT-SAFE (disena
 * los filtros con sin/cos/sqrt); los coeficientes se publican por doble buffer y
 * el estado de los biquads no se resetea, asi que mover un mando no mete un
 * click. Lo shelf 200 Hz, Mid peak 1 kHz (Q 0,9), Hi shelf 4 kHz. */
void xf_engine_set_sample_eq(xf_engine *e, float low_db, float mid_db, float high_db);

/* ---- lo que consulta / usa Swift ---- */

/* El ring de PCM de entrada: **estereo intercalado de 16 bits**. Swift lo drena
 * con `xf_ring_read` y alimenta `xf_timecoder` / `AudioReturnFaderSource`. */
xf_ring_t *xf_engine_input_ring(xf_engine *e);

/* El metronomo, para activarlo/desactivarlo (`xf_metronome_set_enabled`). */
xf_metronome *xf_engine_metronome(xf_engine *e);

/* RT-SAFE: tick musical al inicio del ultimo bloque renderizado. La autopista lo
 * lee para ir sincronizada al reloj de AUDIO (no al frame). */
double xf_engine_tick(const xf_engine *e);

/* Posicion del cabezal del reproductor de scratch, en frames fraccionarios del
 * sample cargado (0 si no hay sample). Para pintar la onda del sample con una
 * barra que sigue donde estas scratcheando. Lectura de un `double` alineado:
 * puede haber un desfase de un bloque, da igual para la UI. */
double xf_engine_scratch_playhead(const xf_engine *e);

/* Posicion del cabezal de la BASE instrumental, en frames fraccionarios. `< 0`
 * si no hay base cargada. Para dibujar la tira de la instrumental pegada al
 * audio (no a un reloj de ticks, que se descuadra al cambiar el tempo). */
double xf_engine_instrumental_playhead(const xf_engine *e);

/* Diagnostico (atomicas): overloads del dispositivo y fallos de `AudioUnitRender`. */
uint64_t xf_engine_overload_count(const xf_engine *e);
uint64_t xf_engine_render_error_count(const xf_engine *e);

/* Pico de la salida (0..~) **antes** de limitar, con decaimiento lento. Para el
 * medidor de nivel de la UI: si pasa de 1,0, la mezcla estaba clipeando. */
double xf_engine_output_peak(const xf_engine *e);

/* ---- nucleo RT (testeable, sin CoreAudio) ---- */

/* RT-SAFE: procesa un bloque.
 *
 *  - `in_l` / `in_r`: entrada del dispositivo, **float no intercalado**, o NULL
 *    si este tic no hubo entrada (se mete silencio en el ring).
 *  - `out_l` / `out_r`: salida al dispositivo, **float no intercalado**.
 *  - `nframes` <= `max_frames`.
 *  - `host_time`: instante del bloque (mach_absolute_time), para sellar el ring.
 *
 * Efectos: convierte la entrada a int16 estereo y la escribe en el ring;
 * sintetiza la salida (reproductor + metronomo, con la ganancia de master);
 * avanza el reloj musical si el transporte esta sonando. */
void xf_engine_render(xf_engine *e,
                      const float *in_l, const float *in_r,
                      float *out_l, float *out_r,
                      int nframes, uint64_t host_time);

/* ---- host CoreAudio (compila; sin tests, necesita dispositivo) ---- */

/* NO RT-SAFE: abre la AudioUnit HAL sobre el dispositivo `device_uid` (NULL =
 * el de salida por defecto), fija `max_frames` como buffer, arranca. Devuelve 0
 * si todo OK, o un OSStatus/-1 si falla. */
int xf_engine_start(xf_engine *e, const char *device_uid);

/* NO RT-SAFE: como `xf_engine_start` pero **solo salida** (sin capturar la
 * entrada del dispositivo). Para practicar con la mesa desconectada: suena el
 * scratch y la base, y el ring de entrada queda en silencio. Devuelve 0 / -1. */
int xf_engine_start_output(xf_engine *e, const char *device_uid);

/* NO RT-SAFE: para y cierra la AudioUnit. */
void xf_engine_stop(xf_engine *e);

/* Version del contrato del modulo (sustituye al marcador de andamiaje). */
int xf_engine_api_version(void);

#endif /* XF_ENGINE_H */
