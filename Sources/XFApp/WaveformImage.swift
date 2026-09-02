// SPDX-License-Identifier: GPL-3.0-only

import AppKit
import simd

/// Pre-renderiza una `WaveformColored.Data` a un `CGImage` de un tamaño dado.
/// Se hace **una vez** al cargar el audio; luego `PracticeScene` solo desplaza
/// esa imagen como textura → sin tirones. Interpolación lineal entre tramos.
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
