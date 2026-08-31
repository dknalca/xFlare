/* SPDX-License-Identifier: GPL-3.0-only */
/*
 * CXFAudioCore — CAPA 0, hilo de tiempo real.
 *
 * Andamiaje (B0.1): este modulo aun no tiene logica. Aqui viviran el ring
 * buffer SPSC lock-free, el callback de CoreAudio y las primitivas RT-safe.
 * Reglas del hilo de audio en CLAUDE.md seccion 7: sin malloc, sin locks,
 * sin Swift, sin logs dentro del callback.
 */
#ifndef XF_AUDIO_CORE_H
#define XF_AUDIO_CORE_H

/* RT-SAFE: marcador de version del andamiaje. Se elimina al implementar B4. */
int xf_audio_core_scaffolding_version(void);

#endif /* XF_AUDIO_CORE_H */
