# Arquitectura de xFlare

> Como esta partido el codigo y por que un modulo terminado no se rompe cuando
> empiezas el siguiente. Estado: v0.2.

## 1. El problema que este documento resuelve

El fallo clasico: todo vive en pocos ficheros grandes, las dependencias son
implicitas, y tocar el reproductor rompe el scoring. La disciplina no basta —
a las tres semanas se te olvida. Hay que hacer que **romper un modulo sellado sea
un error de compilacion o un test en rojo**, no un descubrimiento a los diez dias.

Cuatro mecanismos, en orden de dureza:

| # | Mecanismo | Que impide | Quien lo vigila |
|---|---|---|---|
| 1 | **Un target SPM por modulo** | Que un modulo lea las tripas de otro | El compilador |
| 2 | **Grafo de dependencias en capas, sin ciclos** | Que la UI se cuele en el hilo de audio | El compilador |
| 3 | **Protocolos en las fronteras** | Que el analisis dependa del hardware | El compilador |
| 4 | **Tests sellados + fixtures reales** | Regresiones silenciosas | `make verify` |

El nº1 es el importante. En Swift, si `XFAnalysis` no declara a `XFCapture` como
dependencia, **no puede importarlo**. Punto. No es una convencion, es imposible.

## 2. Mapa de modulos

```
CAPA 3  UI          XFApp
                       |
CAPA 2  Presentacion   +-- XFRender ----+-- XFDesign
                       |
CAPA 1  Dominio     XFEngine
                    /    |    \
           XFAnalysis XFCapture XFPersistence   XFProfiles
              |  \    /  |  \    /
              |   XFNotation   XFPrimitives
              |       |       /
              +----- XFClock /
                         |  /
CAPA 0  Tiempo real  CXFTimecode --- CXFAudioCore      (C)
                     XFPrimitives (Swift, value types compartidos)
```

> Los dos módulos C llevan prefijo `C` (`CXFAudioCore`, `CXFTimecode`), que es la
> convención de SwiftPM para targets en C y el nombre real en `Package.swift`.
> `XFPrimitives` está en el fondo del grafo (Swift, sin dependencias): son los
> `struct` de muestra que `XFCapture` produce y `XFAnalysis` consume, para que no
> tengan que importarse entre sí (ADR-033). No es código de tiempo real.

**Regla de oro: las flechas solo bajan.** Nunca hay un `import` hacia arriba ni
lateral entre hermanos. Si dos modulos de la misma capa se necesitan, o falta un
modulo mas abajo, o el diseno esta mal.

| Modulo | Lenguaje | Responsabilidad | Depende de | Prohibido |
|---|---|---|---|---|
| `CXFAudioCore` | C | Ring buffer SPSC, callback CoreAudio, primitivas RT-safe | — | malloc, locks, Obj-C, logs |
| `CXFTimecode` | C | xwax vendorizado + wrapper `xf_timecode` en modo relativo | CXFAudioCore | tocar los .c de xwax |
| `XFPrimitives` | Swift | `MotionSample` / `FaderSample`: value types de muestra compartidos | — | lógica, I/O, hardware |
| `XFClock` | Swift | Reloj musical: ticks, PPQ 480, transporte, conversion tick↔ms↔host time | — | UI, I/O |
| `XFNotation` | Swift | Modelo XFN, compositor mano×fader, carga de la libreria | XFClock | hardware, UI, red |
| `XFProfiles` | Swift | Parsear y resolver los `.conf` de mesa. Herencia, validacion, autodeteccion | — | hardware, UI |
| `XFCapture` | Swift | Fuentes de entrada: timecode, MIDI, teclado, replay. Binarizacion del fader | XFClock, CXFTimecode, XFProfiles | analisis, UI |
| `XFAnalysis` | Swift | DTW, emparejado de clicks, scoring, diagnostico. **Funciones puras** | XFNotation, XFClock | hardware, UI, disco |
| `XFPersistence` | Swift | GRDB: sesiones, progreso, repeticion espaciada, ajustes | XFNotation | UI, hardware |
| `XFEngine` | Swift | Maquina de estados de la sesion. El unico que orquesta | todos los de capa 1 | dibujar |
| `XFDesign` | Swift | Tokens de diseno y componentes SwiftUI reutilizables | — | logica de negocio |
| `XFRender` | Swift | Escena SpriteKit: autopista, scope, fantasma. Dibuja un ViewModel y ya | XFDesign, XFNotation | leer hardware o BD |
| `XFApp` | Swift | Pantallas SwiftUI, navegacion, ciclo de vida | todos | logica que deba testearse |
| `XFTestKit` | Swift | Fixtures, fuentes falsas, helpers de golden tests | XFCapture, XFNotation | entrar en el binario final |

## 3. Los contratos de frontera

Aqui esta el truco que permite desarrollar el 70% del proyecto **sin la mesa
conectada** y tener tests deterministas.

```swift
// XFCapture — la app nunca habla con hardware, habla con esto.
// NB: MotionSample y FaderSample viven en XFPrimitives (capa 0), no aqui, para
// que XFAnalysis pueda consumirlos sin importar XFCapture (ADR-033).

public struct MotionSample: Sendable {      // en XFPrimitives
    public let hostTime: UInt64   // mach_absolute_time
    public let position: Double   // vueltas acumuladas, signo = direccion
    public let velocity: Double   // 1.0 = 33 1/3 rpm nominal
    public let confidence: Float  // 0..1, calidad del timecode
}

public protocol MotionSource: AnyObject {
    var isConnected: Bool { get }
    func start() throws
    func stop()
    func latest() -> MotionSample?
}

public struct FaderSample: Sendable {        // en XFPrimitives
    public let hostTime: UInt64
    public let value: Float       // 0..1 crudo
    public let isOpen: Bool       // binarizado con el cut-in calibrado
}

public protocol FaderSource: AnyObject {
    var isConnected: Bool { get }
    func start() throws
    func stop()
    func latest() -> FaderSample?
}
```

Implementaciones intercambiables:

| Fuente | Para que |
|---|---|
| `TimecodeMotionSource` | Lo real: vinilo timecode via CXFTimecode |
| `MidiJogMotionSource` | Controlador con jog wheel |
| `KeyboardMotionSource` | Modo sin mesa: flechas del teclado. Cualquiera prueba la app |
| `ReplayMotionSource` | **Reproduce una sesion grabada.** La base de los tests |
| `MidiFaderSource` / `AudioEnvelopeFaderSource` / `KeyboardFaderSource` / `ReplayFaderSource` | Idem para el fader |

Y el analisis es una funcion pura, sin estado ni hardware:

```swift
// XFAnalysis
public struct Take {
    public let motion: [MotionSample]
    public let fader: [FaderSample]
    public let clock: ClockMap        // como mapear hostTime a ticks
}

public protocol Scorer {
    func score(_ take: Take, against target: Scratch) -> Report
}

public struct Report {
    public let accuracy: Double            // 0..1
    public let clickOffsets: [ClickOffset] // desfase con signo, en ms
    public let pitchDistance: Double       // DTW normalizado
    public let consistency: Double         // 1 - sigma normalizada
    public let diagnostics: [Diagnostic]   // frases accionables para el usuario
}
```

Un `Report` se calcula igual si la entrada viene de la Rane o de un fichero. Eso
significa que **el scoring se puede desarrollar en el tren**.

## 4. Grabacion y replay de sesiones

Formato `.xfsession`: un JSON Lines con las muestras crudas de motion y fader mas
metadatos de calibracion. Es la pieza que mas rentabiliza el esfuerzo:

- Grabas una vez una toma buena y una mala de cada patron.
- Los tests de `XFAnalysis` corren contra esas tomas. Si cambias el scoring y una
  toma buena deja de puntuar bien, el test se pone rojo.
- Puedes depurar un fallo raro reproduciendolo cuantas veces quieras.
- Y sirve de funcionalidad de usuario: revisar tu toma.

## 4.5 Restricciones de plataforma

Minimo **macOS 11.0**, universal Intel + Apple Silicon, toolchain **Xcode 14.2 /
Swift 5.7.2**. Detalle y lista de APIs prohibidas en `docs/PLATFORM_SUPPORT.md`.

Dos consecuencias que afectan al diseno de modulos:

- `XFCapture` usa la **API clasica de CoreMIDI** (`MIDIPacketList`), envuelta tras
  el protocolo `FaderSource`. El dia que suba el minimo, solo cambia una
  implementacion y nadie mas se entera.
- `CXFAudioCore` no puede depender de los audio workgroups (macOS 11+) como unica
  via de prioridad. Se fija con `thread_policy_set` /
  `THREAD_TIME_CONSTRAINT_POLICY`, que funciona en todas las maquinas objetivo.

## 5. Reglas del hilo de audio (no negociables)

Dentro del callback de CoreAudio **nunca**: `malloc`/`free`, locks, Swift con ARC,
Obj-C, ficheros, logs, `print`. Solo C, buffers preasignados y atomicas.

La comunicacion RT↔UI es en un solo sentido y sin bloqueo: el callback escribe en
un ring buffer SPSC y publica un snapshot con atomicas; Swift lo lee cuando quiere.
Ningun modulo Swift llama nunca hacia dentro del callback.

## 6. Protocolo de sellado

Un modulo pasa a **SEALED** cuando cumple las cinco:

1. Sus tests pasan y cubren su API publica.
2. Tiene `Sources/XFxxx/README.md` con la API publica y un ejemplo de uso.
3. Todo lo que no es API publica es `internal`. Si es `public`, es contrato.
4. Esta anotado en `docs/MODULE_STATUS.md` con fecha y version.
5. `make verify` esta en verde entero.

Y una vez sellado:

- **No se toca.** Si necesitas algo nuevo, lo *anades* sin romper lo que hay.
- **Sus tests son inmutables.** Esto es lo que hace real el sellado: si puedes
  editar el test para que pase, no has sellado nada.
- Para un cambio incompatible hace falta **un ADR nuevo** que lo justifique,
  re-sellado, y que todos los dependientes sigan en verde.

```
make verify   # compila + tests de todos los modulos + goldens + lint
make seal M=XFClock   # comprueba las 5 condiciones y actualiza MODULE_STATUS.md
```

## 7. Estructura de carpetas

```
xFlare/
├── Package.swift              # define los targets y el grafo de dependencias
├── Sources/
│   ├── CXFAudioCore/          # C: include/ + src/
│   ├── CXFTimecode/           # C: xwax vendorizado en vendor/xwax/ INTACTO
│   ├── XFClock/
│   ├── XFNotation/
│   ├── XFCapture/
│   ├── XFAnalysis/
│   ├── XFPersistence/
│   ├── XFEngine/
│   ├── XFDesign/
│   ├── XFRender/
│   ├── XFTestKit/
│   └── XFApp/
├── Tests/                     # un target de tests por modulo, mismo nombre + Tests
├── Fixtures/
│   ├── sessions/              # .xfsession grabados
│   └── golden/                # SVG/PNG de referencia del renderizador
├── App/                       # proyecto Xcode fino que solo empaqueta XFApp
├── data/  docs/  tools/  preview/
└── Makefile
```

El proyecto Xcode es **una cascara**. Toda la logica vive en paquetes SPM que se
compilan y testean desde terminal. Asi Claude Code puede trabajar sin abrir Xcode.

## 8. Como trabaja Claude Code con esto

Al empezar cualquier tarea:

1. Mirar `TODO.md` — coger **la primera tarea no hecha del bloque activo**.
2. Comprobar en `docs/MODULE_STATUS.md` que modulos estan SEALED.
3. Trabajar **solo dentro del modulo de esa tarea**. Si hace falta tocar otro,
   parar y preguntar.
4. `make verify` antes de dar nada por terminado.
5. Marcar la tarea en `TODO.md` y `data/backlog.json`.
