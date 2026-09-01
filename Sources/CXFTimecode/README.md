# CXFTimecode

**Capa 0 · C · depende de CXFAudioCore · WIP (falta validar con vinilo real)**

Leer el vinilo de timecode. xwax vendorizado **intacto** + un wrapper propio en
**modo relativo** (ADR-004/005): sólo velocidad y dirección, nunca posición
absoluta de la aguja.

## Vendorizado (B5.1)

`vendor/xwax/` — `timecoder.{c,h}`, `lut.{c,h}`, `debug.h`, `pitch.h` de **xwax
1.10** (GPL-3.0, © Mark Hills). **No se toca ni una línea** (CLAUDE.md §8). Toda
adaptación va en `xf_timecode.c`.

## API pública (`xf_timecode.h`)

```c
typedef struct xf_timecoder xf_timecoder;   /* opaco */

xf_timecoder *xf_timecoder_create(const char *def_name, unsigned int sample_rate);
void          xf_timecoder_destroy(xf_timecoder *);

void   xf_timecoder_submit(xf_timecoder *, const int16_t *pcm, size_t nframes);  /* estéreo 16 bits */
double xf_timecoder_velocity(const xf_timecoder *);     /* con signo, 1.0 = normal */
double xf_timecoder_position(const xf_timecoder *);     /* relativa, integral de la velocidad */
float  xf_timecoder_confidence(const xf_timecoder *);   /* 0..1, cae al levantar la aguja */
bool   xf_timecoder_forwards(const xf_timecoder *);

void   xf_timecoder_set_reversed(xf_timecoder *, bool);  /* hamster / reverse (ADR-008) */
void   xf_timecoder_reset_position(xf_timecoder *);
```

`def_name`: formatos de xwax — `"serato_2a"` (por defecto), `"serato_2b"`,
`"serato_cd"`, `"traktor_a/b"`, `"mixvibes_v2"`, `"mixvibes_7inch"`,
`"pioneer_a/b"`.

- El **header público NO incluye `timecoder.h`** (arrastra las tripas de xwax y
  rompería `import CXFTimecode` desde Swift, como `<stdatomic.h>` en `xf_ring.h`).
  El tipo es opaco; las tripas viven en `xf_timecode.c`.
- La velocidad sale del filtro alfa-beta de xwax (`pitch_current`), alimentado por
  los cruces por cero de la portadora — **no hace falta enganchar el bitstream**
  (que es para la posición absoluta, que no usamos).
- `confidence` = presencia de señal (RMS de entrada, cae a 0 con silencio) o 1.0
  si xwax además ha enganchado el bitstream.
- Hamster: `set_reversed(true)` intercambia los canales antes de decodificar → la
  velocidad sale con el signo invertido.

## Verificación (B5)

- **B5.1** vendorizado, compila sin tocarlo (x86_64 + arm64). Hecho.
- **B5.2** wrapper modo relativo: la velocidad sigue la frecuencia de portadora
  (1000 Hz → ~1.0×, 1500 Hz → ~1.5×). Tests con señal de cuadratura sintética.
- **B5.3** hamster/reverse: señal de cuadratura invertida → dirección opuesta; el
  flag `reversed` invierte el signo.
- **B5.4** confianza y dropout: con señal, confianza alta; con silencio, cae por
  debajo de 0,2 y la velocidad decae — sin colgarse. Ruido blanco no engancha ni
  dispara la velocidad. `submit` con 0 frames no revienta.

7 tests.

## Pendiente (bloquea B5.5 / sellado)

Los tests usan **señales sintéticas** de cuadratura, que validan el modo relativo
contra el contrato de xwax. Antes de congelar el módulo hay que pasar **un vinilo
de timecode real** (Serato / Traktor) por un interface de audio y comprobar
enganche, escala de velocidad y recuperación de dropout con la aguja de verdad.
