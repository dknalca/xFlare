// SPDX-License-Identifier: GPL-3.0-only

import CoreGraphics
import XFDesign
import XFNotation

/// Convierte un `Scratch` + "en qué tick estamos" en la geometría de la
/// autopista (`HighwayFrame`). **Puro**: sin SpriteKit, sin reloj propio, sin
/// estado mutable. Se puede testear entero sin pantalla (B7.3) y alimenta los
/// golden SVG de B7.6.
///
/// El patrón se repite: cuando la ventana visible pasa de `scratch.lengthTicks`,
/// se envuelve con el módulo. Así la autopista hace loop sin fin, como la sesión.
public struct HighwayLayout {

    public let scratch: Scratch
    public let ppq: Int
    /// Rango [mín, máx] de la posición del disco en todo el patrón. Se calcula
    /// una vez al construir para que la curva no se reescale en cada fotograma.
    public let positionRange: ClosedRange<Double>

    /// Paso de muestreo de la curva, en ticks. `ppq/24` ≈ resolución de fusa;
    /// más fino que un píxel a escalas normales.
    private let sampleStep: Int

    public init(scratch: Scratch) {
        self.scratch = scratch
        self.ppq = scratch.ppq
        self.sampleStep = max(1, scratch.ppq / 24)

        // Barrido del patrón entero para fijar el rango vertical.
        let length = max(1, scratch.lengthTicks)
        var lo = Double.greatestFiniteMagnitude
        var hi = -Double.greatestFiniteMagnitude
        var t = 0
        while t < length {
            let p = PositionSampler.position(of: scratch, atTick: t)
            lo = min(lo, p)
            hi = max(hi, p)
            t += max(1, scratch.ppq / 24)
        }
        // por si el patrón es degenerado (longitud 0, curva plana)
        if !(lo <= hi) { lo = 0; hi = 1 }
        self.positionRange = lo...hi
    }

    // MARK: - fotograma

    /// La geometría de la autopista cuando "ahora" está en `currentTick`.
    ///
    /// - Parameters:
    ///   - userTrace: la traza del disco del usuario (ticks **absolutos** de
    ///     sesión), con el nivel de acierto por punto. Vacía = solo fantasma.
    ///   - clickHits: el resultado del usuario en cada click del patrón.
    public func frame(atTick currentTick: Double,
                      geometry g: HighwayGeometry,
                      userTrace: [TracePoint] = [],
                      clickHits: [ClickHit] = []) -> HighwayFrame {
        let length = max(1, scratch.lengthTicks)
        let pxPerTick = g.pixelsPerTick(ppq: ppq)
        let playheadX = g.playheadX

        func x(forTick tick: Double) -> CGFloat {
            playheadX + CGFloat(tick - currentTick) * pxPerTick
        }
        func tick(forX px: CGFloat) -> Double {
            currentTick + Double((px - playheadX) / pxPerTick)
        }

        let (yBottom, yTop) = g.curveBand
        let span = positionRange.upperBound - positionRange.lowerBound
        func y(forPosition p: Double) -> CGFloat {
            guard span > 0 else { return (yBottom + yTop) / 2 }
            let n = (p - positionRange.lowerBound) / span
            return yBottom + CGFloat(n) * (yTop - yBottom)
        }
        func wrapped(_ tick: Double) -> Int {
            let m = tick.truncatingRemainder(dividingBy: Double(length))
            return Int(m < 0 ? m + Double(length) : m)
        }

        let tMin = tick(forX: 0)
        let tMax = tick(forX: g.size.width)

        // --- rejilla de negras y compás (ADR-038) ---
        // Líneas en los ticks de negra `b·ppq`. Cada una es de COMPÁS o de
        // negra según su posición *dentro del patrón* (`wrapped`), no según la
        // posición absoluta: así el conjunto de líneas (valores y clasificación)
        // es idéntico en `T` y en `T + L` para cualquier longitud de patrón, y
        // la invariancia `frame(T) == frame(T + L)` se mantiene.
        var beatLines: [CGFloat] = []
        var barLines: [CGFloat] = []
        let beatsPerBar = max(1, g.beatsPerBar)
        let firstBeat = Int((tMin / Double(ppq)).rounded(.up))
        let lastBeat = Int((tMax / Double(ppq)).rounded(.down))
        if firstBeat <= lastBeat {
            for b in firstBeat...lastBeat {
                let px = x(forTick: Double(b * ppq))
                let beatInPattern = wrapped(Double(b * ppq)) / ppq
                if beatInPattern % beatsPerBar == 0 {
                    barLines.append(px)
                } else {
                    beatLines.append(px)
                }
            }
        }

        // --- curva del disco ---
        // Anclamos la rejilla de muestreo con division *hacia abajo* (no la
        // truncada de Swift): asi el mismo tick da la misma rejilla tanto si
        // `tMin` es negativo como positivo, y `frame(T) == frame(T + L)`.
        var curve: [CGPoint] = []
        var sample = Int((tMin / Double(sampleStep)).rounded(.down)) * sampleStep
        while Double(sample) <= tMax + Double(sampleStep) {
            let p = PositionSampler.position(of: scratch, atTick: wrapped(Double(sample)))
            curve.append(CGPoint(x: x(forTick: Double(sample)), y: y(forPosition: p)))
            sample += sampleStep
        }

        // --- marcas de fader sobre la curva (una por copia visible del patrón) ---
        var open: [CGPoint] = []
        var close: [CGPoint] = []
        let firstCopy = Int((tMin / Double(length)).rounded(.down)) - 1
        let lastCopy = Int((tMax / Double(length)).rounded(.down)) + 1
        for copy in firstCopy...max(firstCopy, lastCopy) {
            let base = Double(copy) * Double(length)
            for event in scratch.faderEvents {
                let absTick = base + Double(event.t)
                guard absTick >= tMin - 1, absTick <= tMax + 1 else { continue }
                let p = PositionSampler.position(of: scratch, atTick: event.t)
                let point = CGPoint(x: x(forTick: absTick), y: y(forPosition: p))
                if event.state == .open { open.append(point) } else { close.append(point) }
            }
        }

        // --- carril de fader: tramos de estado constante entre transiciones ---
        var boundaries: [Double] = [tMin]
        for copy in firstCopy...max(firstCopy, lastCopy) {
            let base = Double(copy) * Double(length)
            for event in scratch.faderEvents {
                let absTick = base + Double(event.t)
                if absTick > tMin, absTick < tMax { boundaries.append(absTick) }
            }
        }
        boundaries.append(tMax)
        boundaries.sort()

        var bands: [FaderBand] = []
        for i in 0..<(boundaries.count - 1) {
            let a = boundaries[i], b = boundaries[i + 1]
            guard b > a else { continue }
            let mid = wrapped((a + b) / 2)
            let isOpen = PositionSampler.faderState(of: scratch, atTick: mid) == .open
            let xa = x(forTick: a), xb = x(forTick: b)
            if let last = bands.last, last.isOpen == isOpen, abs(last.xRange.upperBound - xa) < 0.001 {
                bands[bands.count - 1].xRange = last.xRange.lowerBound...xb   // fusiona contiguos
            } else {
                bands.append(FaderBand(xRange: xa...xb, isOpen: isOpen))
            }
        }

        // --- capa de usuario: traza partida en tramos por nivel de acierto ---
        // `nil` y `.perfect` se dibujan igual (acento): la clave de tinte los junta.
        func tintKey(_ level: HitLevel?) -> HitLevel? {
            (level == nil || level == .perfect) ? nil : level
        }
        let visible = userTrace
            .filter { $0.tick >= tMin - Double(sampleStep) && $0.tick <= tMax + Double(sampleStep) }
            .sorted { $0.tick < $1.tick }
            .map { (point: CGPoint(x: x(forTick: $0.tick), y: y(forPosition: $0.position)),
                    key: tintKey($0.level)) }

        var userSegments: [TintedPolyline] = []
        var i = 0
        while i < visible.count {
            let key = visible[i].key
            var pts: [CGPoint] = []
            var j = i
            while j < visible.count && visible[j].key == key { pts.append(visible[j].point); j += 1 }
            if j < visible.count { pts.append(visible[j].point) }   // punto de corte compartido, sin hueco
            if pts.count >= 2 { userSegments.append(TintedPolyline(points: pts, level: key)) }
            i = j
        }

        // --- marcas de click con el resultado del usuario ---
        var hitMarks: [TintedMark] = []
        for hit in clickHits {
            // la copia del patrón más cercana a "ahora"
            let copy = ((currentTick - Double(hit.patternTick)) / Double(length)).rounded()
            let absTick = Double(hit.patternTick) + copy * Double(length)
            let wrappedTick = wrapped(Double(hit.patternTick))
            let closes = scratch.faderEvents
                .first { $0.t == hit.patternTick }?.state != FaderState.open
            let p = PositionSampler.position(of: scratch, atTick: wrappedTick)
            hitMarks.append(TintedMark(
                point: CGPoint(x: x(forTick: absTick), y: y(forPosition: p)),
                level: HitLevel(absOffsetMs: abs(hit.offsetMs)),
                closes: closes))
        }

        return HighwayFrame(discCurve: curve, openMarks: open, closeMarks: close,
                            faderBands: bands, playheadX: playheadX,
                            userSegments: userSegments, hitMarks: hitMarks,
                            beatLines: beatLines, barLines: barLines)
    }
}
