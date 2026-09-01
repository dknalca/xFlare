# XFNotation

**Capa 1 · depende de XFClock · SEALED 2026-09-01 · `apiVersion = 1`**

El modelo XFN en Swift y el compositor mano × fader. Port de `tools/xfn_core.py`.
Puro: sin hardware, sin UI, sin red.

## API pública

### Primitivas y curvas

```swift
public enum Curve { case lin, bell, acc, dec, hold   // func value(_ u: Double) -> Double }
public enum Direction { case fwd, rev, hold }
public enum FaderState { case open, closed }
public struct Division { init?(_ text: String); func unitTicks(ppq:) -> Int }

public struct HandPattern: Codable { let name; let level; let desc; let phases: [Phase] }
public struct FaderPattern: Codable {
    let name; let level; let technique; let desc; let initial: FaderState
    let perPhase: [String: [Rule]]                 // "fwd" | "rev" | "hold" | "any"
    func rules(for dir: Direction) -> [Rule]
}
public struct PrimitiveSet {
    init(handPatternsJSON: Data, faderPatternsJSON: Data) throws   // data/primitives/*.json
    func hand(_ id: String) throws -> HandPattern
    func fader(_ id: String) throws -> FaderPattern
}
```

### Scratch y composición

```swift
public struct RecordPhase: Codable {           // t, dur, dir, dist, curve, from, to
    var u0, u1: Double                          // tramo parcial de curva (recorte)
    var pFrom, pTo: Double                      // extremos "físicos" (amplitud/espejo)
}
public struct FaderEvent: Codable { var t: Int; var state: FaderState }
public struct Scratch: Codable {               // id, name, family, level, hand, fader, div,
    …                                          // cycles, technique, ppq, bpmReference,
}                                              // lengthTicks, clickCount, record, faderEvents, notes

public enum Composer {
    static func compose(hand:fader:division:cycles:bpmReference:ppq:primitives:
                        id:name:level:family:notes:) throws -> Scratch
    static func composeWithOffset(hand:fader:division:cycles:fraction:ppq:primitives:) throws -> Scratch
}

public struct CatalogEntry: Codable            // una línea de tools/catalog.json
public struct ScratchLibrary: Codable {
    var scratches: [Scratch]
    func scratch(id: String) -> Scratch?
    static func build(catalog:primitives:ppq:) throws -> ScratchLibrary   // == xfn_build.py
}
```

### Muestreo, recorte, variantes, puntuación

```swift
public enum PositionSampler {
    static func position(of: Scratch, atTick: Int) -> Double     // respeta u0/u1/pFrom/pTo
    static func faderState(of: Scratch, atTick: Int) -> FaderState
}
public extension Scratch {
    func cropped(from t0: Int, to t1: Int) -> Scratch            // tramo parcial de curva
    func withAmplitude(scale: Double) -> Scratch
    func mirrored() -> Scratch
    func withSwing(ratio: Double, ppq:) -> Scratch
}
public struct ScoreEvents { init(of: Scratch, ppq:); var clicks, pitch, amplitude, events, maxScore }
```

## Ejemplo

```swift
import XFNotation

let prims = try PrimitiveSet(
    handPatternsJSON: try Data(contentsOf: handPatternsURL),
    faderPatternsJSON: try Data(contentsOf: faderPatternsURL))

let flare = try Composer.compose(hand: "baby", fader: "flare_2c",
                                 division: "1/8", cycles: 4, primitives: prims)
let y = PositionSampler.position(of: flare, atTick: 300)     // posición del disco

let off50 = try Composer.composeWithOffset(hand: "baby", fader: "flare_2c",
                                           division: "1/8", cycles: 4, fraction: 0.5,
                                           primitives: prims)
```

## Verificación (B3)

- **B3.1** modelos Codable ↔ `data/primitives/*.json`, `tools/catalog.json`: OK.
- **B3.2** port de `compose()`: OK.
- **B3.3** golden vs `library-v0.1.json` (25 scratches): OK, **campo a campo** con
  `round4` + tolerancia 1e-9 (ADR-028 prohíbe el byte-a-byte que decía TODO.md).
  Ver **ADR-032**.
- **B3.4** recorte con `u0`/`u1`: OK (la posición del tramo recortado coincide
  exactamente con la del scratch entero).
- **B3.5** variantes: `offset`, `amplitude`, `mirror`, `swing` portadas y con
  golden contra `xfn_core.py`; **`subdivision`** añadida
  (`Composer.composeWithSubdivision`, conserva la longitud musical).
- **B3.6** `ScoreEvents`: criterio unificado con `docs/SCORING.md` (decisión del
  autor 2026-09-01) — `pitch` es uno por **semicorchea** (`ppq/4`). El 2-Click
  Flare base da 16 + 16 + 4 = 36 = **3600**. Ver ADR-032.

## Fuera de alcance de este módulo

- **`dropout`** (variante `blind` de `variants.json`): no transforma el patrón —
  decide qué compases puntúan y apaga la guía visual. Es lógica de sesión
  (`XFEngine`), no de notación.
- Tempo variable dentro de una toma: lo pone la reproducción (`XFClock`), no XFN.
