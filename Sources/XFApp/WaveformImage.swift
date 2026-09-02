// SPDX-License-Identifier: GPL-3.0-only

import AppKit
import CoreVideo
import simd

/// Pre-renderiza una `WaveformColored.Data` a un `CGImage` de un tamaño dado.
/// Se hace **una vez** al cargar el audio; luego las tiras solo desplazan la
/// imagen cada frame (barato → sin tirones). Interpolación lineal entre tramos.
enum WaveformImage {

    static func render(_ data: WaveformColored.Data, width: Int, height: Int) -> CGImage? {
        let w = max(1, width), h = max(2, height)
        let count = data.levels.count
        guard count > 1 else { return nil }

        guard let ctx = CGContext(
            data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }

        ctx.setLineWidth(1)
        ctx.setLineCap(.round)
        let half = Double(h) / 2
        let denom = Double(count)
        for px in 0..<w {
            let fx = (Double(px) + 0.5) / Double(w) * denom
            let i0 = min(count - 1, max(0, Int(fx)))
            let i1 = min(count - 1, i0 + 1)
            let f = Float(fx - Double(i0))
            let lvl = Double(data.levels[i0] * (1 - f) + data.levels[i1] * f)
            let c = data.colors[i0] + (data.colors[i1] - data.colors[i0]) * f
            let amp = lvl * (half - 1)
            ctx.setStrokeColor(red: CGFloat(c.x), green: CGFloat(c.y), blue: CGFloat(c.z), alpha: 0.92)
            ctx.move(to: CGPoint(x: Double(px) + 0.5, y: half - amp))
            ctx.addLine(to: CGPoint(x: Double(px) + 0.5, y: half + amp))
            ctx.strokePath()
        }
        return ctx.makeImage()
    }
}

/// Un `NSView` que se redibuja **al ritmo del vsync** (`CVDisplayLink`), no por
/// `Timer`. Las subclases implementan `render(_:)`; el ciclo de vida del display
/// link lo lleva esta clase.
class DisplayLinkView: NSView {

    private var link: CVDisplayLink?

    override var isFlipped: Bool { true }

    func startLink() {
        guard link == nil else { return }
        var dl: CVDisplayLink?
        CVDisplayLinkCreateWithActiveCGDisplays(&dl)
        guard let dl else { return }
        CVDisplayLinkSetOutputHandler(dl) { [weak self] _, _, _, _, _ in
            DispatchQueue.main.async { self?.needsDisplay = true }
            return kCVReturnSuccess
        }
        CVDisplayLinkStart(dl)
        link = dl
    }

    func stopLink() {
        if let dl = link { CVDisplayLinkStop(dl) }
        link = nil
    }

    deinit { stopLink() }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        render(ctx, size: bounds.size)
    }

    /// A implementar por la subclase. `ctx` ya está listo; `size` en puntos.
    func render(_ ctx: CGContext, size: CGSize) {}
}
