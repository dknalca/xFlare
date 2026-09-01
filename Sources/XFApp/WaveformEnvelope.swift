// SPDX-License-Identifier: GPL-3.0-only

import Foundation

/// Reduce un PCM mono a una **envolvente** de pico absoluto por tramo,
/// normalizada a `0…1`. Es lo que dibuja `WaveformStripView` (la forma de onda
/// del sample de scratch). Puro y testeable.
public enum WaveformEnvelope {

    /// - Parameters:
    ///   - pcm: muestras mono.
    ///   - buckets: cuántos puntos tiene la envolvente resultante.
    public static func build(_ pcm: [Float], buckets: Int = 1_400) -> [Float] {
        let n = pcm.count
        let b = max(1, buckets)
        guard n > 0 else { return [] }

        var env = [Float](repeating: 0, count: b)
        var peak: Float = 0
        for i in 0..<b {
            let lo = i * n / b
            let hi = max(lo + 1, (i + 1) * n / b)
            var m: Float = 0
            var j = lo
            while j < hi && j < n {
                let a = abs(pcm[j])
                if a > m { m = a }
                j += 1
            }
            env[i] = m
            if m > peak { peak = m }
        }
        if peak > 1e-6 {
            let inv = 1 / peak
            for i in 0..<b { env[i] *= inv }
        }
        return env
    }
}
