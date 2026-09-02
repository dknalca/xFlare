// SPDX-License-Identifier: GPL-3.0-only

import SwiftUI
import AppKit

/// Tira **inferior**: la forma de onda del sample de scratch (con color por
/// frecuencia). Se desplaza bajo una aguja vertical fija a `needleFraction` del
/// ancho, siguiendo dónde está el cabezal del reproductor (`progress`, 0…1).
///
/// Redibuja al **vsync** (`DisplayLinkView`) y la onda va **pre-renderizada** a
/// una imagen: cada frame solo se recorta y desplaza → sin tirones. El sample
/// empieza en el borde izquierdo y acaba en el derecho; nunca hay onda fuera de
/// donde hay sample.
struct WaveformStripView: NSViewRepresentable {

    let wave: WaveformColored.Data
    let progress: () -> Double
    /// Fracción del sample visible a lo ancho (zoom; 1 = todo).
    var visibleFraction: Double = 0.5
    /// Dónde va la aguja (0…1). Alineada con la cabeza de lectura de la autopista.
    var needleFraction: Double = 0.30

    func makeNSView(context: Context) -> StripView {
        let v = StripView()
        apply(to: v)
        v.startLink()
        return v
    }

    func updateNSView(_ nsView: StripView, context: Context) { apply(to: nsView) }

    private func apply(to v: StripView) {
        let changed = v.wave != wave
        v.wave = wave
        v.progress = progress
        v.visibleFraction = CGFloat(min(1, max(0.05, visibleFraction)))
        v.needleFraction = CGFloat(min(0.9, max(0.05, needleFraction)))
        if changed { v.invalidateImage() }
    }

    static func dismantleNSView(_ nsView: StripView, coordinator: ()) { nsView.stopLink() }

    final class StripView: DisplayLinkView {

        var wave = WaveformColored.Data(levels: [], colors: [])
        var progress: () -> Double = { 0 }
        var visibleFraction: CGFloat = 0.5
        var needleFraction: CGFloat = 0.30

        private var image: CGImage?
        private var imageHeight: CGFloat = 0
        private let imgW = 6000

        private let bg = CGColor(srgbRed: 0x11/255, green: 0x14/255, blue: 0x18/255, alpha: 1)
        private let mid = CGColor(srgbRed: 0x2A/255, green: 0x32/255, blue: 0x3B/255, alpha: 1)
        private let needle = CGColor(srgbRed: 0x34/255, green: 0xE1/255, blue: 0xC4/255, alpha: 1)

        func invalidateImage() { image = nil }

        override func render(_ ctx: CGContext, size: CGSize) {
            let w = size.width, h = size.height
            ctx.setFillColor(bg)
            ctx.fill(CGRect(origin: .zero, size: size))
            guard w > 1, h > 4 else { return }

            if image == nil || imageHeight != h {
                image = WaveformImage.render(wave, width: imgW, height: Int(h))
                imageHeight = h
            }

            // linea de reposo
            ctx.setStrokeColor(mid)
            ctx.setLineWidth(1)
            ctx.move(to: CGPoint(x: 0, y: h / 2))
            ctx.addLine(to: CGPoint(x: w, y: h / 2))
            ctx.strokePath()

            let needleX = (w * needleFraction).rounded()

            if let image {
                let p = max(0, min(1, CGFloat(progress())))
                // fraccion del sample en x=0 y en x=w
                let f0 = p - needleFraction * visibleFraction
                // el sample entero (frac 0..1) mapea a este intervalo de pantalla:
                let sx0 = -f0 / visibleFraction * w
                let sw  = w / visibleFraction
                // solo se pinta la parte de pantalla que cae dentro del sample
                let clip = CGRect(x: max(0, sx0), y: 0,
                                  width: min(w, sx0 + sw) - max(0, sx0), height: h)
                if clip.width > 0 {
                    ctx.saveGState()
                    ctx.clip(to: clip)
                    ctx.draw(image, in: CGRect(x: sx0, y: 0, width: sw, height: h))
                    ctx.restoreGState()
                }
            }

            // aguja
            ctx.setStrokeColor(needle)
            ctx.setLineWidth(1.5)
            ctx.move(to: CGPoint(x: needleX, y: 0))
            ctx.addLine(to: CGPoint(x: needleX, y: h))
            ctx.strokePath()
        }
    }
}
