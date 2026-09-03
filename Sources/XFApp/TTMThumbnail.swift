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
///  - Cada **corte** (el fader se cierra) es un **círculo relleno ●**. Dónde va
///    depende de la familia:
///     · **flare / orbit / crab** (fader abierto, cierres momentáneos): todos los
///       ● en **una misma horizontal**, repartidos **simétricos** — así se lee
///       "toca-corta-toca-corta" de un vistazo (feedback 2026-09-03).
///     · **chirp**: un solo ● en el **vértice** del movimiento (el fader cierra
///       al frenar).
///     · resto (cut, transformer, tear): el ● **sobre la curva**, donde deja de
///       sonar.
///
/// Todo normalizado al cuadrado unidad (`x` = tiempo 0→1, `y` = 0 abajo → 1
/// arriba entre el mínimo y el máximo de la posición). Puro y testeable.
public struct TTMThumbnail: Equatable, Sendable {

    /// Tramos de la curva del disco **donde suena** (fader abierto), de
    /// izquierda a derecha. Un baby (fader siempre abierto) tiene uno solo.
    public var segments: [[CGPoint]]

    /// Puntos de corte (el fader cierra), **sobre la curva**. ● relleno.
    public var cuts: [CGPoint]

    public init(segments: [[CGPoint]], cuts: [CGPoint] = []) {
        self.segments = segments
        self.cuts = cuts
    }

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
        func y(_ p: Double) -> CGFloat { span > 1e-9 ? CGFloat((p - lo) / span) : 0.5 }
        func point(_ t: Int) -> CGPoint {
            CGPoint(x: CGFloat(min(1, max(0, Double(t) / L))),
                    y: y(PositionSampler.position(of: scratch, atTick: t)))
        }
        func isOpen(_ t: Int) -> Bool {
            PositionSampler.faderState(of: scratch, atTick: min(length - 1, max(0, t))) == .open
        }

        // recorre las muestras: acumula tramos con el fader abierto; al cerrar,
        // cierra el tramo y anota el corte en su ÚLTIMO punto (sobre la curva).
        var segments: [[CGPoint]] = []
        var rawCuts: [CGPoint] = []
        var current: [CGPoint] = []
        var prevOpen = false

        for i in 0...n {
            let t = tickAt(i)
            let open = isOpen(t)
            if open {
                current.append(point(t))
            } else if prevOpen {
                if current.count >= 2 { segments.append(current) }
                if let last = current.last { addCut(&rawCuts, last) }
                current.removeAll(keepingCapacity: true)
            }
            prevOpen = open
        }
        if current.count >= 2 { segments.append(current) }
        rawCuts.sort { $0.x < $1.x }

        // vértice del movimiento (punto más alto de la curva), para el chirp
        var peak = CGPoint(x: 0.5, y: 0.9)
        for i in 0...n {
            let p = point(tickAt(i))
            if p.y > peak.y { peak = p }
        }

        let cuts = place(rawCuts, family: scratch.family, peak: peak)
        return TTMThumbnail(segments: segments, cuts: cuts)
    }

    /// Añade un corte si no hay ya uno muy cerca (dedup por proximidad).
    private static func addCut(_ cuts: inout [CGPoint], _ p: CGPoint) {
        guard p.x > 0.01, p.x < 0.99 else { return }
        if !cuts.contains(where: { abs($0.x - p.x) < 0.05 && abs($0.y - p.y) < 0.08 }) {
            cuts.append(p)
        }
    }

    /// Coloca los ● según la familia (ver la nota de la cabecera).
    private static func place(_ raw: [CGPoint], family: String, peak: CGPoint) -> [CGPoint] {
        guard !raw.isEmpty else { return [] }

        switch family {
        case "flare", "orbit", "crab", "twiddle":
            // Todos a la misma altura (media de las alturas reales, con margen
            // para no rozar el borde) y repartidos simétricos respecto al centro.
            let avgY = raw.map { $0.y }.reduce(0, +) / CGFloat(raw.count)
            let yLine = min(0.82, max(0.18, avgY))
            let m = raw.count
            var out: [CGPoint] = []
            for i in 0..<m {
                let j = m - 1 - i
                // media entre x_i y el espejo de su pareja: fuerza la simetría
                let xs = (raw[i].x + (1 - raw[j].x)) / 2
                out.append(CGPoint(x: min(0.94, max(0.06, xs)), y: yLine))
            }
            return out.sorted { $0.x < $1.x }

        case "chirp":
            // Un único ● en el vértice del movimiento (el fader cierra al frenar).
            // `y` con un pelín de margen para que el círculo no se coma el borde.
            return [CGPoint(x: peak.x, y: min(0.92, peak.y))]

        default:
            // cut, transformer, tear…: el ● se queda sobre la curva.
            return raw
        }
    }
}
