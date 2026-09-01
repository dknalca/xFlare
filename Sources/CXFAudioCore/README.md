# CXFAudioCore

**Capa 0 · C · WIP (B4.1 ring buffer + B4.3 reproductor con resampling hechos)**

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

## Hecho: `xf_player` — reproductor con resampling antialiasing (B4.3)

El "plato": un cabezal fraccionario que lee un sample **mono** a la velocidad del
disco (1.0 = normal, negativo = hacia atras).

```c
#include "xf_player.h"

typedef struct xf_player xf_player;   /* opaco */

xf_player *xf_player_create(const float *sample, int64_t frames, unsigned int sr); /* NO RT-SAFE */
void   xf_player_destroy(xf_player *p);                                            /* NO RT-SAFE */
void   xf_player_render(xf_player *p, float *out, int nframes, double target_v);   /* RT-SAFE */
double xf_player_playhead(const xf_player *p);                                     /* RT-SAFE */
void   xf_player_set_playhead(xf_player *p, double frame);
double xf_player_velocity(const xf_player *p);                                     /* RT-SAFE */
void   xf_player_set_glide_ms(xf_player *p, double ms);                            /* NO RT-SAFE */
```

- **Antialiasing:** lectura con **sinc enventanado** (32 taps, Blackman-Harris,
  512 fases) cuyo corte baja al subir la velocidad. Tabla precalculada en
  `create` (NO RT-SAFE); el `render` no reserva nada. Leer mas rapido que el
  sample (`|v| > 1`) submuestrea la fuente; sin bajar el corte apareceria alias.
- **Suavizado de velocidad** (`glide_ms`, 5 ms por defecto) para no meter clicks
  al cambiarla de golpe. El cabezal se satura a los extremos (no hace loop).
- Solo resamplea: el corte de fader, el metronomo y la mezcla a estereo van
  aguas abajo (B4.2 / B4.4).

Tests (`XFPlayerTests`): el foco es **medir** que no hay aliasing, no confiar en
el oido. v=1 casi transparente (misma amplitud del tono, < 0,5 dB); v=2 duplica
el pitch y borra el fundamental; **20 kHz a 2x -> salida casi en silencio**
(RMS < 0,03) en vez de plegarse a 8 kHz; 15 kHz a 3x sin alias en 3 kHz; reverso,
parada, ganancia DC unidad, sin discontinuidad entre bloques, glide de velocidad.

## Pendiente (necesita hardware / Instruments)

- **B4.2** callback CoreAudio RT-safe a 64 frames, con `thread_policy_set` +
  workgroup de audio.
- **B4.4** metronomo en la salida principal (ADR-007).
- **B4.5** PUERTA DE CALIDAD: ≤10 ms, 0 overloads en 5 min (medido con Instruments).
- **B4.6** SELLAR.

El spike desechable `spike/b1-latency/` ya prueba el passthrough a 64 frames en
crudo; B4.2 es la version "para quedarse".
