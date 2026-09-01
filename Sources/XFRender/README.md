# XFRender

**Capa 2 · depende de XFDesign, XFNotation · SEALED 2026-09-01 · `apiVersion = 1`**

Dibuja la autopista (pantalla héroe) y el scope circular del plato. **No lee
hardware ni base de datos, no puntúa, no mira ningún reloj por su cuenta.** Se
sincroniza al **reloj de AUDIO** que le pasa `XFApp`, nunca al frame — así no hay
deriva por muchas horas que pase.

Patrón del módulo: cada vista tiene un **`…Layout` puro** (geometría, `struct`,
testeable sin SpriteKit) y una **`…Scene` / `…View` delgada** (SpriteKit + SwiftUI)
que solo pinta lo que el layout calcula y reutiliza nodos para no reservar
memoria por fotograma. Ver **ADR-036**.

## La autopista

### Geometría pura

```swift
public struct HighwayGeometry: Equatable, Sendable {
    public init(size: CGSize, playheadFraction: CGFloat = 0.30,
                pixelsPerBeat: CGFloat = 120, laneHeight: CGFloat = 40, curveInset: CGFloat = 16,
                beatsPerBar: Int = 4)          // rejilla: negras por compás (ADR-038)
    public var playheadX: CGFloat
    public func pixelsPerTick(ppq: Int) -> CGFloat
    public var curveBand: (bottom: CGFloat, top: CGFloat)
}

public struct HighwayLayout {
    public init(scratch: Scratch)                 // calcula positionRange una vez
    public let positionRange: ClosedRange<Double>

    public func frame(atTick currentTick: Double,
                      geometry: HighwayGeometry,
                      userTrace: [TracePoint] = [],
                      clickHits: [ClickHit] = []) -> HighwayFrame
}
```

`frame(atTick:)` es una **función pura del tick de AUDIO**: mismo tick ⇒ mismo
`HighwayFrame`, y `frame(T) == frame(T + lengthTicks)` bit a bit (el patrón hace
loop con el módulo). Ahí está la garantía de "sin deriva".

Ejes: coordenadas con **origen abajo-izquierda** (como SpriteKit). La cabeza de
lectura va fija al 30 % del ancho; lo que viene está a su derecha y se desplaza
hacia ella.

### Lo que sale

```swift
public struct HighwayFrame: Equatable, Sendable {
    public var discCurve: [CGPoint]          // curva del patrón (fantasma)
    public var openMarks: [CGPoint]          // ○ el fader abre
    public var closeMarks: [CGPoint]         // ● el fader cierra (el click)
    public var faderBands: [FaderBand]       // carril de fader, tramos contiguos
    public var userSegments: [TintedPolyline]  // tu curva, partida por nivel de acierto
    public var hitMarks: [TintedMark]        // resultado en cada click
    public var playheadX: CGFloat
    public var beatLines: [CGFloat]          // x de las negras (ADR-038)
    public var barLines: [CGFloat]           // x de los compases (cada beatsPerBar negras)
    public var discSegments: [[CGPoint]]     // la sombra partida donde el fader cierra (ADR-040)
}

public struct FaderBand: Equatable, Sendable { public var xRange: ClosedRange<CGFloat>; public var isOpen: Bool }
public struct TracePoint: Equatable, Sendable { public var tick: Double; public var position: Double; public var level: HitLevel? }
public struct TintedPolyline: Equatable, Sendable { public var points: [CGPoint]; public var level: HitLevel? }
public struct ClickHit: Equatable, Sendable { public var patternTick: Int; public var offsetMs: Double }
public struct TintedMark: Equatable, Sendable { public var point: CGPoint; public var level: HitLevel; public var closes: Bool }
```

**Capa de usuario (B7.4):** `TracePoint.tick` es un tick **absoluto de sesión**
(no envuelto: es una grabación en tiempo real). La curva del usuario se dibuja en
el **mismo eje vertical** que el fantasma. `level == nil` o `.perfect` → color de
acento; el resto → `HitLevel.color`. `XFRender` no juzga la tolerancia:
`XFAnalysis` rellena los niveles.

### La escena

```swift
public final class HighwayScene: SKScene {
    public var currentTick: () -> Double        // lee el reloj de AUDIO
    public var userTrace: () -> [TracePoint]
    public var clickHits: () -> [ClickHit]
    public func load(_ scratch: Scratch)
    public init(geometry: HighwayGeometry)
}

public struct HighwayView: NSViewRepresentable {
    public init(scratch: Scratch, geometry: HighwayGeometry,
                tick: @escaping () -> Double,
                userTrace: @escaping () -> [TracePoint] = { [] },
                clickHits: @escaping () -> [ClickHit] = { [] })
}
```

`SKScene.update(_:)` lo llama SpriteKit al **refresco real** (60 en Intel, 120 en
ProMotion); dentro se lee `currentTick()` y se dibuja ese instante.

### Golden SVG (B7.6)

```swift
public enum HighwaySVG {
    public static func document(_ frame: HighwayFrame, geometry: HighwayGeometry) -> String
}
```

SVG determinista: coordenadas a **4 decimales** en locale C, sin `-0` (política de
ADR-028). `Fixtures/golden/highway/<id>.svg` tiene los 25 scratches; se regeneran
con `make golden-update`.

## El scope circular

```swift
public struct ScopeReading: Equatable, Sendable { public var position, velocity, confidence: Double }
public struct ScopeGeometry: Equatable, Sendable {
    public init(size: CGSize, padding: CGFloat = 12)
    public var center: CGPoint; public var referenceRadius: CGFloat
}
public struct ScopeLayout {
    public init(degradedBelow: Double = 0.4)
    public func figure(readings: [ScopeReading], geometry: ScopeGeometry) -> ScopeFigure
}
public struct ScopeFigure: Equatable, Sendable {
    public var center: CGPoint; public var referenceRadius: CGFloat
    public var dot: CGPoint; public var dotRadiusFraction: CGFloat; public var angleRadians: CGFloat
    public var trail: [CGPoint]; public var isDegraded: Bool
}

public final class ScopeScene: SKScene { public var readings: () -> [ScopeReading]; public init(geometry: ScopeGeometry) }
public struct ScopeView: NSViewRepresentable { public init(geometry: ScopeGeometry, readings: @escaping () -> [ScopeReading]) }
```

Es un Lissajous **reconstruido**: el ángulo sale de la fase acumulada
(`position · 2π`) porque las dos portadoras en cuadratura crudas viven en la capa
RT (`CXFTimecode`); el radio del punto sale de la **confianza** — señal limpia →
punto sobre la circunferencia, aguja sucia → se hunde al centro y `isDegraded`. El
rastro (historial que aporta quien llama) da dirección y velocidad.

## Ejemplo de uso

```swift
import XFRender

let geo = HighwayGeometry(size: view.bounds.size)
HighwayView(
    scratch: currentScratch,
    geometry: geo,
    tick:      { clock.currentTick() },            // reloj de AUDIO
    userTrace: { capture.recentTrace() },          // XFApp lo va rellenando
    clickHits: { analysis.clickHitsSoFar() }
)

ScopeView(geometry: ScopeGeometry(size: CGSize(width: 160, height: 160)),
          readings: { capture.recentScopeReadings() })
```

## Qué NO hace (a propósito)

- No arranca hilos ni temporizadores. El tiempo entra por `currentTick()`.
- No decodifica timecode ni lee `MotionSample`: recibe `TracePoint` /
  `ScopeReading` ya listos.
- No puntúa: los `HitLevel` los pone `XFAnalysis`.
- No dibuja el Lissajous con las portadoras crudas (viven en la capa RT); lo
  reconstruye desde `position` + `confidence`.
- No mide fps ni garantiza 120: eso es `SKView` + la máquina (B7.2b).

## Decisiones

- **ADR-028** — goldens con 4 decimales y tolerancia; universal desde el día 1.
- **ADR-036** — layout puro + escena delgada; sincronización al reloj de AUDIO;
  golden SVG; Lissajous reconstruido.
