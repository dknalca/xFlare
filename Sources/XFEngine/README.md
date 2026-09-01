# XFEngine

**Capa 1 · depende de XFNotation, XFCapture, XFAnalysis, XFPersistence, CXFAudioCore · SEALED 2026-09-01 · `apiVersion = 1`**

La máquina de estados de la sesión de gimnasio (`docs/CURRICULUM.md` §3). El único
módulo que orquesta a los demás de la capa 1. **No dibuja, no toca hardware, no
mira ningún reloj**: son `struct` valor que avanzan por eventos, como `Transport`
de XFClock. Determinista y testeable sin tiempo real; el scoring y esta lógica
corren fuera del hilo de audio (PLAN.md Hito E).

Todo lo relevante pasa por el facade **`Session`**. `SessionMachine`, `BPMLadder`
y `UnlockTracker` son públicos pero se usan sueltos solo en tests o casos raros.

## API pública

### `XFEngine`

```swift
public enum XFEngine {
    public static let apiVersion = 1
}
```

### `Session` — el facade

```swift
public struct Session: Equatable, Sendable {
    public init(config: SessionConfig = .standard, ladder: BPMLadder, unlock: UnlockTracker)

    // piezas (lectura)
    public private(set) var machine: SessionMachine
    public private(set) var ladder: BPMLadder
    public private(set) var unlock: UnlockTracker

    // consultas de conveniencia
    public var phase: SessionPhase        // == machine.phase
    public var currentBPM: Int            // == ladder.currentBPM
    public var isUnlocked: Bool           // == unlock.isUnlocked
    public var isFinished: Bool           // fase de resultados
    public var barsToUnlock: Int          // compases buenos que faltan
    public var summary: Summary?          // solo en resultados

    // eventos (los llama el driver de la sesión)
    public mutating func beginSeries()                       // calentamiento -> serie 0
    public mutating func recordBar(accuracy: Double) -> BarEvent
    public mutating func endRest()                           // descanso -> siguiente serie
    public mutating func recordBoss(accuracy: Double)        // toma del boss -> resultados
    public mutating func reset()                             // "otra vez"

    public enum BarEvent: Equatable, Sendable {
        case ignored                                          // no estábamos en una serie
        case barRecorded                                      // la serie continúa
        case seriesEnded(passed: Bool, bpmStep: BPMLadder.Step)
    }

    public struct Summary: Equatable, Sendable {
        public let seriesOutcomes: [Bool]
        public let finalBPM: Int
        public let bossAccuracy: Double
        public let unlocked: Bool
        public let bestStreak: Int
    }
}
```

**Una serie se aprueba si _todos_ sus compases llegan al umbral**
(`UnlockRule.accuracy`); un solo compás flojo la suspende (ADR-034: streak, no
media). El `minBPM` de la regla no interviene aquí, solo en el desbloqueo.

### `SessionMachine` — las fases

```swift
public struct SessionMachine: Equatable, Sendable {
    public init(config: SessionConfig = .standard)
    public let config: SessionConfig
    public private(set) var phase: SessionPhase
    public private(set) var seriesOutcomes: [Bool]

    public mutating func beginSeries()
    public mutating func completeSeries(passed: Bool)
    public mutating func endRest()
    public mutating func completeBoss()
    public mutating func reset()

    public var isScored: Bool             // series y boss puntúan; el resto no
    public var isFinished: Bool
    public var currentSeriesIndex: Int?
    public var completedSeriesCount: Int
}

public enum SessionPhase: Equatable, Sendable {
    case warmup
    case series(index: Int)
    case rest(afterSeries: Int)
    case boss
    case results
}

public struct SessionConfig: Equatable, Sendable {
    public init(seriesCount: Int = 3, barsPerSeries: Int = 4)
    public let seriesCount: Int
    public let barsPerSeries: Int
    public static let standard: SessionConfig
}
```

Orden: `warmup → series(0) → rest(0) → … → series(n-1) → boss → results`. El
descanso solo va **entre** series. Un evento llamado en una fase que no lo admite
es un no-op silencioso (como `Transport.advance` estando parado).

### `BPMLadder` — el peso de la barra

```swift
public struct BPMLadder: Equatable, Sendable {
    public init(rungs: [Int], startBPM: Int)   // rungs ascendentes; startBPM ∈ rungs
    public let rungs: [Int]
    public private(set) var index: Int

    public static let passesToStepUp = 3
    public static let failsToStepDown = 2

    public var currentBPM: Int
    public var isAtTop: Bool
    public var isAtBottom: Bool

    @discardableResult
    public mutating func record(passed: Bool) -> Step
    public mutating func reset()                // vuelve al startBPM

    public enum Step: Equatable, Sendable { case hold, up, down }
}
```

3 series aprobadas seguidas suben un escalón; 2 falladas seguidas bajan. Un
aprobado corta la racha de fallos y viceversa. En el techo/suelo no se mueve y el
contador se reinicia (no queda armado). `rungs` sale de `bpmLadder` en
`data/curriculum/exercises.json`.

### `UnlockRule` + `UnlockTracker` — el desbloqueo

```swift
public struct UnlockRule: Equatable, Sendable {
    public init(accuracy: Double, consecutiveBars: Int, minBPM: Int? = nil)
    public let accuracy: Double
    public let consecutiveBars: Int
    public let minBPM: Int?
}

public struct UnlockTracker: Equatable, Sendable {
    public init(rule: UnlockRule)
    public let rule: UnlockRule
    public private(set) var currentStreak: Int
    public private(set) var bestStreak: Int
    public private(set) var isUnlocked: Bool
    public var barsRemaining: Int

    @discardableResult
    public mutating func record(barAccuracy: Double, bpm: Int) -> Bool
    public mutating func reset()
}
```

Cuenta compases buenos **seguidos**, no de media: un compás por debajo del umbral
(o del `minBPM`, si lo hay) pone `currentStreak` a 0. `isUnlocked` se queda
pegado. `UnlockRule` cubre tanto el `pass` de un ejercicio (`exercises.json`, sin
BPM) como el `unlock` de un nivel (`levels.json`, con BPM).

## Ejemplo de uso

```swift
import XFEngine

// El ejercicio se lee de data/curriculum/. Aquí, a mano:
var session = Session(
    config: SessionConfig(seriesCount: 3, barsPerSeries: 4),
    ladder: BPMLadder(rungs: [60, 70, 80, 90, 100], startBPM: 70),
    unlock: UnlockTracker(rule: UnlockRule(accuracy: 0.8, consecutiveBars: 8))
)

// ... el usuario hace el calentamiento (no puntúa) ...
session.beginSeries()

// El driver de audio, al cerrar cada compás, pasa la precisión de XFAnalysis:
switch session.recordBar(accuracy: barAccuracy) {
case .barRecorded:
    break
case .seriesEnded(let passed, let step):
    // mostrar "serie superada / fallada"; step dice si cambió el BPM
    if step == .down { /* "bajamos a \(session.currentBPM) BPM" */ }
case .ignored:
    break
}

// Cuando acaba el descanso:
session.endRest()

// Tras la última serie, la fase es .boss:
if session.phase == .boss { session.recordBoss(accuracy: bossTakeAccuracy) }

// Pantalla de resultados:
if let s = session.summary {
    // s.finalBPM, s.unlocked, s.bestStreak, s.seriesOutcomes, s.bossAccuracy
}
```

## Qué NO hace (a propósito)

- No arranca hilos ni temporizadores. Todo entra por los eventos.
- No mide compases: el driver de audio cuenta con `XFClock` y llama a
  `recordBar` cuando toca.
- No elige el ejercicio de repaso (repetición espaciada) — eso necesita
  `XFPersistence` y llega después sin tocar este contrato.
- No conoce el modo ciego ni el calentamiento adaptativo (ADR-027). Aditivos.

## Decisiones

- **ADR-025** — 3 estrellas por criterios ortogonales (la filosofía "no por
  media" que hereda el aprobado de serie).
- **ADR-034** — el facade `Session`, y que una serie se aprueba por streak de
  compases limpios, no por media. `BPMLadder.reset()`.
