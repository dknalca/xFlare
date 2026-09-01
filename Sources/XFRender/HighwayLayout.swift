// SPDX-License-Identifier: GPL-3.0-only

import CoreGraphics
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
    public func frame(atTick currentTick: Double, geometry g: HighwayGeometry) -> HighwayFrame {
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

        return HighwayFrame(discCurve: curve, openMarks: open, closeMarks: close,
                            faderBands: bands, playheadX: playheadX)
    }
}
