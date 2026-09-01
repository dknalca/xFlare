// SPDX-License-Identifier: GPL-3.0-only

import CoreGraphics
import XFNotation

/// Miniatura del gráfico TTM de un scratch para la celda de la matriz: la curva
/// del disco y los tramos donde el fader está cerrado, **normalizados al cuadrado
/// unidad** para que la vista solo tenga que escalar.
///
/// Se calcula de `Scratch` con `PositionSampler` (mismo muestreo que la
/// autopista, sin geometría). De momento se usa solo en un par de celdas
/// (`docs/NOTATION.md` es la referencia del dibujo completo).
public struct TTMThumbnail: Equatable, Sendable {

    /// Curva del disco. `x` recorre 0→1 en el tiempo del patrón; `y` 0→1 de la
    /// posición mínima a la máxima (0 abajo).
    public var curve: [CGPoint]

    /// Tramos del eje `x` (0…1) donde el fader está **cerrado** (la barrita).
    public var faderClosed: [ClosedRange<CGFloat>]

    public init(curve: [CGPoint], faderClosed: [ClosedRange<CGFloat>]) {
        self.curve = curve
        self.faderClosed = faderClosed
    }

    /// - Parameter samples: puntos de muestreo a lo largo del patrón.
    public static func build(scratch: Scratch, samples: Int = 72) -> TTMThumbnail {
        let n = max(2, samples)
        let length = max(1, scratch.lengthTicks)

        func tick(_ i: Int) -> Int { min(length, Int((Double(i) / Double(n)) * Double(length))) }

        // posiciones + rango vertical
        var positions: [Double] = []
        positions.reserveCapacity(n + 1)
        var lo = Double.greatestFiniteMagnitude
        var hi = -Double.greatestFiniteMagnitude
        for i in 0...n {
            let p = PositionSampler.position(of: scratch, atTick: tick(i))
            positions.append(p)
            lo = min(lo, p); hi = max(hi, p)
        }
        let span = hi - lo

        var curve: [CGPoint] = []
        curve.reserveCapacity(n + 1)
        for (i, p) in positions.enumerated() {
            let x = CGFloat(i) / CGFloat(n)
            let y = span > 1e-9 ? CGFloat((p - lo) / span) : 0.5
            curve.append(CGPoint(x: x, y: y))
        }

        // Tramos de fader cerrado: se sacan de los eventos exactos, no del
        // muestreo (los cierres de un flare duran ~20 ticks y el paso de la
        // curva es mayor, se los saltaria).
        let total = Double(length)
        var closed: [ClosedRange<CGFloat>] = []
        var state: FaderState = .open
        var closeStart: Int?
        for event in scratch.faderEvents.sorted(by: { $0.t < $1.t }) {
            if event.state != .open, state == .open {
                closeStart = event.t
            } else if event.state == .open, state != .open, let s = closeStart {
                appendClosed(&closed, from: s, to: event.t, total: total)
                closeStart = nil
            }
            state = event.state
        }
        if let s = closeStart { appendClosed(&closed, from: s, to: length, total: total) }

        return TTMThumbnail(curve: curve, faderClosed: closed)
    }

    private static func appendClosed(_ out: inout [ClosedRange<CGFloat>],
                                     from: Int, to: Int, total: Double) {
        let lo = CGFloat(min(1, max(0, Double(from) / total)))
        let hi = CGFloat(min(1, max(0, Double(to) / total)))
        if hi > lo { out.append(lo...hi) }
    }
}
