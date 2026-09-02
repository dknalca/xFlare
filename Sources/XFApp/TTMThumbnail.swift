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

    /// Puntos donde el fader **abre** (empieza a sonar): círculo **hueco** ○.
    public var openMarks: [CGPoint]

    /// Puntos donde el fader **cierra** (el corte / click): círculo **relleno** ●.
    public var closeMarks: [CGPoint]

    /// Puntos donde el disco **cambia de sentido** con el fader abierto: ahí el
    /// vinilo se para un instante y ese silencio corta el sonido sin mover el
    /// fader — el *phantom click* del manual TTM. Se marcan aparte de los cortes
    /// de fader (docs/MATRIX_MAPPING.md §3b).
    public var phantomCuts: [CGPoint]

    public init(segments: [[CGPoint]], openMarks: [CGPoint] = [], closeMarks: [CGPoint] = [],
                phantomCuts: [CGPoint] = []) {
        self.segments = segments
        self.openMarks = openMarks
        self.closeMarks = closeMarks
        self.phantomCuts = phantomCuts
    }

    /// - Parameter samples: resolución de muestreo de la curva a lo ancho.
    ///
    /// Se dibuja **un solo ciclo** del patrón (`lengthTicks / cycles`), como la
    /// referencia TTM: un gesto, no el ejercicio entero repetido.
    public static func build(scratch: Scratch, samples: Int = 120) -> TTMThumbnail {
        let n = max(8, samples)
        let length = max(1, scratch.lengthTicks / max(1, scratch.cycles))
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

        // Intervalos con el fader abierto, en ticks. Solo el primer ciclo.
        let events = scratch.faderEvents.filter { $0.t < length }.sorted { $0.t < $1.t }
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

        // Círculos por transición de fader: abrir (○, empieza a sonar) y cerrar
        // (●, el corte). El evento inicial en t=0 no cuenta.
        var openMarks: [CGPoint] = []
        var closeMarks: [CGPoint] = []
        for (idx, e) in events.enumerated() where !(idx == 0 && e.t == 0) {
            if e.state == .open { openMarks.append(pointAt(e.t)) }
            else { closeMarks.append(pointAt(e.t)) }
        }

        // Phantom clicks: el disco cambia de sentido (fwd<->rev) y ahí se para un
        // instante. Solo cuentan con el fader abierto (si está cerrado, ya está
        // mudo). El cambio de sentido en t=0 no es un corte.
        var phantomCuts: [CGPoint] = []
        for i in 1..<max(1, scratch.record.count) {
            let prev = scratch.record[i - 1].dir
            let cur = scratch.record[i].dir
            let reversal = (prev == .fwd && cur == .rev) || (prev == .rev && cur == .fwd)
            guard reversal else { continue }
            let t = scratch.record[i].t
            if t > 0, t < length,
               PositionSampler.faderState(of: scratch, atTick: t) == .open {
                phantomCuts.append(pointAt(t))
            }
        }

        return TTMThumbnail(segments: segments, openMarks: openMarks,
                            closeMarks: closeMarks, phantomCuts: phantomCuts)
    }
}
