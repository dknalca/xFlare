// SPDX-License-Identifier: GPL-3.0-only

import Foundation
import simd

/// Envolvente de amplitud + **color por frecuencia** de un PCM mono, para pintar
/// la onda tipo Serato: graves cálidos, medios verdes, agudos azules. Análisis
/// offline (al cargar la instrumental). Sin dependencias: 3 biquads.
public enum WaveformColored {

    public struct Data: Equatable, Sendable {
        /// Amplitud por tramo, 0…1.
        public var levels: [Float]
        /// Color por tramo (RGB 0…1): mezcla de energía grave/media/aguda.
        public var colors: [SIMD3<Float>]
        public var isEmpty: Bool { levels.isEmpty }
    }

    /// - buckets: cuántos puntos tiene el resultado. Más = onda más fina.
    public static func build(_ pcm: [Float], sampleRate: Double,
                             buckets: Int = 8_000) -> Data {
        let n = pcm.count
        let b = max(1, buckets)
        guard n > 4, sampleRate > 0 else { return Data(levels: [], colors: []) }

        // separa en 3 bandas: LP 180 Hz, HP 2200 Hz, medios = resto
        let low  = biquadLowpass(pcm, cutoff: 180,  sr: sampleRate)
        let high = biquadHighpass(pcm, cutoff: 2200, sr: sampleRate)

        var levels = [Float](repeating: 0, count: b)
        var bandRMS = [SIMD3<Float>](repeating: .zero, count: b)
        for i in 0..<b {
            let lo = i * n / b
            let hi = max(lo + 1, (i + 1) * n / b)
            var eAll: Float = 0, eLo: Float = 0, eHi: Float = 0
            var j = lo
            while j < hi && j < n {
                let s = pcm[j], l = low[j], h = high[j]
                let m = s - l - h                      // medios ~ crossover
                eAll += s * s
                eLo  += l * l
                eHi  += h * h
                bandRMS[i].y += m * m
                j += 1
            }
            let count = Float(max(1, hi - lo))
            levels[i]     = (eAll / count).squareRoot()
            bandRMS[i].x  = (eLo  / count).squareRoot()
            bandRMS[i].z  = (eHi  / count).squareRoot()
            bandRMS[i].y  = (bandRMS[i].y / count).squareRoot()
        }

        // normaliza la amplitud
        let lMax = levels.max() ?? 0
        if lMax > 1e-9 { for i in 0..<b { levels[i] /= lMax } }

        // normaliza cada banda por su propio máximo y compón el color
        var maxBand = SIMD3<Float>(repeating: 1e-9)
        for v in bandRMS { maxBand = simd_max(maxBand, v) }
        var colors = [SIMD3<Float>](repeating: .zero, count: b)
        for i in 0..<b {
            let nrm = bandRMS[i] / maxBand                 // 0…1 por banda
            let sum = nrm.x + nrm.y + nrm.z + 1e-6
            // paleta: grave -> naranja cálido, medio -> verde, agudo -> azul
            let warm  = SIMD3<Float>(0.95, 0.55, 0.25)
            let green = SIMD3<Float>(0.35, 0.80, 0.45)
            let blue  = SIMD3<Float>(0.35, 0.65, 0.95)
            let c = (warm * nrm.x + green * nrm.y + blue * nrm.z) / sum
            colors[i] = simd_clamp(c, .zero, .one)
        }
        return Data(levels: levels, colors: colors)
    }

    // MARK: - biquads RBJ (2º orden), forma directa I

    private static func biquadLowpass(_ x: [Float], cutoff: Double, sr: Double) -> [Float] {
        let w0 = 2 * Double.pi * min(cutoff, sr * 0.45) / sr
        let cw = cos(w0), sw = sin(w0)
        let alpha = sw / (2 * 0.707)
        let b1 = 1 - cw
        let (b0, b2) = (b1 / 2, b1 / 2)
        let a0 = 1 + alpha, a1 = -2 * cw, a2 = 1 - alpha
        return applyBiquad(x, b0 / a0, b1 / a0, b2 / a0, a1 / a0, a2 / a0)
    }

    private static func biquadHighpass(_ x: [Float], cutoff: Double, sr: Double) -> [Float] {
        let w0 = 2 * Double.pi * min(cutoff, sr * 0.45) / sr
        let cw = cos(w0), sw = sin(w0)
        let alpha = sw / (2 * 0.707)
        let b0 = (1 + cw) / 2, b1 = -(1 + cw), b2 = (1 + cw) / 2
        let a0 = 1 + alpha, a1 = -2 * cw, a2 = 1 - alpha
        return applyBiquad(x, b0 / a0, b1 / a0, b2 / a0, a1 / a0, a2 / a0)
    }

    private static func applyBiquad(_ x: [Float], _ b0: Double, _ b1: Double, _ b2: Double,
                                    _ a1: Double, _ a2: Double) -> [Float] {
        var y = [Float](repeating: 0, count: x.count)
        var x1 = 0.0, x2 = 0.0, y1 = 0.0, y2 = 0.0
        for i in 0..<x.count {
            let xn = Double(x[i])
            let yn = b0 * xn + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2
            y[i] = Float(yn)
            x2 = x1; x1 = xn
            y2 = y1; y1 = yn
        }
        return y
    }
}
