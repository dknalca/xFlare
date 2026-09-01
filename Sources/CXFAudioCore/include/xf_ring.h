/* SPDX-License-Identifier: GPL-3.0-only */
/*
 * xf_ring — ring buffer SPSC (un productor, un consumidor) lock-free, orientado
 * a bytes. Es el unico canal permitido entre el hilo de audio (productor) y el
 * resto de la app en Swift (consumidor), segun CLAUDE.md seccion 7.
 *
 * Contrato:
 *  - UN solo hilo escribe (produce) y UN solo hilo lee (consume). Con dos
 *    productores o dos consumidores esto NO es correcto.
 *  - El buffer de almacenamiento lo aporta quien inicializa: aqui no hay malloc.
 *  - La capacidad debe ser POTENCIA DE 2 (permite enmascarar en vez de dividir).
 *
 * Implementacion: `head` y `tail` son contadores de 64 bits que solo suben; la
 * diferencia `head - tail` es cuantos bytes hay sin leer. El indice real en el
 * buffer es el contador `& (cap - 1)`. Asi no hay ambiguedad "lleno vs vacio" y
 * el desbordamiento natural de los contadores es inofensivo.
 *
 * Nota de portabilidad: este header NO incluye <stdatomic.h> a proposito (no es
 * "module-safe" y romperia `import CXFAudioCore` desde Swift). Los accesos
 * atomicos a `head`/`tail` se hacen en el .c con los builtins `__atomic_*` de
 * Clang/GCC, que no necesitan cabecera.
 */
#ifndef XF_RING_H
#define XF_RING_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

typedef struct {
    uint8_t  *buf;    /* almacenamiento aportado por el llamante */
    size_t    cap;    /* potencia de 2 */
    size_t    mask;   /* cap - 1 */
    uint64_t  head;   /* indice de ESCRITURA. Lo mueve solo el productor (atomico en el .c). */
    uint64_t  tail;   /* indice de LECTURA.  Lo mueve solo el consumidor (atomico en el .c). */
} xf_ring_t;

/* NO RT-SAFE: llamar una vez en el arranque. `storage` debe tener al menos
 * `cap_pow2` bytes y vivir mientras viva el ring. Devuelve false si `cap_pow2`
 * es 0 o no es potencia de 2. */
bool xf_ring_init(xf_ring_t *r, uint8_t *storage, size_t cap_pow2);

/* RT-SAFE: capacidad total en bytes. */
size_t xf_ring_capacity(const xf_ring_t *r);

/* RT-SAFE: bytes disponibles para leer / para escribir en este instante.
 * Es una foto: el otro hilo puede cambiarlo justo despues. */
size_t xf_ring_read_available(const xf_ring_t *r);
size_t xf_ring_write_available(const xf_ring_t *r);

/* RT-SAFE (lado PRODUCTOR): copia hasta `n` bytes desde `src`. Devuelve cuantos
 * copio (puede ser < n si no cabe). Nunca pisa datos aun sin leer. */
size_t xf_ring_write(xf_ring_t *r, const void *src, size_t n);

/* RT-SAFE (lado CONSUMIDOR): extrae hasta `n` bytes a `dst`. Devuelve cuantos. */
size_t xf_ring_read(xf_ring_t *r, void *dst, size_t n);

/* RT-SAFE (lado CONSUMIDOR): descarta hasta `n` bytes sin copiarlos. */
size_t xf_ring_skip(xf_ring_t *r, size_t n);

/* NO RT-SAFE: vacia el ring. Solo cuando NADIE esta produciendo ni consumiendo. */
void xf_ring_reset(xf_ring_t *r);

#endif /* XF_RING_H */
