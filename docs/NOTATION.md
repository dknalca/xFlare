# XFN — xFlare Notation

> Especificacion de como xFlare representa, almacena y dibuja un scratch.
> Estado: v0.1 · El modelo se implementa en el bloque B3 (`XFNotation`); el modo
> fantasma que lo usa, en el Hito E de `PLAN.md`.

## 1. Por que una notacion propia

TTM (Turntablist Transcription Methodology) y la *Periodic Matrix of Skratches* son
la mejor convencion visual que existe para leer scratches: eje X tiempo, eje Y posicion
del disco, y marcas sobre la curva para el fader. xFlare **adopta esa gramatica visual**
porque es la que el DJ ya sabe leer.

Lo que **no** hacemos: copiar el poster, sus celdas, su arte o su nomenclatura registrada.
XFN es un formato propio, generativo y legible por maquina. Ver `docs/MATRIX_MAPPING.md`
para la parte legal y de atribucion.

## 2. Modelo de datos

Un scratch son **dos carriles sincronizados** sobre una rejilla de tiempo musical:

| Carril | Que describe | Se mide con |
|---|---|---|
| `record` | El movimiento del disco (la mano) | Timecode → posicion y velocidad |
| `faderEvents` | El estado del crossfader (los cortes) | MIDI o envolvente de audio |

### 2.1 Tiempo

Todo en **ticks**, con `PPQ = 480` (480 ticks por negra, convencion MIDI). Nunca en
segundos: el tempo es un parametro de reproduccion, no del patron. Conversion:

    ms = ticks * (60000 / bpm) / 480

### 2.2 Carril de disco (`record`)

Lista de **fases**. Cada fase es un tramo de movimiento continuo:

```json
{ "t": 0, "dur": 240, "dir": "fwd", "dist": 1.0,
  "curve": "bell", "from": 0.0, "to": 1.0 }
```

- `dir` — `fwd` (adelante), `rev` (atras), `hold` (disco parado).
- `dist` — recorrido en *unidades de patron* (adimensional; se escala al calibrar
  con el sample real). **La suma de `dist` de un ciclo debe ser 0**, o el patron
  no cierra y deriva.
- `curve` — perfil de velocidad dentro de la fase. La pendiente es el tono:

  | curva | forma | como suena |
  |---|---|---|
  | `lin` | velocidad constante | tono plano |
  | `bell` | lento-rapido-lento (`3u²-2u³`) | el gesto natural de muneca |
  | `acc` | acelera (`u²`) | el tono sube |
  | `dec` | frena (`1-(1-u)²`) | el tono baja |
  | `hold` | sin movimiento | silencio / parada del tear |

### 2.3 Carril de fader (`faderEvents`)

Lista de **cambios de estado**, no de estados por muestra:

```json
[{ "t": 0, "state": "open" }, { "t": 134, "state": "closed" }, { "t": 173, "state": "open" }]
```

Un **click** es un `closed` seguido de un `open` en ventana corta: el silencio breve
que parte un sonido continuo. `clickCount` cuenta las transiciones a `closed`.

Nota de implementacion: el crossfader real es analogico. En la captura se binariza
con la **curva de corte calibrada** (el *cut-in point* que se mide en el Hito D),
con histeresis para no generar eventos fantasma.

## 3. Composicionalidad — la idea central

La leccion de la Periodic Matrix es que un scratch **no es una entidad atomica**,
es un producto cartesiano:

```
scratch = patron_de_mano  ×  patron_de_fader  ×  subdivision  ×  ciclos
```

Por eso xFlare **no guarda 900 scratches dibujados a mano**: guarda ~10 patrones de
mano y ~16 patrones de fader, y los multiplica. Anadir un patron de fader anade
decenas de scratches nuevos gratis.

```
baby      × open         × 1/8  = Baby Scratch
baby      × flare_2c     × 1/8  = 2-Click Flare
tear2     × flare_1c     × 1/8  = Tear Flare
drag      × transformer_4× 1/4  = Transformer x4
```

Los patrones de fader se definen en **fracciones de la fase** (0.0 a 1.0), no en
ticks absolutos. Asi el mismo flare de 2 clicks funciona igual a 1/8 que a 1/16.

Ficheros: `data/primitives/hand_patterns.json`, `data/primitives/fader_patterns.json`,
catalogo en `tools/catalog.json`, salida compilada en `data/scratches/library-v0.1.json`.

## 4. Grafismo

Convenio de dibujo (implementado en `xfn_core.render`, a portar a SpriteKit):

- **Curva negra continua** = posicion del disco. Subir = adelante, bajar = atras.
  La pendiente es el tono; una recta es tono constante.
- **Circulo hueco (○)** sobre la curva = el fader **ABRE** (entra sonido).
- **Circulo relleno (●)** sobre la curva = el fader **CIERRA** (click / corte).
- **Banda inferior** = estado del fader en el tiempo. Negro = abierto, gris = cerrado.
- **Rejilla vertical**: linea gris fuerte en cada negra, fina en cada 1/16.

En la app hay tres capas superpuestas:

| Capa | Contenido | Color |
|---|---|---|
| Fantasma | El patron objetivo | Gris translucido |
| Usuario | Lo que estas tocando de verdad | Color de acento |
| Delta | Zonas fuera de tolerancia | Rojo/ambar |

## 5. Evaluacion

- **Contorno de tono**: DTW (ADR-005, afinacion relativa) entre curva objetivo y
  curva del usuario. Lo que importa es la forma, no la posicion absoluta del disco.
- **Clicks**: emparejamiento 1:1 objetivo↔usuario por proximidad temporal, y despues
  desfase con signo en ms. Ventanas: ±20 perfecto, ±40 muy bien, ±70 bien, ±110 tarde.
- **Regularidad**: desviacion tipica del desfase. Un DJ que va 30 ms tarde *siempre*
  es mejor que uno que oscila ±30 ms — el primero solo tiene que adelantar la mano.

Todo el scoring corre **fuera del hilo de audio** (ADR de RT-safety).

## 6. Pendiente para v0.2

- Notacion de **dos platos** (juggling, chasing) — hoy solo hay un carril de disco.
- **Bancos de sample** y trigger de pads.
- Curvas de fader no binarias (fades, blends).
- Import/export a formatos de la comunidad si aparece alguno abierto.
