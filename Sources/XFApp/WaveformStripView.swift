// SPDX-License-Identifier: GPL-3.0-only

import SwiftUI
import AppKit

/// Tira inferior con la **forma de onda del sample de scratch**: se desplaza bajo
/// una línea vertical fija (centrada), como el visor de un DVS, siguiendo dónde
/// está el cabezal del reproductor. `progress` es 0…1 sobre el sample; la vista
/// se redibuja a ~60 Hz leyéndolo.
struct WaveformStripView: NSViewRepresentable {

    let envelope: [Float]
    let progress: () -> Double
    /// `true` = fader cerrado: no está sonando, la onda y la aguja se apagan.
    var muted: Bool = false
    /// Fracción del sample visible a lo ancho de la tira (zoom).
    var visibleFraction: Double = 0.5
    /// Dónde va la aguja (0…1). Alineada con la cabeza de lectura de la autopista.
    var needleFraction: Double = 0.30

    func makeNSView(context: Context) -> StripView {
        let v = StripView()
        apply(to: v)
        v.startTicking()
        return v
    }

    func updateNSView(_ nsView: StripView, context: Context) { apply(to: nsView) }

    private func apply(to v: StripView) {
        v.envelope = envelope
        v.progress = progress
        v.muted = muted
        v.visibleFraction = CGFloat(visibleFraction)
        v.needleFraction = CGFloat(min(0.9, max(0.05, needleFraction)))
    }

    static func dismantleNSView(_ nsView: StripView, coordinator: ()) {
        nsView.stopTicking()
    }

    /// El `NSView` de verdad: dibuja la onda y la aguja, y se refresca por timer.
    final class StripView: NSView {

        var envelope: [Float] = []
        var progress: () -> Double = { 0 }
        var muted = false
        var visibleFraction: CGFloat = 0.5
        var needleFraction: CGFloat = 0.30

        private var timer: Timer?

        // paleta (docs/UI_DESIGN.md §2), aquí como NSColor
        private let bg = NSColor(srgbRed: 0x11/255, green: 0x14/255, blue: 0x18/255, alpha: 1)
        private let wave = NSColor(srgbRed: 0x7A/255, green: 0x87/255, blue: 0x94/255, alpha: 0.9)
        private let needle = NSColor(srgbRed: 0x34/255, green: 0xE1/255, blue: 0xC4/255, alpha: 1)
        private let mid = NSColor(srgbRed: 0x2A/255, green: 0x32/255, blue: 0x3B/255, alpha: 1)

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
            guard w > 1, h > 4, envelope.count > 1 else {
                drawNeedle(w: w, h: h); return
            }

            let p = max(0, min(1, CGFloat(progress())))
            let half = h / 2
            let count = CGFloat(envelope.count)

            // línea de reposo
            mid.setStroke()
            let axis = NSBezierPath()
            axis.move(to: CGPoint(x: 0, y: half))
            axis.line(to: CGPoint(x: w, y: half))
            axis.lineWidth = 1
            axis.stroke()

            // onda: por cada columna de píxel, mapea a una fracción del sample.
            // fader cerrado (muted) -> la onda se apaga.
            (muted ? wave.withAlphaComponent(0.22) : wave).setStroke()
            let path = NSBezierPath()
            path.lineWidth = 1
            var x: CGFloat = 0
            while x <= w {
                let frac = p + (x / w - needleFraction) * visibleFraction
                if frac >= 0, frac < 1 {
                    let idx = min(envelope.count - 1, Int(frac * count))
                    let amp = CGFloat(envelope[idx]) * (half - 2)
                    path.move(to: CGPoint(x: x, y: half - amp))
                    path.line(to: CGPoint(x: x, y: half + amp))
                }
                x += 1
            }
            path.stroke()

            drawNeedle(w: w, h: h)
        }

        private func drawNeedle(w: CGFloat, h: CGFloat) {
            (muted ? needle.withAlphaComponent(0.3) : needle).setStroke()
            let n = NSBezierPath()
            n.move(to: CGPoint(x: w / 2, y: 0))
            n.line(to: CGPoint(x: w / 2, y: h))
            n.lineWidth = 1.5
            n.stroke()
        }
    }
}
