# CXFAudioCore

**Capa 0 · C · WIP (B4.1 ring + B4.2 motor/host + B4.3 reproductor + B4.4 metronomo; falta B4.5 puerta de latencia en hardware)**

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

## Hecho: `xf_metronome` — claqueta en la salida principal (B4.4)

Se **mezcla en la salida principal**, no en un canal aparte (ADR-007). No lleva
el tiempo: el callback le pasa por bloque la posicion musical de inicio (ticks) y
el BPM.

```c
#include "xf_metronome.h"

xf_metronome *xf_metronome_create(unsigned int sr);                  /* NO RT-SAFE */
void xf_metronome_destroy(xf_metronome *m);
void xf_metronome_set_enabled(xf_metronome *m, bool on);             /* RT-SAFE (atomica) — el unico control */
bool xf_metronome_enabled(const xf_metronome *m);
void xf_metronome_set_level(xf_metronome *m, float level);
void xf_metronome_set_time_signature(xf_metronome *m, int beats_per_bar, int ppq);
void xf_metronome_render(xf_metronome *m, float *out, int n, double tick0, double bpm); /* RT-SAFE, SUMA a out */
void xf_metronome_resync(xf_metronome *m, double tick);             /* NO RT-SAFE */
```

- Un click al cruzar cada negra; el **primer tiempo del compas va acentuado**
  (1600 Hz vs 1000 Hz). Click = seno con ataque de 1,5 ms y caida exponencial
  (~60 ms), sintetizado sin reservas.
- **Se suma** a `out` (el mixer de B4.2 hace player -> out y luego el metronomo
  suma). Con ticks negativos suena tambien -> la claqueta de la cuenta atras del
  transporte sale gratis.
- Activar/desactivar es un solo control atomico; al reactivar **no suelta una
  rafaga** (deja morir el click en curso, no acumula los perdidos).
- `resync(tick)` no re-dispara el tiempo en curso; un salto que cambia el numero
  de tiempo (loop del transporte hacia atras) si dispara.

Tests (`XFMetronomeTests`): 1 click/negra y su espaciado, acento del 1er tiempo
(Goertzel 1600 vs 1000), silencio absoluto si esta desactivado, mezcla que
**suma** (fuera del click `out == preset`), cuenta atras con ticks negativos,
el BPM cambia el espaciado, resync, salto hacia atras.

## Hecho: `xf_engine` — el motor RT + host CoreAudio (B4.2)

Une el ring buffer (B4.1), el reproductor (B4.3) y el metronomo (B4.4) y los
conecta a una AudioUnit HAL duplex a 64 frames. Dos partes:

**Nucleo RT (`xf_engine_render`, testeable sin hardware):** dado un bloque de
entrada del dispositivo (float no intercalado) produce la salida y mete la
entrada en el ring como **estereo int16** para que Swift la drene (timecode,
fader). Sintetiza la salida con `xf_player` + `xf_metronome`, aplica la ganancia
de master y satura. Avanza el reloj musical y publica el **tick del inicio del
bloque** (`xf_engine_tick`), que la autopista lee para ir con el reloj de AUDIO.
No reserva memoria (regla §7); habla con Swift solo por atomicas y el ring.

```c
xf_engine *xf_engine_create(double sr, uint32_t max_frames);      /* NO RT-SAFE */
void xf_engine_load_sample(xf_engine *, const float *mono, int64_t frames);
void xf_engine_set_transport(xf_engine *, double bpm, int ppq, bool playing);
void xf_engine_seek_tick(xf_engine *, double tick);
void xf_engine_set_velocity(xf_engine *, double v);
void xf_engine_set_master_gain(xf_engine *, float g);
xf_ring_t    *xf_engine_input_ring(xf_engine *);   /* Swift drena PCM int16 estereo */
xf_metronome *xf_engine_metronome(xf_engine *);
double        xf_engine_tick(const xf_engine *);   /* RT-SAFE */
void xf_engine_render(xf_engine *, const float *inL, const float *inR,
                      float *outL, float *outR, int n, uint64_t host_time); /* RT-SAFE */
```

Cambiar el sample **sonando** es seguro: el puntero al reproductor es atomico y
el anterior se retira sin `free` en el hilo RT.

**Host CoreAudio (`xf_engine_start`/`xf_engine_stop`, compila; SIN tests):** abre
la AudioUnit HAL sobre el dispositivo, fija 64 frames, instala el callback, y en
el primer callback promociona el hilo (`xf_rt_promote_current_thread` →
`THREAD_TIME_CONSTRAINT_POLICY`) y lo une al workgroup del dispositivo
(`kAudioDevicePropertyIOThreadOSWorkgroup` → `os_workgroup_join`, obligatorio en
Apple Silicon). Cuenta overloads (`kAudioDeviceProcessorOverload`) y render
errors.

`xf_rt` (`xf_rt.h`): `xf_rt_time_constraint_params(sr, frames, &period, &comp,
&constraint)` calcula la politica (testeable) y `xf_rt_promote_current_thread`
la aplica.

Tests (`XFEngineRTTests`, `xf_rt` + `xf_engine_render`): la entrada va al ring
como int16 estereo, sin entrada no escribe pero saca salida, `nframes` se satura
a `max_frames`, el reproductor suena, gain 0 silencia, el metronomo se mezcla, el
reloj musical avanza solo sonando y publica el tick del inicio del bloque, seek,
cambio de sample sonando. Los parametros de time-constraint: `computation <=
period`, `constraint` entre medias, escala con el buffer.

## Pendiente (necesita hardware / Instruments)

- **B4.5** PUERTA DE CALIDAD: ≤10 ms round-trip, 0 overloads en 5 min, verificar
  con Instruments (Audio System Trace) que `xf_engine_render` no hace malloc/lock.
- **B4.6** SELLAR.

El spike desechable `spike/b1-latency/` ya prueba el passthrough a 64 frames en
crudo; B4.2 es la version "para quedarse".
