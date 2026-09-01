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

/* Coloca el reloj musical en `tick` (p. ej. el inicio de la cuenta atras, que es
 * negativo). Resincroniza el metronomo. */
void xf_engine_seek_tick(xf_engine *e, double tick);

/* Velocidad objetivo del plato (1.0 normal, negativo hacia atras). La pone la
 * capa de captura a partir del timecode / teclado. Atomica. */
void xf_engine_set_velocity(xf_engine *e, double velocity);

/* Ganancia de salida (0..1). Atomica. */
void xf_engine_set_master_gain(xf_engine *e, float gain);

/* ---- lo que consulta / usa Swift ---- */

/* El ring de PCM de entrada: **estereo intercalado de 16 bits**. Swift lo drena
 * con `xf_ring_read` y alimenta `xf_timecoder` / `AudioReturnFaderSource`. */
xf_ring_t *xf_engine_input_ring(xf_engine *e);

/* El metronomo, para activarlo/desactivarlo (`xf_metronome_set_enabled`). */
xf_metronome *xf_engine_metronome(xf_engine *e);

/* RT-SAFE: tick musical al inicio del ultimo bloque renderizado. La autopista lo
 * lee para ir sincronizada al reloj de AUDIO (no al frame). */
double xf_engine_tick(const xf_engine *e);

/* Diagnostico (atomicas): overloads del dispositivo y fallos de `AudioUnitRender`. */
uint64_t xf_engine_overload_count(const xf_engine *e);
uint64_t xf_engine_render_error_count(const xf_engine *e);

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
