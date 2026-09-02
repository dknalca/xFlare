// SPDX-License-Identifier: GPL-3.0-only

import Foundation

/// Estima el tempo y la fase (dónde cae el primer golpe fuerte) de un trozo de
/// audio. Análisis **offline** al cargar la instrumental: así la rejilla de
/// compás cae sobre los golpes de verdad y no sobre un 4/4 nominal.
///
/// - Tempo: envolvente de onset (flujo de energía positivo) → autocorrelación,
///   ponderada por un **prior** de tempo (gaussiana en log2 centrada en 120 BPM,
///   como Ellis 2007) para resolver la ambigüedad de octava.
/// - Fase: correlación de la envolvente con un tren de pulsos al periodo hallado.
/// - Si el llamante pasa `hintBPM` (p. ej. sacado del nombre del fichero,
///   `080bpm_beat.wav`), se usa ese tempo y el análisis solo busca la fase.
public enum TempoAnalyzer {

    public struct Result: Equatable, Sendable {
        public var bpm: Double
        /// Frame del primer golpe fuerte (para rotar el PCM y empezar en el "1").
        public var phaseFrames: Int
        /// `true` si el audio es un bucle **corto** que dura ~un número entero de
        /// negras (se cuadró el BPM). `false` para pistas largas.
        public var isShortLoop: Bool
        /// Negras que dura el audio (redondeado). Unidad de bucle para la tira.
        public var beats: Int
    }

    /// Saca un BPM de un nombre de fichero tipo `080bpm_beat.wav` o `120 BPM`.
    public static func bpmHint(fromFilename name: String) -> Double? {
        let lower = name.lowercased()
        guard let r = lower.range(of: #"(\d{2,3})\s*bpm"#, options: .regularExpression) else { return nil }
        let digits = lower[r].prefix { $0.isNumber }
        guard let v = Double(digits), (40...300).contains(v) else { return nil }
        return v
    }

    public static func analyze(_ pcm: [Float], sampleRate: Double,
                               hintBPM: Double? = nil,
                               minBPM: Double = 60, maxBPM: Double = 200) -> Result? {
        guard sampleRate > 0, pcm.count > Int(sampleRate) else { return nil }

        let hop = 512
        let nFrames = pcm.count / hop
        guard nFrames > 32 else { return nil }

        // --- envolvente de onset ---
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

        let envRate = sampleRate / Double(hop)

        // --- tempo ---
        var bpm: Double
        if let h = hintBPM, (minBPM...maxBPM).contains(h) {
            bpm = h
        } else {
            let minLag = max(1, Int((60.0 / maxBPM) * envRate))
            let maxLag = min(nFrames / 2, Int((60.0 / minBPM) * envRate))
            guard maxLag > minLag + 1 else { return nil }

            var bestLag = minLag
            var bestScore = -1.0
            for lag in minLag...maxLag {
                var s = 0.0
                for i in 0..<(nFrames - lag) { s += env[i] * env[i + lag] }
                s /= Double(nFrames - lag)
                // prior de tempo: gaussiana en log2 centrada en 120 BPM (Ellis)
                let cand = 60.0 * envRate / Double(lag)
                let z = log2(cand / 120.0) / 1.0
                let prior = exp(-0.5 * z * z)
                let score = s * prior
                if score > bestScore { bestScore = score; bestLag = lag }
            }
            bpm = 60.0 * envRate / Double(bestLag)
        }

        // --- fase: offset que maximiza la energía de onset en las negras ---
        let periodFrames = 60.0 / bpm * envRate
        let searchN = max(1, Int(periodFrames.rounded()))
        var bestPhase = 0
        var bestPhaseScore = -1.0
        for p in 0..<searchN {
            var s = 0.0
            var k = 0.0
            while true {
                let idx = Int((Double(p) + k * periodFrames).rounded())
                if idx >= nFrames { break }
                s += env[idx]; k += 1
            }
            if s > bestPhaseScore { bestPhaseScore = s; bestPhase = p }
        }

        // --- cuadrar SOLO bucles cortos (<= 16 s) que duran ~n negras exactas ---
        let loopSec = Double(pcm.count) / sampleRate
        let rawBeats = loopSec * bpm / 60.0
        let beatsRounded = max(1, Int(rawBeats.rounded()))
        var isShortLoop = false
        if hintBPM == nil, loopSec <= 16.0, abs(rawBeats - Double(beatsRounded)) < 0.06 {
            bpm = Double(beatsRounded) * 60.0 / loopSec
            isShortLoop = true
        }

        return Result(bpm: bpm,
                      phaseFrames: min(pcm.count - 1, max(0, bestPhase * hop)),
                      isShortLoop: isShortLoop,
                      beats: beatsRounded)
    }
}
