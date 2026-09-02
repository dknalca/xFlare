// SPDX-License-Identifier: GPL-3.0-only

import CoreGraphics
import XFNotation

/// Miniatura del **esquema simple TTM** de un scratch, para la celda de la matriz
/// y la ficha del truco.
///
/// Convención (feedback 2026-09-02): a diferencia de la autopista y los
/// ejercicios —donde el tramo con el fader cerrado NO se dibuja (ausencia =
/// mute)— aquí la curva del disco es **una sola línea continua** y cada **corte**
/// (el fader se cierra) se marca con un **círculo relleno ●**. El corte se supone
/// corto, así que no se deja hueco. No se dibuja círculo al abrir el fader.
///
/// Todo normalizado al cuadrado unidad (`x` = tiempo 0→1, `y` = 0 abajo → 1
/// arriba entre el mínimo y el máximo de la posición). Puro y testeable.
public struct TTMThumbnail: Equatable, Sendable {

    /// La curva del disco: **una** polilínea continua, un ciclo del patrón.
    public var curve: [CGPoint]

    /// Puntos donde el sonido se **corta**: el fader se cierra. Círculo relleno ●.
    /// Un baby (no toca el fader) no tiene ninguno.
    public var cuts: [CGPoint]

    public init(curve: [CGPoint], cuts: [CGPoint] = []) {
        self.curve = curve
        self.cuts = cuts
    }

    /// - Parameter samples: resolución de muestreo de la curva a lo ancho.
    ///
    /// Se dibuja **un solo ciclo** del patrón (`lengthTicks / cycles`), como la
    /// referencia TTM: un gesto, no el ejercicio entero repetido.
    public static func build(scratch: Scratch, samples: Int = 120) -> TTMThumbnail {
        let n = max(8, samples)
        let length = max(1, scratch.lengthTicks / max(1, scratch.cycles))
        let L = Double(length)

        // Rango vertical de toda la curva, para una escala estable.
        var lo = Double.greatestFiniteMagnitude
        var hi = -Double.greatestFiniteMagnitude
        for i in 0...n {
            let t = min(length, Int(Double(i) / Double(n) * L))
            let p = PositionSampler.position(of: scratch, atTick: t)
            lo = min(lo, p); hi = max(hi, p)
        }
        let span = hi - lo
        func y(_ p: Double) -> CGFloat { span > 1e-9 ? CGFloat((p - lo) / span) : 0.5 }
        func pointAt(_ t: Int) -> CGPoint {
            CGPoint(x: CGFloat(min(1, max(0, Double(t) / L))),
                    y: y(PositionSampler.position(of: scratch, atTick: min(length, max(0, t)))))
        }

        // Una sola curva continua (sin partir por el fader).
        var curve: [CGPoint] = []
        curve.reserveCapacity(n + 1)
        for i in 0...n { curve.append(pointAt(min(length, Int(Double(i) / Double(n) * L)))) }

        // Cortes = cada evento de fader que CIERRA (incluido en t=0: el chirp
        // arranca con el fader cerrado y eso ya es un corte). Abrir no marca.
        var cuts: [CGPoint] = []
        for e in scratch.faderEvents where e.state != .open && e.t < length {
            let p = pointAt(e.t)
            if !cuts.contains(where: { abs($0.x - p.x) < 0.03 && abs($0.y - p.y) < 0.06 }) {
                cuts.append(p)
            }
        }

        return TTMThumbnail(curve: curve, cuts: cuts)
    }
}
