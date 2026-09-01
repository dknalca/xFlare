/* SPDX-License-Identifier: GPL-3.0-only */
/*
 * spike B4 — banco de pruebas del motor de audio.
 *
 * QUE ES: un prototipo DESECHABLE para "sentir" el motor antes de tenerlo en
 * serio (CXFAudioCore, bloque B4). Simula el timecode con el trackpad y el corte
 * del crossfader con una tecla, y suena: una instrumental de fondo + un sample
 * scratcheado por el "plato".
 *
 * QUE NO ES: el motor definitivo. No hay ring buffer, no hay timecode real, la
 * resamplificacion es lineal (sin antialiasing serio). El callback SI respeta las
 * reglas del hilo de audio (CLAUDE.md §7): C puro, sin malloc, sin locks, sin
 * printf; se comunica con la UI (Swift) solo por atomicas.
 *
 * La UI (ventana, trackpad, teclado) va en Swift (`sandbox.swift`); esto es la
 * parte C. Es el reparto real del proyecto: Swift arriba, C en el hilo de audio.
 */
#ifndef SANDBOX_AUDIO_H
#define SANDBOX_AUDIO_H

#include <stdbool.h>

/* NO RT-SAFE: decodifica los dos mp3 a PCM float en memoria. Devuelve 0 si OK,
 * un codigo < 0 si algo falla (fichero no encontrado, formato raro...). */
int  sandbox_load(const char *scratch_path, const char *instrumental_path);

/* NO RT-SAFE: abre la salida de audio por defecto y arranca el callback.
 * Devuelve 0 si OK. */
int  sandbox_start(void);

/* NO RT-SAFE: para y libera. */
void sandbox_stop(void);

/* --- parametros que fija la UI (hilo normal); el callback los lee por atomica --- */

/* Velocidad objetivo del plato. 1.0 = reproduccion normal, 0 = parado,
 * negativo = hacia atras. El callback la suaviza (glide) para no escalonar. */
void   sandbox_set_velocity(double v);
/* Fader: true = abierto (se oye el scratch), false = cortado. */
void   sandbox_set_fader_open(bool open);
/* Rebobina el sample de scratch al principio. */
void   sandbox_reset_scratch(void);

/* --- lecturas para el HUD (hilo normal, aproximadas) --- */
double sandbox_get_velocity(void);       /* velocidad suavizada actual */
double sandbox_get_scratch_pos(void);    /* 0..1, posicion en el sample */
double sandbox_get_out_peak(void);       /* pico de salida reciente, 0..~1 */
bool   sandbox_get_fader_open(void);
double sandbox_get_scratch_seconds(void);/* duracion del sample cargado */

#endif /* SANDBOX_AUDIO_H */
