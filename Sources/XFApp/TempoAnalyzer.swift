// SPDX-License-Identifier: GPL-3.0-only

import Foundation

/// Estima el tempo y la fase (dónde cae el "1") de un trozo de audio. Análisis
/// **offline** al cargar la instrumental: así la rejilla de compás cae sobre los
/// golpes de verdad y no sobre un 4/4 nominal.
///
/// - Onset: flux **multibanda** (grave / medio / agudo por filtros de un polo),
///   suma de las subidas de energía RMS log-comprimida de cada banda. Coge el
///   bombo, la caja y el charles, que suben en bandas distintas (idea de los
///   detectores tipo Serato/Traktor, sin llegar a la FFT por banda de octava).
/// - Tempo: autocorrelación con **suma armónica** (premia el periodo cuyos
///   múltiplos también correlacionan → la negra, no su mitad ni su doble) y un
///   **prior** gaussiano en log2 centrado en 120 BPM (Ellis 2007). Interpolación
///   parabólica del pico para BPM sub-lag. Si el nombre del fichero trae un BPM
///   (`080bpm_beat.wav`), se usa ese y sólo se busca la fase.
/// - Fase: mejor offset de **negra** por correlación con un tren de pulsos. NO se
///   intenta el downbeat (qué negra es el "1"): con energía broadband el snare
///   pesa más que el bombo y la estimación bailaba al backbeat. La rejilla cae
///   sobre los golpes; que la línea de compás caiga en el 1 exacto es un refino
///   futuro (haría falta separar por bandas).
public enum TempoAnalyzer {

    public struct Result: Equatable, Sendable {
        public var bpm: Double
        /// Frame del primer golpe fuerte (para rotar el PCM y empezar en el "1").
        public var phaseFrames: Int
        /// `true` si el audio es un bucle **corto** que dura ~un número entero de
        /// negras (se cuadró el BPM). `false` para pistas largas.
        public var isShortLoop: Bool
        /// Negras que dura el audio (redondeado).
        public var beats: Int
    }

    /// Saca un BPM de un nombre tipo `080bpm_beat.wav` o `track 120 BPM`.
    public static func bpmHint(fromFilename name: String) -> Double? {
        let lower = name.lowercased()
        guard let r = lower.range(of: #"(\d{2,3})\s*bpm"#, options: .regularExpression) else { return nil }
        let digits = lower[r].prefix { $0.isNumber }
        guard let v = Double(digits), (40...300).contains(v) else { return nil }
        return v
    }

    public static func analyze(_ pcm: [Float], sampleRate: Double,
                               hintBPM: Double? = nil,
                               minBPM: Double = 60, maxBPM: Double = 200,
                               preferredRange: ClosedRange<Double> = 70...140) -> Result? {
        guard sampleRate > 0, pcm.count > Int(sampleRate) else { return nil }

        let hop = 256
        let nFrames = pcm.count / hop
        guard nFrames > 64 else { return nil }

        // --- envolvente de onset MULTIBANDA (mas cerca de Serato/Traktor que un
        // flux broadband: el bombo, la caja y el charles suben de energia en
        // bandas distintas; sumando el flux de cada banda se cogen los tres). ---
        // Tres bandas por filtros de un polo: grave (< ~160 Hz), agudo (> ~4 kHz)
        // y medio (el resto).
        let sr = sampleRate
        func onePoleCoef(_ hz: Double) -> Double { exp(-2.0 * Double.pi * hz / sr) }
        let aLow = onePoleCoef(160), aHigh = onePoleCoef(4000)
        var lp = 0.0, lpH = 0.0
        var band = [[Double]](repeating: [Double](repeating: 0, count: nFrames), count: 3)
        for f in 0..<nFrames {
            let base = f * hop
            var eLo = 0.0, eMid = 0.0, eHi = 0.0
            for i in 0..<hop {
                let s = Double(pcm[base + i])
                lp = (1 - aLow) * s + aLow * lp             // grave
                lpH = (1 - aHigh) * s + aHigh * lpH         // corte para agudo
                let hi = s - lpH                            // agudo = lo que pasa de 4 kHz
                let mid = s - lp - hi                       // medio = resto
                eLo += lp * lp; eMid += mid * mid; eHi += hi * hi
            }
            let inv = 1.0 / Double(hop)
            band[0][f] = log(1.0 + 1000.0 * (eLo * inv).squareRoot())
            band[1][f] = log(1.0 + 1000.0 * (eMid * inv).squareRoot())
            band[2][f] = log(1.0 + 1000.0 * (eHi * inv).squareRoot())
        }
        // flux por banda (subida, rectificada) y suma
        var env = [Double](repeating: 0, count: nFrames)
        for b in 0..<3 {
            var prev = band[b][0]
            for f in 1..<nFrames {
                env[f] += max(0, band[b][f] - prev)
                prev = band[b][f]
            }
        }
        // suavizado 3-tap simetrico (quita ruido sin desplazar los transitorios)
        if nFrames > 3 {
            var sm = env
            for i in 1..<(nFrames - 1) { sm[i] = 0.25 * env[i - 1] + 0.5 * env[i] + 0.25 * env[i + 1] }
            env = sm
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
            guard maxLag > minLag + 2 else { return nil }

            var ac = [Double](repeating: 0, count: maxLag + 1)
            for lag in minLag...maxLag {
                var s = 0.0
                for i in 0..<(nFrames - lag) { s += env[i] * env[i + lag] }
                ac[lag] = s / Double(nFrames - lag)
            }

            var bestLag = minLag
            var bestScore = -1.0
            for lag in minLag...maxLag {
                // suma armonica: la negra "de verdad" correlaciona tambien en 2x y 3x
                var comb = ac[lag]
                if 2 * lag <= maxLag { comb += 0.5 * ac[2 * lag] }
                if 3 * lag <= maxLag { comb += 0.33 * ac[3 * lag] }
                let cand = 60.0 * envRate / Double(lag)
                let z = log2(cand / 120.0)
                let prior = exp(-0.5 * z * z)          // sigma 1 octava
                let score = comb * prior
                if score > bestScore { bestScore = score; bestLag = lag }
            }

            // interpolacion parabolica del pico -> BPM sub-lag
            var refined = Double(bestLag)
            if bestLag > minLag, bestLag < maxLag {
                let a = ac[bestLag - 1], b = ac[bestLag], c = ac[bestLag + 1]
                let denom = a - 2 * b + c
                if abs(denom) > 1e-12 {
                    let d = 0.5 * (a - c) / denom
                    if abs(d) < 1 { refined = Double(bestLag) + d }
                }
            }
            bpm = 60.0 * envRate / refined
        }

        // --- plegar a un rango razonable (por defecto 70..140) ---
        // Un tempo detectado a doble/mitad -180 en vez de 90- se dobla o parte
        // hasta caer en el rango. Con un 2 % de margen para no plegar algo que
        // cae justo en el borde (139-142 se queda). Si venia por nombre de
        // fichero (hint), se respeta tal cual. Se hace ANTES de la fase para que
        // todo lo de abajo (periodo, negras) use ya el BPM plegado.
        if hintBPM == nil {
            while bpm > preferredRange.upperBound * 1.02 { bpm /= 2 }
            while bpm < preferredRange.lowerBound / 1.02 { bpm *= 2 }
        }

        // --- fase de negra ---
        // Comb: para cada offset `p` (en env-frames) se suma la envolvente en
        // `p, p+period, p+2·period, …`; el `p` que mas suma es la fase de negra.
        let period = 60.0 / bpm * envRate
        let searchN = max(1, Int(period.rounded()))
        func combScore(_ p: Double) -> Double {
            var s = 0.0
            var x = p
            while x < Double(nFrames) - 1 {
                let i = Int(x)
                let fr = x - Double(i)
                s += env[i] * (1 - fr) + env[i + 1] * fr     // interp lineal
                x += period
            }
            return s
        }
        var beatPhase = 0
        var beatScore = -1.0
        for p in 0..<searchN {
            let s = combScore(Double(p))
            if s > beatScore { beatScore = s; beatPhase = p }
        }
        // refino sub-frame por parabola alrededor del mejor `p`
        var refined = Double(beatPhase)
        if searchN > 2 {
            let a = combScore(Double((beatPhase - 1 + searchN) % searchN))
            let b = beatScore
            let c = combScore(Double((beatPhase + 1) % searchN))
            let denom = a - 2 * b + c
            if abs(denom) > 1e-12 {
                let d = 0.5 * (a - c) / denom
                if abs(d) < 1 { refined = Double(beatPhase) + d }
            }
        }
        // La envolvente de flux marca el bloque donde SUBE la energia; el golpe
        // real cae hacia el centro de ese bloque -> medio hop mas tarde. (El
        // usuario tenia la rejilla adelantada respecto a los golpes.)
        let phaseFrames = min(pcm.count - 1, max(0, Int((refined * Double(hop)).rounded()) + hop / 2))

        // --- cuadrar SOLO bucles cortos (<= 16 s) con ~n negras exactas ---
        let loopSec = Double(pcm.count) / sampleRate
        let rawBeats = loopSec * bpm / 60.0
        let beatsRounded = max(1, Int(rawBeats.rounded()))
        var isShortLoop = false
        if hintBPM == nil, loopSec <= 16.0, abs(rawBeats - Double(beatsRounded)) < 0.06 {
            bpm = Double(beatsRounded) * 60.0 / loopSec
            isShortLoop = true
        }

        return Result(bpm: bpm, phaseFrames: phaseFrames,
                      isShortLoop: isShortLoop, beats: beatsRounded)
    }
}
