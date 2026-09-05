/* SPDX-License-Identifier: GPL-3.0-only */
/*
 * CXFTimecode — CAPA 0. Wrapper propio sobre el decoder de xwax, en **modo
 * relativo** (ADR-004/005): solo velocidad y direccion del disco, sin posicion
 * absoluta de la aguja.
 *
 * El codigo vendorizado de xwax (`vendor/xwax/timecoder.c`, `lut.c`) NO se toca
 * (ADR / CLAUDE.md §8). Toda adaptacion va aqui.
 *
 * Nota de portabilidad: este header NO incluye `timecoder.h` a proposito. Ese
 * header arrastra las tripas de xwax y romperia `import CXFTimecode` desde Swift
 * (mismo problema que `<stdatomic.h>` en `xf_ring.h`). El tipo `xf_timecoder` es
 * opaco; las tripas viven en `xf_timecode.c`.
 */
#ifndef XF_TIMECODE_H
#define XF_TIMECODE_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

typedef struct xf_timecoder xf_timecoder;

/* NO RT-SAFE: crea el decoder para el formato `def_name` de xwax
 * ("serato_2a", "traktor_a", "mixvibes_v2"...). `NULL` = "serato_2a".
 * `sample_rate` en Hz. Devuelve NULL si el formato no existe o falta memoria. */
xf_timecoder *xf_timecoder_create(const char *def_name, unsigned int sample_rate);

/* NO RT-SAFE: libera. */
void xf_timecoder_destroy(xf_timecoder *tc);

/* RT-SAFE (una vez creado): alimenta `nframes` frames de PCM **estereo
 * intercalado de 16 bits** (L,R,L,R...). */
void xf_timecoder_submit(xf_timecoder *tc, const int16_t *pcm, size_t nframes);

/* RT-SAFE: velocidad relativa CON SIGNO. 1.0 = reproduccion normal hacia
 * delante, 0 = parado, negativo = hacia atras. */
double xf_timecoder_velocity(const xf_timecoder *tc);

/* RT-SAFE: posicion relativa acumulada (integral de la velocidad), en "vueltas
 * de referencia". Es relativa: arranca en 0 y se puede resetear. */
double xf_timecoder_position(const xf_timecoder *tc);

/* RT-SAFE (F.76, ADR-080) — posicion ABSOLUTA que trae el bitstream del
 * vinilo AHORA MISMO, en SEGUNDOS NOMINALES (la MISMA unidad que
 * `xf_timecoder_position()`, asi que se pueden restar directamente para medir
 * la deriva: el entero crudo de xwax ya viene dividido aqui por la
 * resolucion del formato, que varia por formato -- 1000 en "serato_2a",
 * 1300/2000 en otros -- para no obligar a quien llama a conocer esa
 * constante). No es una integral: no acumula error nunca, es una lectura
 * directa del disco. Devuelve -1.0 si el bitstream no esta enganchado (aguja
 * levantada, señal sucia, o los primeros ~VALID_BITS tras enganchar). `when`
 * (si no es NULL) se rellena con los segundos transcurridos desde la ULTIMA
 * lectura fiable -- crece mientras no llega una nueva, vuelve a ~0 en cuanto
 * llega. Uso previsto: medir (y, mas adelante, corregir) la deriva de
 * `xf_timecoder_position()`, que SI es una integral y SI puede acumular
 * sesgo. Esto NO cambia el modo relativo (ADR-004/005): el punto de arranque
 * del sample lo sigue decidiendo el usuario; esto solo mide cuanto ha girado
 * el disco de verdad, con una regla que no se puede torcer con el tiempo. */
double xf_timecoder_absolute_position(const xf_timecoder *tc, double *when);

/* RT-SAFE (F.76, ADR-080): true si el bitstream esta enganchado ahora mismo
 * (mismo criterio que usa `xf_timecoder_absolute_position` para no devolver
 * -1). Atajo para no tener que mirar el signo del entero. */
bool xf_timecoder_locked(const xf_timecoder *tc);

/* RT-SAFE: confianza de la lectura, 0..1. Cae a ~0 al levantar la aguja
 * (silencio) o con senal sucia. */
float xf_timecoder_confidence(const xf_timecoder *tc);

/* RT-SAFE: true si el disco va hacia delante. */
bool xf_timecoder_forwards(const xf_timecoder *tc);

/* NO RT-SAFE: hamster / reverse (ADR-008). Con `true`, se intercambian los
 * canales antes de decodificar, de modo que la velocidad sale con el signo
 * invertido. El autor corta en reverse. */
void xf_timecoder_set_reversed(xf_timecoder *tc, bool reversed);

/* NO RT-SAFE: pone la posicion acumulada a 0. */
void xf_timecoder_reset_position(xf_timecoder *tc);

/* Version del wrapper (para la prueba de humo del grafo de modulos). */
int xf_timecode_scaffolding_version(void);

#endif /* XF_TIMECODE_H */
