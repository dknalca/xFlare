# XFClock

**Capa 1 · sin dependencias · SEALED 2026-08-31 · `apiVersion = 1`**

El reloj musical de xFlare. Puro: sin UI, sin I/O, sin hardware. Convierte entre
tiempo musical (ticks, PPQ 480 — ADR-016) y tiempo real (ms, y el `hostTime` de
`mach_absolute_time` que comparten CoreAudio y CoreMIDI), y lleva el estado del
transporte (play / stop / loop / cuenta atrás).

## API pública

### `Tick` y `XFClock`

```swift
public typealias Tick = Int          // posición o distancia en tiempo musical
public enum XFClock {
    public static let ppq = 480      // pulsos por negra (ADR-016)
    public static let apiVersion = 1
}
```

`Tick` es con signo: una posición es ≥ 0, pero un desfase o la cuenta atrás son
negativos.

### `TimeSignature`

```swift
public struct TimeSignature: Equatable, Sendable {
    public let beatsPerBar: Int
    public let beatUnit: Int          // potencia de 2
    public init(beatsPerBar: Int, beatUnit: Int)
    public static let fourFour: TimeSignature
    public var ticksPerBeat: Tick     // negra = ppq, corchea = ppq/2, ...
    public var ticksPerBar: Tick
}
```

### `Tempo`

```swift
public struct Tempo: Equatable, Sendable {
    public let bpm: Double            // > 0
    public init(bpm: Double)
    public var millisecondsPerTick: Double
    public var ticksPerSecond: Double
    public func milliseconds(fromTicks: Tick) -> Double
    public func seconds(fromTicks: Tick) -> Double
    public func ticks(fromMilliseconds: Double) -> Tick   // redondea al tick más cercano
    public func ticks(fromSeconds: Double) -> Tick
}
```

`ticks(fromMilliseconds: milliseconds(fromTicks: t)) == t` para todo el rango de
trabajo (verificado con 10.000 valores y 6 tempos).

### `HostClock`

```swift
public struct HostClock: Equatable, Sendable {
    public let numer: UInt64
    public let denom: UInt64
    public init()                              // lee mach_timebase_info de esta máquina
    public init(numer: UInt64, denom: UInt64)  // determinista, para tests
    public static func now() -> UInt64         // mach_absolute_time()
    public func nanoseconds(fromHostTicks: UInt64) -> Double
    public func hostTicks(fromNanoseconds: Double) -> UInt64
}
```

`now()` es la única función de todo el módulo con efecto de "leer el mundo".

### `ClockMap`

```swift
public struct ClockMap: Equatable, Sendable {
    public let anchorHostTime: UInt64   // un instante del reloj del sistema...
    public let anchorTick: Tick         // ...equivalente a este tick
    public let tempo: Tempo
    public let host: HostClock
    public init(anchorHostTime: UInt64, anchorTick: Tick, tempo: Tempo, host: HostClock = HostClock())
    public static func startingNow(tempo: Tempo, host: HostClock = HostClock()) -> ClockMap
    public func tick(fromHostTime: UInt64) -> Tick
    public func hostTime(fromTick: Tick) -> UInt64
}
```

Ancla + tempo. Lo usa `XFAnalysis` (vía `Take.clock`) para llevar una captura
grabada a la rejilla del patrón. La ida y vuelta `tick(fromHostTime:)` ∘
`hostTime(fromTick:)` es exacta para todo el rango de trabajo. Ticks anteriores
al origen del reloj darían `hostTime` negativo y se saturan a 0 (no recuperable,
pero no ocurre en uso real: `anchorHostTime` es un `mach_absolute_time` grande).

### `Transport`

```swift
public struct Transport: Equatable, Sendable {
    public enum State { case stopped, countIn, playing }
    public struct Loop: Equatable, Sendable {
        public let start: Tick
        public let end: Tick            // end > start
        public init(start: Tick, end: Tick)
        public var length: Tick
    }
    public private(set) var state: State
    public private(set) var position: Tick   // < 0 en cuenta atrás
    public var timeSignature: TimeSignature
    public var loop: Loop?
    public init(timeSignature: TimeSignature = .fourFour)

    public mutating func stop()
    public mutating func play(countInBars: Int = 0)
    public mutating func advance(by delta: Tick)   // delta >= 0, lo llama el driver de audio

    public var isPlaying: Bool
    public var countInBarsRemaining: Int           // ceil; 0 si ya suena
    public var bar: Int                            // 1-based mientras suena, 0 si no
}
```

Es un **valor**, no un objeto con hilo. No mira ningún reloj: el driver de audio
calcula los ticks transcurridos según el reloj de AUDIO y llama a `advance(by:)`.
Así el transporte es determinista y la autopista no deriva respecto al sonido.

## Ejemplo de uso

```swift
import XFClock

// 1) Tiempo musical <-> ms
let tempo = Tempo(bpm: 168)
let ms = tempo.milliseconds(fromTicks: 480)     // una negra en ms
let back = tempo.ticks(fromMilliseconds: ms)    // 480

// 2) Alinear una captura con el patrón: el origen musical es el instante de start
let clock = ClockMap.startingNow(tempo: tempo)
let sampleTick = clock.tick(fromHostTime: someMotionSample.hostTime)

// 3) Transporte con dos compases de cuenta atrás y un loop de 4 compases
var transport = Transport()
transport.loop = Transport.Loop(start: 0, end: 4 * transport.timeSignature.ticksPerBar)
transport.play(countInBars: 2)
// cada bloque de audio:
let elapsedTicks = tempo.ticks(fromSeconds: Double(framesRendered) / sampleRate)
transport.advance(by: elapsedTicks)
if transport.isPlaying { /* dibujar la autopista en transport.position */ }
```

## Qué NO hace (a propósito)

- No arranca hilos ni temporizadores. El tiempo entra por `advance(by:)`.
- No conoce el patrón ni el sample. Solo tiempo.
- No hace tempo variable dentro de una toma (un `Tempo` por `ClockMap`). Si algún
  día hace falta, es un tipo nuevo, no un cambio incompatible aquí.

## Decisiones

- **ADR-016** — PPQ 480, el patrón en ticks, el BPM es parámetro de reproducción.
- **ADR-031** — contrato de redondeo tick↔hostTime y el transporte como valor que
  avanza el driver de audio.
