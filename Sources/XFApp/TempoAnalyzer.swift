// SPDX-License-Identifier: GPL-3.0-only

import Foundation

/// Estima el tempo y la fase (dónde cae el primer golpe fuerte) de un trozo de
/// audio. Es análisis **offline** al cargar la instrumental: así la rejilla de
/// compás cae sobre los golpes de verdad y no sobre un 4/4 nominal.
///
/// Método clásico y sin dependencias: envolvente de onset (flujo de energía
/// positivo) → autocorrelación para el periodo de negra → correlación con un
/// tren de pulsos para la fase. Para bucles limpios (una batería) es de sobra.
public enum TempoAnalyzer {

    public struct Result: Equatable, Sendable {
        /// Pulsos por minuto detectados (ya cuadrados al bucle si encajaba).
        public var bpm: Double
        /// Frame del primer golpe fuerte del bucle (para rotar el PCM y que
        /// empiece en el "1").
        public var phaseFrames: Int
        /// Cuántas negras dura el bucle (redondeado).
        public var beatsInLoop: Int
    }

    /// - Parameters:
    ///   - pcm: audio mono.
    ///   - sampleRate: Hz.
    ///   - minBPM/maxBPM: rango de búsqueda (evita el error de octava).
    /// Devuelve `nil` si el audio es muy corto o no tiene onsets.
    public static func analyze(_ pcm: [Float], sampleRate: Double,
                               minBPM: Double = 70, maxBPM: Double = 170) -> Result? {
        guard sampleRate > 0, pcm.count > Int(sampleRate) else { return nil }

        let hop = 512
        let nFrames = pcm.count / hop
        guard nFrames > 32 else { return nil }

        // --- envolvente de onset: subida de energía RMS entre frames ---
        var env = [Double](repeating: 0, count: nFrames)
        var prevRMS = 0.0
        for f in 0..<nFrames {
            let base = f * hop
            var e = 0.0
            for i in 0..<hop { let s = Double(pcm[base + i]); e += s * s }
            let rms = (e / Double(hop)).squareRoot()
            env[f] = max(0, rms - prevRMS)
            prevRMS = rms
        }
        let envMax = env.max() ?? 0
        guard envMax > 1e-9 else { return nil }
        for i in env.indices { env[i] /= envMax }

        let envRate = sampleRate / Double(hop)          // frames/seg de la envolvente

        // --- autocorrelación en el rango de tempo ---
        let minLag = max(1, Int((60.0 / maxBPM) * envRate))
        let maxLag = min(nFrames / 2, Int((60.0 / minBPM) * envRate))
        guard maxLag > minLag else { return nil }

        var bestLag = minLag
        var bestScore = -1.0
        for lag in minLag...maxLag {
            var s = 0.0
            for i in 0..<(nFrames - lag) { s += env[i] * env[i + lag] }
            s /= Double(nFrames - lag)
            // sesgo suave hacia tempos medios: rebaja el error de octava
            let bpm = 60.0 * envRate / Double(lag)
            let bias = 1.0 - 0.15 * abs(log2(bpm / 120.0))
            let score = s * max(0.5, bias)
            if score > bestScore { bestScore = score; bestLag = lag }
        }

        var bpm = 60.0 * envRate / Double(bestLag)

        // --- cuadrar al bucle: si dura ~un número entero de negras, forzar ---
        let loopSec = Double(pcm.count) / sampleRate
        let beats = loopSec * bpm / 60.0
        let beatsRounded = max(1, Int(beats.rounded()))
        if abs(beats - Double(beatsRounded)) < 0.15 {
            bpm = Double(beatsRounded) * 60.0 / loopSec
        }

        // --- fase: offset que maximiza la energía de onset en las negras ---
        let periodFrames = 60.0 / bpm * envRate
        let searchN = max(1, Int(periodFrames.rounded()))
        var bestPhase = 0
        var bestPhaseScore = -1.0
        for p in 0..<searchN {
            var s = 0.0
            var k = 0
            while true {
                let idx = Int((Double(p) + Double(k) * periodFrames).rounded())
                if idx >= nFrames { break }
                s += env[idx]
                k += 1
            }
            if s > bestPhaseScore { bestPhaseScore = s; bestPhase = p }
        }

        return Result(bpm: bpm,
                      phaseFrames: min(pcm.count - 1, bestPhase * hop),
                      beatsInLoop: beatsRounded)
    }
}
