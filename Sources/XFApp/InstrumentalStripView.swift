// SPDX-License-Identifier: GPL-3.0-only

import SwiftUI
import AppKit
import simd
import XFRender

/// Tira **superior** con la forma de onda de la instrumental (en bucle) y la
/// rejilla de compás/negra. Se desplaza al mismo ritmo que la autopista y sus
/// líneas de compás caen en la **misma X**: usa la misma `HighwayGeometry` y el
/// mismo mapeo `x(tick) = playheadX + (tick - now)·pxPerTick`, en **coordenadas
/// de píxel 1:1**, igual que `HighwayScene` (cuyo `scaleMode = .resizeFill`
/// **redimensiona** la escena, no escala el contenido). Como la tira y la
/// autopista comparten columna (mismo borde izquierdo), un tick cae en la misma
/// X en las dos.
///
/// No es XFRender (que está SELLADO): es una vista de XFApp que **replica** el
/// trozo de geometría que necesita. La duplicación es unas pocas líneas y está
/// acotada aquí; es preferible a re-sellar XFRender por esto.
struct InstrumentalStripView: NSViewRepresentable {

    /// Onda del bucle entero: amplitud 0…1 + color por frecuencia.
    let wave: WaveformColored.Data
    /// Duración musical del bucle, en ticks (se redondea a compás al calcularla).
    let loopTicks: Double
    /// Geometría de la autopista (nominal). La misma instancia que `HighwayView`.
    let geometry: HighwayGeometry
    /// PPQ del patrón y su longitud, para clasificar cada línea como compás o
    /// negra igual que `HighwayLayout` (por posición dentro del patrón).
    let ppq: Int
    let patternLengthTicks: Int
    /// "Ahora" en ticks (reloj de la práctica).
    let tick: () -> Double

    func makeNSView(context: Context) -> StripView {
        let v = StripView()
        apply(to: v)
        v.startTicking()
        return v
    }

    func updateNSView(_ nsView: StripView, context: Context) { apply(to: nsView) }

    private func apply(to v: StripView) {
        v.wave = wave
        v.loopTicks = max(1, loopTicks)
        v.geometry = geometry
        v.ppq = max(1, ppq)
        v.patternLen = max(1, patternLengthTicks)
        v.tick = tick
    }

    static func dismantleNSView(_ nsView: StripView, coordinator: ()) {
        nsView.stopTicking()
    }

    final class StripView: NSView {

        var wave = WaveformColored.Data(levels: [], colors: [])
        var loopTicks: Double = 1
        var geometry = HighwayGeometry(size: CGSize(width: 1000, height: 100))
        var ppq: Int = 480
        var patternLen: Int = 1
        var tick: () -> Double = { 0 }

        private var timer: Timer?

        // paleta (docs/UI_DESIGN.md §2)
        private let bg = NSColor(srgbRed: 0x11/255, green: 0x14/255, blue: 0x18/255, alpha: 1)
        private let beatLine = NSColor(srgbRed: 0x3A/255, green: 0x44/255, blue: 0x4F/255, alpha: 1)
        private let barLine = NSColor(srgbRed: 0x5A/255, green: 0x66/255, blue: 0x74/255, alpha: 1)
        private let playhead = NSColor(srgbRed: 0x34/255, green: 0xE1/255, blue: 0xC4/255, alpha: 0.5)

        override var isFlipped: Bool { true }

        func startTicking() {
            guard timer == nil else { return }
            let t = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
                self?.needsDisplay = true
            }
            RunLoop.main.add(t, forMode: .common)
            timer = t
        }
        func stopTicking() { timer?.invalidate(); timer = nil }
        deinit { timer?.invalidate() }

        override func draw(_ dirtyRect: NSRect) {
            let w = bounds.width, h = bounds.height
            bg.setFill()
            bounds.fill()
            guard w > 1, h > 4 else { return }

            // --- mismo mapeo tick->x que HighwayLayout, en pixeles 1:1 ---
            // HighwayScene con .resizeFill toma el ANCHO REAL de la vista en
            // `didChangeSize` (`geometry.size = size`), asi que su cabeza de
            // lectura queda en `anchoReal * playheadFraction`, no en el nominal.
            // Como la tira y la autopista comparten columna (mismo `w`), usamos
            // el mismo calculo. `pixelsPerBeat` sí es fijo en las dos.
            let pxPerTick = geometry.pixelsPerTick(ppq: ppq)
            let playheadX = w * geometry.playheadFraction
            let now = tick()
            func x(_ t: Double) -> CGFloat { playheadX + CGFloat(t - now) * pxPerTick }
            // rango de ticks visible en ESTA tira (por su ancho real)
            let tMin = now + Double((0 - playheadX) / pxPerTick)
            let tMax = now + Double((w - playheadX) / pxPerTick)

            // --- onda de la instrumental: cada columna de pixel -> tick ->
            //     fraccion del bucle, con interpolacion lineal entre tramos
            //     (asi no se ve cuadriculada) y color por frecuencia ---
            let count = wave.levels.count
            if count > 1 {
                let half = h / 2
                let denom = Double(count)
                var px: CGFloat = 0
                while px <= w {
                    let t = now + Double((px - playheadX) / pxPerTick)
                    var frac = t.truncatingRemainder(dividingBy: loopTicks) / loopTicks
                    if frac < 0 { frac += 1 }
                    let fx = frac * denom
                    let i0 = min(count - 1, max(0, Int(fx)))
                    let i1 = min(count - 1, i0 + 1)
                    let f = CGFloat(fx - Double(i0))
                    let lvl = CGFloat(wave.levels[i0]) * (1 - f) + CGFloat(wave.levels[i1]) * f
                    let amp = lvl * (half - 2)
                    let c0 = wave.colors[i0], c1 = wave.colors[i1]
                    let c = c0 + (c1 - c0) * Float(f)
                    NSColor(srgbRed: CGFloat(c.x), green: CGFloat(c.y), blue: CGFloat(c.z),
                            alpha: 0.9).setStroke()
                    let col = NSBezierPath()
                    col.lineWidth = 1
                    col.move(to: CGPoint(x: px, y: half - amp))
                    col.line(to: CGPoint(x: px, y: half + amp))
                    col.stroke()
                    px += 1
                }
            }

            // --- rejilla: mismas X y misma clasificacion que HighwayLayout ---
            let beatsPerBar = max(1, geometry.beatsPerBar)
            let firstBeat = Int((tMin / Double(ppq)).rounded(.up))
            let lastBeat = Int((tMax / Double(ppq)).rounded(.down))
            if firstBeat <= lastBeat {
                for b in firstBeat...lastBeat {
                    let t = Double(b * ppq)
                    let m = t.truncatingRemainder(dividingBy: Double(patternLen))
                    let beatInPattern = Int(m < 0 ? m + Double(patternLen) : m) / ppq
                    let isBar = beatInPattern % beatsPerBar == 0
                    (isBar ? barLine : beatLine).setStroke()
                    let line = NSBezierPath()
                    line.lineWidth = isBar ? 1.5 : 1
                    let lx = x(t).rounded()
                    line.move(to: CGPoint(x: lx, y: 0))
                    line.line(to: CGPoint(x: lx, y: h))
                    line.stroke()
                }
            }

            // aguja en la cabeza de lectura (misma X absoluta que la autopista)
            playhead.setStroke()
            let n = NSBezierPath()
            let hx = playheadX.rounded()
            n.move(to: CGPoint(x: hx, y: 0))
            n.line(to: CGPoint(x: hx, y: h))
            n.lineWidth = 1
            n.stroke()
        }
    }
}
