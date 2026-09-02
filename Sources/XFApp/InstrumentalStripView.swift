// SPDX-License-Identifier: GPL-3.0-only

import SwiftUI
import AppKit
import XFRender

/// Tira **superior** con la forma de onda de la instrumental (en bucle) y la
/// rejilla de compás/negra. Se desplaza al mismo ritmo que la autopista y sus
/// líneas de compás caen en la **misma X** que las de la autopista: se dibuja
/// con la misma geometría (`HighwayGeometry`) y el mismo mapeo tick→x que
/// `HighwayLayout`, y como la escena de la autopista y esta tira ocupan la misma
/// columna (mismo ancho), la escala nominal→pantalla es idéntica en las dos.
///
/// No es XFRender (que está SELLADO): es una vista de XFApp que **replica** el
/// trozo de geometría que necesita. La duplicación es unas pocas líneas y está
/// acotada aquí; es preferible a re-sellar XFRender por esto.
struct InstrumentalStripView: NSViewRepresentable {

    /// Envolvente de amplitud del bucle entero (0…1), como la de `WaveformStripView`.
    let envelope: [Float]
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
        v.envelope = envelope
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

        var envelope: [Float] = []
        var loopTicks: Double = 1
        var geometry = HighwayGeometry(size: CGSize(width: 1000, height: 100))
        var ppq: Int = 480
        var patternLen: Int = 1
        var tick: () -> Double = { 0 }

        private var timer: Timer?

        // paleta (docs/UI_DESIGN.md §2)
        private let bg = NSColor(srgbRed: 0x11/255, green: 0x14/255, blue: 0x18/255, alpha: 1)
        private let wave = NSColor(srgbRed: 0x7A/255, green: 0x87/255, blue: 0x94/255, alpha: 0.75)
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

            // --- mismo mapeo tick->x que HighwayLayout, escalado nominal->pantalla ---
            let nominalW = max(1, geometry.size.width)
            let scale = w / nominalW
            let pxPerTick = geometry.pixelsPerTick(ppq: ppq)          // nominal
            let playheadXNom = geometry.playheadX                     // nominal
            let now = tick()
            func xAct(_ t: Double) -> CGFloat {
                (playheadXNom + CGFloat(t - now) * pxPerTick) * scale
            }
            let tMin = now + Double((-playheadXNom) / pxPerTick)
            let tMax = now + Double((nominalW - playheadXNom) / pxPerTick)

            // --- onda de la instrumental: cada columna de píxel -> tick -> fracción del bucle ---
            let count = envelope.count
            if count > 1 {
                wave.setStroke()
                let path = NSBezierPath()
                path.lineWidth = 1
                let half = h / 2
                var x: CGFloat = 0
                while x <= w {
                    let t = now + Double((x / scale - playheadXNom) / pxPerTick)
                    var frac = t.truncatingRemainder(dividingBy: loopTicks) / loopTicks
                    if frac < 0 { frac += 1 }
                    let idx = min(count - 1, max(0, Int(frac * Double(count))))
                    let amp = CGFloat(envelope[idx]) * (half - 2)
                    path.move(to: CGPoint(x: x, y: half - amp))
                    path.line(to: CGPoint(x: x, y: half + amp))
                    x += 1
                }
                path.stroke()
            }

            // --- rejilla: mismas X y misma clasificación que HighwayLayout ---
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
                    let px = xAct(t).rounded()
                    line.move(to: CGPoint(x: px, y: 0))
                    line.line(to: CGPoint(x: px, y: h))
                    line.stroke()
                }
            }

            // aguja en la cabeza de lectura (misma fracción que la autopista)
            playhead.setStroke()
            let n = NSBezierPath()
            let hx = (playheadXNom * scale).rounded()
            n.move(to: CGPoint(x: hx, y: 0))
            n.line(to: CGPoint(x: hx, y: h))
            n.lineWidth = 1
            n.stroke()
        }
    }
}
