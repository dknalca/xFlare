// SPDX-License-Identifier: GPL-3.0-only

import CoreGraphics
import XFNotation

/// Miniatura del **esquema simple TTM** de un scratch (celda de la matriz y
/// ficha del truco), al estilo de la *Periodic Matrix of Skratches*.
///
/// Convención (feedback 2026-09-03, 2ª iteración):
///  - Se dibuja **la curva del disco entera** (un solo ciclo del gesto), sin
///    huecos. Lo que cambia es el **color** de cada tramo:
///     · fader **abierto** → suena → color vivo.
///     · fader **cerrado** → cortado / silencio → gris apagado.
///  - Sin puntos ●: el propio color dice dónde suena y dónde se corta. Así el
///    vértice del movimiento siempre se ve arriba (es la curva de verdad) y no
///    hay marcas que se salgan del cuadro (el problema de `tear-flare-1c` y
///    `crab`).
///
/// Todo normalizado al cuadrado unidad (`x` = tiempo 0→1, `y` = 0 abajo → 1
/// arriba entre el mínimo y el máximo de la posición, con un margen para que el
/// trazo no toque el borde). Puro y testeable.
public struct TTMThumbnail: Equatable, Sendable {

    /// Un tramo contiguo de la curva con un mismo estado de fader.
    public struct Segment: Equatable, Sendable {
        public var points: [CGPoint]
        /// `true` = suena (fader abierto); `false` = cortado / silencio.
        public var sounding: Bool

        public init(points: [CGPoint], sounding: Bool) {
            self.points = points
            self.sounding = sounding
        }
    }

    /// La curva completa, partida en tramos por los cambios de fader. Contigua:
    /// cada tramo comparte su punto de unión con el siguiente (no hay saltos).
    public var segments: [Segment]

    public init(segments: [Segment]) {
        self.segments = segments
    }

    /// Todos los puntos de todos los tramos, en orden.
    public var allPoints: [CGPoint] { segments.flatMap { $0.points } }

    /// - Parameter samples: resolución de muestreo de la curva a lo ancho.
    ///
    /// Se dibuja **un solo ciclo** del patrón (`lengthTicks / cycles`), como la
    /// referencia TTM: un gesto, no el ejercicio entero repetido.
    public static func build(scratch: Scratch, samples: Int = 160) -> TTMThumbnail {
        let n = max(8, samples)
        let length = max(1, scratch.lengthTicks / max(1, scratch.cycles))
        let L = Double(length)

        func tickAt(_ i: Int) -> Int { min(length, max(0, Int(Double(i) / Double(n) * L))) }

        // rango vertical de toda la curva, para una escala estable
        var lo = Double.greatestFiniteMagnitude
        var hi = -Double.greatestFiniteMagnitude
        for i in 0...n {
            let p = PositionSampler.position(of: scratch, atTick: tickAt(i))
            lo = min(lo, p); hi = max(hi, p)
        }
        let span = hi - lo
        // deja un 8 % de margen arriba y abajo: el trazo no toca el borde
        func y(_ p: Double) -> CGFloat {
            let norm = span > 1e-9 ? (p - lo) / span : 0.5
            return CGFloat(0.08 + 0.84 * norm)
        }
        func point(_ t: Int) -> CGPoint {
            CGPoint(x: CGFloat(min(1, max(0, Double(t) / L))),
                    y: y(PositionSampler.position(of: scratch, atTick: t)))
        }
        func isOpen(_ t: Int) -> Bool {
            PositionSampler.faderState(of: scratch, atTick: min(length - 1, max(0, t))) == .open
        }

        // muestrea el ciclo entero (punto + suena/no)
        var pts: [(p: CGPoint, on: Bool)] = []
        pts.reserveCapacity(n + 1)
        for i in 0...n { let t = tickAt(i); pts.append((point(t), isOpen(t))) }

        // parte la curva en tramos por el cambio de fader; el punto del cambio
        // va en LOS DOS tramos, así la línea queda contigua.
        var segments: [Segment] = []
        var cur: [CGPoint] = [pts[0].p]
        var curOn = pts[0].on
        for k in 1...n {
            let s = pts[k]
            cur.append(s.p)
            if s.on != curOn {
                segments.append(Segment(points: cur, sounding: curOn))
                cur = [s.p]
                curOn = s.on
            }
        }
        if cur.count >= 2 { segments.append(Segment(points: cur, sounding: curOn)) }

        return TTMThumbnail(segments: segments)
    }
}
