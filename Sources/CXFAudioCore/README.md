# CXFAudioCore

**Capa 0 · C · WIP (solo B4.1 hecho)**

El motor de audio en tiempo real. Reglas del hilo de audio en `CLAUDE.md` §7:
sin `malloc`/`free`, sin locks, sin Swift/ARC, sin Obj-C, sin ficheros, sin logs
dentro del callback. Cada funcion lleva `/* RT-SAFE */` o `/* NO RT-SAFE */`.

## Hecho: `xf_ring` — ring buffer SPSC lock-free (B4.1)

El unico canal permitido entre el hilo de audio (productor) y el resto de la app
en Swift (consumidor).

```c
#include "xf_ring.h"

typedef struct { /* opaco en la practica */ } xf_ring_t;

bool   xf_ring_init(xf_ring_t *r, uint8_t *storage, size_t cap_pow2);  /* NO RT-SAFE */
size_t xf_ring_capacity(const xf_ring_t *r);                           /* RT-SAFE */
size_t xf_ring_read_available(const xf_ring_t *r);                     /* RT-SAFE */
size_t xf_ring_write_available(const xf_ring_t *r);                    /* RT-SAFE */
size_t xf_ring_write(xf_ring_t *r, const void *src, size_t n);         /* RT-SAFE (productor) */
size_t xf_ring_read(xf_ring_t *r, void *dst, size_t n);               /* RT-SAFE (consumidor) */
size_t xf_ring_skip(xf_ring_t *r, size_t n);                          /* RT-SAFE (consumidor) */
void   xf_ring_reset(xf_ring_t *r);                                   /* NO RT-SAFE */
```

- **Un** productor y **un** consumidor. Con dos de cualquiera no es correcto.
- El almacenamiento lo aporta el llamante (sin `malloc`). Capacidad **potencia
  de 2**.
- `head`/`tail` son contadores de 64 bits que solo suben; `head - tail` = bytes
  sin leer; el indice real es `contador & (cap-1)`. Sin ambiguedad lleno/vacio.
- Atomicidad con los builtins `__atomic_*` de Clang/GCC (RELEASE al publicar el
  indice, ACQUIRE al leerlo). **No** se incluye `<stdatomic.h>` en el header
  porque no es "module-safe" y romperia `import CXFAudioCore` desde Swift.
- `write` nunca pisa datos sin leer; `read`/`write` copian en hasta dos tramos
  por si el dato da la vuelta al final del buffer.

Tests (`XFRingTests`): orden, no-pisado al llenar, vuelta al final del buffer,
reset, y **estres productor/consumidor en dos hilos** moviendo 1 MiB por un ring
de 1 KiB con verificacion byte a byte.

## Pendiente (necesita hardware / Instruments)

- **B4.2** callback CoreAudio RT-safe a 64 frames, con `thread_policy_set` +
  workgroup de audio.
- **B4.3** reproductor de sample con resampling por velocidad/direccion.
- **B4.4** metronomo en la salida principal (ADR-007).
- **B4.5** PUERTA DE CALIDAD: ≤10 ms, 0 overloads en 5 min (medido con Instruments).
- **B4.6** SELLAR.

El spike desechable `spike/b1-latency/` ya prueba el passthrough a 64 frames en
crudo; B4.2 es la version "para quedarse".
