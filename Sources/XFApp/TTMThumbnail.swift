// SPDX-License-Identifier: GPL-3.0-only

import CoreGraphics
import XFNotation

/// Miniatura del gráfico TTM de un scratch para la celda de la matriz.
///
/// Notación (docs/NOTATION.md): la curva del disco es la **posición de la mano**;
/// donde el fader está **cerrado no se dibuja** (ausencia = mute), y cada
/// apertura/cierre del fader se marca con un **círculo** sobre la curva. Los
/// cortes largos son, por tanto, un hueco en la línea.
///
/// Todo normalizado al cuadrado unidad (`x` = tiempo 0→1, `y` = 0 abajo → 1
/// arriba entre el mínimo y el máximo de la posición). Puro y testeable.
public struct TTMThumbnail: Equatable, Sendable {

    /// La curva del disco partida en tramos: un tramo por cada intervalo con el
    /// fader **abierto**. Entre tramos el fader está cerrado (no se dibuja).
    public var segments: [[CGPoint]]

    /// Puntos sobre la curva donde el fader abre o cierra (los círculos).
    public var cuts: [CGPoint]

    public init(segments: [[CGPoint]], cuts: [CGPoint]) {
        self.segments = segments
        self.cuts = cuts
    }

    /// - Parameter samples: resolución de muestreo de la curva a lo ancho.
    public static func build(scratch: Scratch, samples: Int = 120) -> TTMThumbnail {
        let n = max(8, samples)
        let length = max(1, scratch.lengthTicks)
        let L = Double(length)

        // Rango vertical de TODA la curva (abierta o no), para una escala estable.
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

        // Intervalos con el fader abierto, en ticks.
        let events = scratch.faderEvents.sorted { $0.t < $1.t }
        var openIntervals: [(Int, Int)] = []
        if events.isEmpty {
            openIntervals = [(0, length)]
        } else {
            var state: FaderState = .open
            var openStart = 0
            for e in events {
                if e.state != .open, state == .open {
                    if e.t > openStart { openIntervals.append((openStart, e.t)) }
                } else if e.state == .open, state != .open {
                    openStart = e.t
                }
                state = e.state
            }
            if state == .open, length > openStart { openIntervals.append((openStart, length)) }
        }

        // Un tramo de curva por intervalo abierto.
        var segments: [[CGPoint]] = []
        for (a, b) in openIntervals where b > a {
            let steps = max(2, Int(Double(b - a) / L * Double(n)) + 1)
            var seg: [CGPoint] = []
            seg.reserveCapacity(steps + 1)
            for k in 0...steps {
                seg.append(pointAt(a + (b - a) * k / steps))
            }
            segments.append(seg)
        }

        // Círculos en cada transición de fader (el evento inicial en t=0 no cuenta).
        var cuts: [CGPoint] = []
        for (idx, e) in events.enumerated() where !(idx == 0 && e.t == 0) {
            cuts.append(pointAt(e.t))
        }

        return TTMThumbnail(segments: segments, cuts: cuts)
    }
}
