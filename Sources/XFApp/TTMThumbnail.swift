// SPDX-License-Identifier: GPL-3.0-only

import CoreGraphics
import XFNotation

/// Miniatura del **esquema simple TTM** de un scratch (celda de la matriz y
/// ficha del truco), al estilo de la *Periodic Matrix of Skratches*.
///
/// Convención (feedback 2026-09-03):
///  - La curva del disco se dibuja **solo donde suena** (fader abierto). El
///    tramo mudo NO se pinta — mute = ausencia, igual que la autopista y el TTM
///    real. Así "Forward Cut" o "Stab" no arrastran la vuelta silenciosa.
///  - Cada **corte** (el fader se cierra) es un **círculo relleno ●** en una
///    **fila horizontal fija** en el borde superior — la "pista de fader" del
///    TTM. Puestos así, los cortes de un flare quedan alineados y simétricos, y
///    el del chirp cae sobre el vértice.
///
/// Todo normalizado al cuadrado unidad (`x` = tiempo 0→1, `y` = 0 abajo → 1
/// arriba entre el mínimo y el máximo de la posición). Puro y testeable.
public struct TTMThumbnail: Equatable, Sendable {

    /// Y (normalizada) de la fila de cortes, cerca del borde superior.
    public static let cutLineY: CGFloat = 0.98

    /// Tramos de la curva del disco **donde suena** (fader abierto), de
    /// izquierda a derecha. Un baby (fader siempre abierto) tiene uno solo.
    public var segments: [[CGPoint]]

    /// Puntos de corte (el fader cierra), en la fila `cutLineY`. ● relleno.
    public var cuts: [CGPoint]

    public init(segments: [[CGPoint]], cuts: [CGPoint] = []) {
        self.segments = segments
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

        func tickAt(_ i: Int) -> Int { min(length, max(0, Int(Double(i) / Double(n) * L))) }

        // rango vertical de toda la curva, para una escala estable
        var lo = Double.greatestFiniteMagnitude
        var hi = -Double.greatestFiniteMagnitude
        for i in 0...n {
            let p = PositionSampler.position(of: scratch, atTick: tickAt(i))
            lo = min(lo, p); hi = max(hi, p)
        }
        let span = hi - lo
        func y(_ p: Double) -> CGFloat { span > 1e-9 ? CGFloat((p - lo) / span) : 0.5 }
        func point(_ t: Int) -> CGPoint {
            CGPoint(x: CGFloat(min(1, max(0, Double(t) / L))),
                    y: y(PositionSampler.position(of: scratch, atTick: t)))
        }
        func isOpen(_ t: Int) -> Bool {
            PositionSampler.faderState(of: scratch, atTick: min(length - 1, max(0, t))) == .open
        }

        // recorre las muestras acumulando tramos donde el fader esta abierto;
        // al cerrar, marca un corte en la fila superior con la x de ese instante
        var segments: [[CGPoint]] = []
        var cuts: [CGPoint] = []
        var current: [CGPoint] = []
        var prevOpen = false

        for i in 0...n {
            let t = tickAt(i)
            let open = isOpen(t)
            if open {
                current.append(point(t))
            } else if prevOpen {
                // se acaba de cerrar: cierra el tramo y anota el corte
                if current.count >= 2 { segments.append(current) }
                current.removeAll(keepingCapacity: true)
                addCut(&cuts, x: CGFloat(min(1, Double(t) / L)))
            }
            prevOpen = open
        }
        if current.count >= 2 { segments.append(current) }

        // cortes explicitos del patron por si el muestreo se los salta (chirp:
        // cierre muy al final del tramo)
        for e in scratch.faderEvents where e.state == .closed && e.t < length {
            addCut(&cuts, x: CGFloat(min(1, Double(e.t) / L)))
        }

        return TTMThumbnail(segments: segments, cuts: cuts.sorted { $0.x < $1.x })
    }

    private static func addCut(_ cuts: inout [CGPoint], x: CGFloat) {
        guard x > 0.001, x < 0.999 else { return }
        if !cuts.contains(where: { abs($0.x - x) < 0.04 }) {
            cuts.append(CGPoint(x: x, y: cutLineY))
        }
    }
}
