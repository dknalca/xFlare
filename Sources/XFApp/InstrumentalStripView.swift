// SPDX-License-Identifier: GPL-3.0-only

import SwiftUI
import AppKit
import XFRender

/// Tira **superior**: la onda de la instrumental (en bucle, con color por
/// frecuencia) + la rejilla de compás/negra. Redibuja al **vsync**
/// (`DisplayLinkView`), no por `Timer`, y la onda está **pre-renderizada** a una
/// imagen: cada frame solo la desplaza → sin tirones.
///
/// La X se calcula igual que `HighwayLayout`
/// (`x(tick) = playheadX + (tick - now)·pxPerTick`), en píxeles 1:1. Como la tira
/// y la autopista comparten columna (mismo ancho) y `pixelsPerBeat` es fijo en
/// las dos, un tick cae en la misma X.
struct InstrumentalStripView: NSViewRepresentable {

    let wave: WaveformColored.Data
    /// Duración musical del bucle, en ticks.
    let loopTicks: Double
    /// Geometría de la autopista (la misma instancia que `HighwayView`).
    let geometry: HighwayGeometry
    let ppq: Int
    let patternLengthTicks: Int
    /// "Ahora" en ticks (reloj de la práctica, ya extrapolado).
    let tick: () -> Double

    func makeNSView(context: Context) -> StripView {
        let v = StripView()
        apply(to: v)
        v.startLink()
        return v
    }

    func updateNSView(_ nsView: StripView, context: Context) { apply(to: nsView) }

    private func apply(to v: StripView) {
        let waveChanged = v.wave != wave
        v.wave = wave
        v.loopTicks = max(1, loopTicks)
        v.geometry = geometry
        v.ppq = max(1, ppq)
        v.patternLen = max(1, patternLengthTicks)
        v.tick = tick
        if waveChanged { v.invalidateImage() }
    }

    static func dismantleNSView(_ nsView: StripView, coordinator: ()) { nsView.stopLink() }

    final class StripView: DisplayLinkView {

        var wave = WaveformColored.Data(levels: [], colors: [])
        var loopTicks: Double = 1
        var geometry = HighwayGeometry(size: CGSize(width: 1000, height: 100))
        var ppq: Int = 480
        var patternLen: Int = 1
        var tick: () -> Double = { 0 }

        private var image: CGImage?
        private var imageHeight: CGFloat = 0
        private var imageWidth: CGFloat = 1

        private let bg = CGColor(srgbRed: 0x11/255, green: 0x14/255, blue: 0x18/255, alpha: 1)
        private let beatLine = CGColor(srgbRed: 0x3A/255, green: 0x44/255, blue: 0x4F/255, alpha: 1)
        private let barLine = CGColor(srgbRed: 0x5A/255, green: 0x66/255, blue: 0x74/255, alpha: 1)
        private let playhead = CGColor(srgbRed: 0x34/255, green: 0xE1/255, blue: 0xC4/255, alpha: 0.5)

        func invalidateImage() { image = nil }

        private func rebuildImage(height: CGFloat) {
            let pxPerTick = geometry.pixelsPerTick(ppq: ppq)
            // ancho natural del bucle en px, acotado (una pista larga son
            // decenas de miles de px; suficiente y sin reventar memoria).
            let w = min(80_000, max(1, Int((CGFloat(loopTicks) * pxPerTick).rounded())))
            image = WaveformImage.render(wave, width: w, height: Int(height))
            imageWidth = CGFloat(w)
            imageHeight = height
        }

        override func render(_ ctx: CGContext, size: CGSize) {
            let w = size.width, h = size.height
            ctx.setFillColor(bg)
            ctx.fill(CGRect(origin: .zero, size: size))
            guard w > 1, h > 4 else { return }

            if image == nil || imageHeight != h { rebuildImage(height: h) }

            let pxPerTick = geometry.pixelsPerTick(ppq: ppq)
            let playheadX = w * geometry.playheadFraction
            let now = tick()

            // --- onda: 3 copias de la imagen desplazadas por la fase del bucle ---
            if let image, imageWidth > 1 {
                var phase = now.truncatingRemainder(dividingBy: loopTicks)
                if phase < 0 { phase += loopTicks }
                let imgX = CGFloat(phase) * pxPerTick
                let baseX = playheadX - imgX
                for k in -1...1 {
                    let x = baseX + CGFloat(k) * imageWidth
                    if x + imageWidth < 0 || x > w { continue }
                    ctx.draw(image, in: CGRect(x: x, y: 0, width: imageWidth, height: h))
                }
            }

            // --- rejilla: mismas X y clasificacion que HighwayLayout ---
            let tMin = now + Double((0 - playheadX) / pxPerTick)
            let tMax = now + Double((w - playheadX) / pxPerTick)
            let beatsPerBar = max(1, geometry.beatsPerBar)
            let firstBeat = Int((tMin / Double(ppq)).rounded(.up))
            let lastBeat = Int((tMax / Double(ppq)).rounded(.down))
            if firstBeat <= lastBeat {
                for b in firstBeat...lastBeat {
                    let t = Double(b * ppq)
                    let m = t.truncatingRemainder(dividingBy: Double(patternLen))
                    let beatInPattern = Int(m < 0 ? m + Double(patternLen) : m) / ppq
                    let isBar = beatInPattern % beatsPerBar == 0
                    let lx = (playheadX + CGFloat(t - now) * pxPerTick).rounded()
                    ctx.setStrokeColor(isBar ? barLine : beatLine)
                    ctx.setLineWidth(isBar ? 1.5 : 1)
                    ctx.move(to: CGPoint(x: lx, y: 0))
                    ctx.addLine(to: CGPoint(x: lx, y: h))
                    ctx.strokePath()
                }
            }

            // --- aguja en la cabeza de lectura (misma X que la autopista) ---
            ctx.setStrokeColor(playhead)
            ctx.setLineWidth(1)
            ctx.move(to: CGPoint(x: playheadX.rounded(), y: 0))
            ctx.addLine(to: CGPoint(x: playheadX.rounded(), y: h))
            ctx.strokePath()
        }
    }
}
