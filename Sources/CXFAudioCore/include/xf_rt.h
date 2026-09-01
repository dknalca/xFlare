/* SPDX-License-Identifier: GPL-3.0-only */
/*
 * xf_rt — prioridad de tiempo real para el hilo de audio (B4.2).
 *
 * En todas las maquinas objetivo hay que fijar la politica
 * `THREAD_TIME_CONSTRAINT_POLICY` con `thread_policy_set` (funciona tambien en
 * Intel, a diferencia de los audio workgroups). En Apple Silicon, ADEMAS, el
 * hilo se une al workgroup del dispositivo de audio (nucleos P/E) — eso lo hace
 * `xf_engine` porque necesita el `AudioDeviceID`.
 *
 * Header module-safe (C plano), como el resto de CXFAudioCore.
 */
#ifndef XF_RT_H
#define XF_RT_H

#include <stdbool.h>
#include <stdint.h>

/* NO RT-SAFE: calcula los parametros de `thread_time_constraint_policy` para un
 * hilo que despierta cada `buffer_frames` a `sample_rate` Hz. Los valores salen
 * en **unidades de mach_absolute_time** (ya convertidos con `mach_timebase_info`).
 *
 *  - `period`      = duracion de un buffer (cada cuanto despierta el hilo).
 *  - `computation` = tiempo de CPU que decimos que necesita por vuelta (~50 %).
 *  - `constraint`  = plazo maximo desde que despierta hasta que termina (~90 %).
 *
 * Devuelve false si `sample_rate <= 0` o `buffer_frames == 0`. */
bool xf_rt_time_constraint_params(double sample_rate, uint32_t buffer_frames,
                                  uint32_t *period, uint32_t *computation,
                                  uint32_t *constraint);

/* NO RT-SAFE (llamar UNA vez, desde el propio hilo de audio, en el primer
 * callback): fija `THREAD_TIME_CONSTRAINT_POLICY` en el hilo actual con los
 * parametros de arriba. Devuelve true si `thread_policy_set` tuvo exito. */
bool xf_rt_promote_current_thread(double sample_rate, uint32_t buffer_frames);

#endif /* XF_RT_H */
