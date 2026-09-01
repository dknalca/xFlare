/* SPDX-License-Identifier: GPL-3.0-only */
/*
 * xf_metronome — la claqueta (B4.4). Se **mezcla en la salida principal**, no en
 * un canal aparte (ADR-007: en una mesa de dos canales, un canal para la
 * claqueta es perderla). Se activa/desactiva con un solo control.
 *
 * No lleva el tiempo por su cuenta: el callback de audio le pasa en cada bloque
 * la posicion musical de inicio (en ticks, PPQ del patron) y el BPM, y el
 * metronomo dispara un click en cada negra. El primer tiempo del compas va
 * acentuado (mas agudo). Con la posicion negativa (cuenta atras del transporte)
 * tambien suena: sale gratis la claqueta de los dos compases previos.
 *
 * El click es una senoide con ataque rapido y caida exponencial (~60 ms), y se
 * **suma** a `out` (mono). La sintesis no reserva memoria (regla CLAUDE.md 7).
 *
 * Header module-safe (tipo opaco, C plano), como `xf_ring.h` / `xf_player.h`.
 */
#ifndef XF_METRONOME_H
#define XF_METRONOME_H

#include <stdbool.h>

typedef struct xf_metronome xf_metronome;

/* NO RT-SAFE: crea el metronomo. `sample_rate` en Hz. Por defecto: activado,
 * nivel 0.35, compas de 4 por PPQ 480. Devuelve NULL si `sample_rate == 0` o
 * falta memoria. */
xf_metronome *xf_metronome_create(unsigned int sample_rate);

/* NO RT-SAFE: libera. */
void xf_metronome_destroy(xf_metronome *m);

/* RT-SAFE (atomica): el unico control. */
void xf_metronome_set_enabled(xf_metronome *m, bool on);
bool xf_metronome_enabled(const xf_metronome *m);

/* NO RT-SAFE: nivel de mezcla (0..1) y compas. `ppq` = ticks por negra. */
void xf_metronome_set_level(xf_metronome *m, float level);
void xf_metronome_set_time_signature(xf_metronome *m, int beats_per_bar, int ppq);

/* RT-SAFE: **suma** la claqueta en `out` (mono, `nframes`) para un bloque que
 * empieza en la posicion musical `tick_at_start` y avanza a `bpm`. Dispara un
 * click al cruzar cada negra; el primer tiempo del compas va acentuado. Si esta
 * desactivado no toca `out`, pero deja morir el click en curso para no soltar
 * una rafaga al reactivar. */
void xf_metronome_render(xf_metronome *m, float *out, int nframes,
                         double tick_at_start, double bpm);

/* NO RT-SAFE: reengancha el contador de tiempos a `tick` **sin disparar** el
 * tiempo actual (el siguiente cruce si). Para cuando el transporte arranca o
 * salta. */
void xf_metronome_resync(xf_metronome *m, double tick);

#endif /* XF_METRONOME_H */
