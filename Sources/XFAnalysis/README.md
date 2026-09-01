# XFAnalysis

**Capa 1 · depende de XFPrimitives, XFNotation, XFClock · WIP (no sellado)**

El cerebro del gym: puntúa una toma contra un patrón y devuelve un **diagnóstico
accionable** (ADR-018), no sólo un número. Funciones puras — un `Report` se
calcula igual venga la entrada de la mesa o de un `.xfsession`, así que el
scoring se desarrolla y se prueba sin hardware.

## API pública

```swift
public struct Take: Sendable {                 // la entrada
    let motion: [MotionSample]; let fader: [FaderSample]; let clock: ClockMap
}

public protocol Scorer {
    func score(_ take: Take, against scratch: Scratch, atTargetBpm: Bool) -> Report
}
public struct DefaultScorer: Scorer { init() }

public struct Report: Equatable, Sendable {
    let score, maxScore: Int
    var accuracy: Double                        // score / maxScore
    let clickOffsets: [ClickOffset]             // desfase con signo por click
    let pitchDistance: Double                   // DTW normalizado del contorno
    let sigmaMs, biasMs: Double                 // dispersión y sesgo del timing
    let amplitudeError: Double
    let missedClicks: Int
    let finished: Bool
    let stars: Int                              // 0..3, criterios ortogonales
    let starReasons: [String]                   // qué falta para la siguiente
    let diagnostics: [Diagnostic]
}

public struct ClickOffset { let targetTick; let userHostTime: UInt64?; let offsetMs: Double?; let score: Int; var isMissed }
public struct Diagnostic { enum Kind { timingBias, timingSpread, missedClicks, amplitude, pitchContour, good }; let kind; let text }
public enum DTW { static func normalizedDistance(_:_:band:) -> Double }
public enum ScoringConstants { /* tablas de SCORING.md */ }
```

## Cómo puntúa (SCORING.md §1)

- **click** — cada cierre de fader del patrón se empareja con el más cercano del
  usuario dentro de ±150 ms; fuera de eso = perdido. Puntos por `|desfase|`:
  ±20→100, ±40→75, ±70→50, ±110→25, fuera→0.
- **pitch** — un punto de control por semicorchea. Contorno de **velocidad**
  (= tono), normalizado por su máximo (afinación relativa, ADR-005), comparado
  con DTW. Puntos por distancia local.
- **amplitude** — un evento por trazo `fwd`. Recorrido de cada trazo normalizado
  al rango del propio usuario, comparado con el del patrón.
- **estrellas (ADR-025):** ★ ≥70 % y al final · ★★ ≥85 % y **cero eventos a 0** ·
  ★★★ ≥95 %, σ ≤ 15 ms y al BPM objetivo. Un 88 % con un fallo suelto = 1 estrella.
- **diagnóstico:** distingue **sesgo** (media con signo → mueve el gesto) de
  **dispersión** (σ → practica la regularidad).

## Pendiente (bloquea B8.8 / sellado)

- **B8.5 — tomas reales.** Los tests actuales (`ReplayScoringTests`) generan el
  `Take` a partir del patrón (`SyntheticTake`). `docs/TESTING.md` pide
  `.xfsession` **grabados** (`flare-2c__good` ≥ 0.88, `__late` sesgo ~35 ms,
  `__sloppy` ≤ 0.60). Necesitan hardware.
- **B8.4 — umbrales del diagnóstico** (`Diagnoser.biasMs = 12`, `spreadMs = 18`)
  son provisionales: se afinan contra esas tomas reales.
- Cuando estén: mover `SyntheticTake` a `XFTestKit`, repetir los tests contra los
  `.xfsession`, `make seal M=XFAnalysis`.
