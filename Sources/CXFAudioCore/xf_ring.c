/* SPDX-License-Identifier: GPL-3.0-only */
#include "xf_ring.h"

#include <string.h>

/* Accesos atomicos con los builtins de Clang/GCC (sin <stdatomic.h>, ver el
 * comentario de portabilidad en xf_ring.h). El modelo de memoria es el mismo:
 * el productor publica `head` con RELEASE y el consumidor lo lee con ACQUIRE
 * (y simetrico para `tail`), de modo que los bytes escritos son visibles antes
 * de que el otro hilo vea el indice avanzado. */
#define LOAD_ACQ(p)      __atomic_load_n((p), __ATOMIC_ACQUIRE)
#define LOAD_RLX(p)      __atomic_load_n((p), __ATOMIC_RELAXED)
#define STORE_REL(p, v)  __atomic_store_n((p), (v), __ATOMIC_RELEASE)
#define STORE_RLX(p, v)  __atomic_store_n((p), (v), __ATOMIC_RELAXED)

/* true si x es potencia de 2 (y no 0). */
static bool is_pow2(size_t x) {
    return x != 0 && (x & (x - 1)) == 0;
}

/* NO RT-SAFE */
bool xf_ring_init(xf_ring_t *r, uint8_t *storage, size_t cap_pow2) {
    if (r == NULL || storage == NULL || !is_pow2(cap_pow2)) {
        return false;
    }
    r->buf = storage;
    r->cap = cap_pow2;
    r->mask = cap_pow2 - 1;
    STORE_RLX(&r->head, (uint64_t)0);
    STORE_RLX(&r->tail, (uint64_t)0);
    return true;
}

/* RT-SAFE */
size_t xf_ring_capacity(const xf_ring_t *r) {
    return r->cap;
}

/* RT-SAFE. Lo llama normalmente el consumidor: ve el `head` mas reciente del
 * productor (acquire) y su propio `tail`. */
size_t xf_ring_read_available(const xf_ring_t *r) {
    uint64_t head = LOAD_ACQ(&r->head);
    uint64_t tail = LOAD_RLX(&r->tail);
    return (size_t)(head - tail);
}

/* RT-SAFE. Lo llama normalmente el productor. */
size_t xf_ring_write_available(const xf_ring_t *r) {
    uint64_t tail = LOAD_ACQ(&r->tail);
    uint64_t head = LOAD_RLX(&r->head);
    return r->cap - (size_t)(head - tail);
}

/* RT-SAFE (productor). Copia en como mucho dos tramos (por si da la vuelta al
 * final del buffer). */
size_t xf_ring_write(xf_ring_t *r, const void *src, size_t n) {
    uint64_t head = LOAD_RLX(&r->head);
    uint64_t tail = LOAD_ACQ(&r->tail);
    size_t free_bytes = r->cap - (size_t)(head - tail);
    if (n > free_bytes) {
        n = free_bytes;
    }
    if (n == 0) {
        return 0;
    }

    size_t offset = (size_t)(head & r->mask);
    size_t first = r->cap - offset;      /* espacio hasta el final del buffer */
    if (first > n) {
        first = n;
    }
    memcpy(r->buf + offset, src, first);
    if (n > first) {
        memcpy(r->buf, (const uint8_t *)src + first, n - first);
    }

    STORE_REL(&r->head, head + (uint64_t)n);
    return n;
}

/* RT-SAFE (consumidor). Simetrico a write. */
size_t xf_ring_read(xf_ring_t *r, void *dst, size_t n) {
    uint64_t tail = LOAD_RLX(&r->tail);
    uint64_t head = LOAD_ACQ(&r->head);
    size_t avail = (size_t)(head - tail);
    if (n > avail) {
        n = avail;
    }
    if (n == 0) {
        return 0;
    }

    size_t offset = (size_t)(tail & r->mask);
    size_t first = r->cap - offset;
    if (first > n) {
        first = n;
    }
    memcpy(dst, r->buf + offset, first);
    if (n > first) {
        memcpy((uint8_t *)dst + first, r->buf, n - first);
    }

    STORE_REL(&r->tail, tail + (uint64_t)n);
    return n;
}

/* RT-SAFE (consumidor). Como read pero sin copiar. */
size_t xf_ring_skip(xf_ring_t *r, size_t n) {
    uint64_t tail = LOAD_RLX(&r->tail);
    uint64_t head = LOAD_ACQ(&r->head);
    size_t avail = (size_t)(head - tail);
    if (n > avail) {
        n = avail;
    }
    if (n == 0) {
        return 0;
    }
    STORE_REL(&r->tail, tail + (uint64_t)n);
    return n;
}

/* NO RT-SAFE */
void xf_ring_reset(xf_ring_t *r) {
    STORE_RLX(&r->head, (uint64_t)0);
    STORE_RLX(&r->tail, (uint64_t)0);
}
