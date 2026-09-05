# CXFTimecode

**Capa 0 · C · depende de CXFAudioCore · SEALED (2026-09-04)**

Leer el vinilo de timecode. xwax vendorizado **intacto** + un wrapper propio en
**modo relativo** (ADR-004/005): el punto de arranque del sample lo decide
siempre el usuario, nunca la posición de la aguja. F.76 (ADR-080) expone
además la posición ABSOLUTA que trae el bitstream — no para pilotar el
sample (eso seguiría siendo modo absoluto), sino como regla de medir sin
acumular error cuánto se ha movido el disco de verdad, y así diagnosticar
(y más adelante corregir) la deriva de la posición relativa integrada.

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

/* F.76 (ADR-080) — diagnóstico de deriva, no forma parte del "modo relativo"
 * de arriba: posición ABSOLUTA del bitstream ahora mismo, en las MISMAS
 * unidades (segundos nominales) que xf_timecoder_position(), para poder
 * restarlas y medir cuánto se ha separado la integral del disco real. */
double xf_timecoder_absolute_position(const xf_timecoder *, double *when);  /* -1.0 si no engancha */
bool   xf_timecoder_locked(const xf_timecoder *);
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

- **F.76 (ADR-080)** posición absoluta del bitstream, para medir (y más
  adelante corregir) la deriva de la posición relativa integrada — ver
  `docs/TIMECODE_DRIFT.md`. Con la cuadratura sintética de esta suite (sin
  el LFSR real) nunca debe darse por enganchada; 2 tests nuevos lo
  confirman.

9 tests.

- **B5.5** validado con vinilo Serato CV02 **real** sobre la Rane 72
  (`spike/b5-timecode/tcprobe`, no señal sintética): 60 s a 33⅓ estable → `vel`
  media 0.9999 (min 0.9967, max 1.0033), `conf` sostenida 0.92–1.00, enganche
  de bitstream. Dirección: el scratch invierte el signo de `vel` en sincronía
  con `dir`, sin perder confianza. Dropout: al levantar la aguja, `conf` decae
  suavemente a 0 en ~1,5 s y `vel` cae a 0, `position` se congela sin
  corromperse ni colgar el proceso. `drops` = 0, `render_err` = 0 en las tres
  corridas. Detalle completo, incluida la búsqueda del canal correcto (el
  perfil asumía uno equivocado), en `docs/TIMECODE.md` §3.

## Nota para quien reutilice el spike en otro sitio

El vinilo real llegó por el canal de entrada **"Analog 1"** de la Rane 72, no
por el canal que la propia mesa etiqueta **"Deck 1"** en CoreAudio — esa
etiqueta resultó no llevar la señal real (solo daba un pico aislado de
confianza). Si otra mesa se comporta igual, no confíes en el nombre de canal
que reporta el driver: compara contra el medidor de la mesa y prueba varios
pares. `spike/b5-timecode/tcprobe --ch N` deja elegir qué par probar sin
recompilar.
