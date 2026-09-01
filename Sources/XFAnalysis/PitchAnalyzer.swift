// SPDX-License-Identifier: GPL-3.0-only

import XFClock
import XFNotation

/// Contorno de tono (B8.2). El tono lo da la **velocidad** del disco; se evalua
/// su forma, no su valor absoluto (afinacion relativa, ADR-005): ambos contornos
/// se normalizan por su maximo antes de comparar.
enum PitchAnalyzer {

    struct Result {
        /// Distancia DTW normalizada de los dos contornos (0 = identico).
        let dtwDistance: Double
        /// Puntos (0..100) por cada punto de control (semicorchea).
        let checkpointScores: [Int]
    }

    /// Un punto de control por semicorchea (`ppq/4`), igual que cuenta `pitch`
    /// en `ScoreEvents`.
    static func checkpointTicks(of scratch: Scratch, ppq: Int = XFClock.ppq) -> [Tick] {
        let step = max(1, ppq / 4)
        return Array(stride(from: 0, to: max(step, scratch.lengthTicks), by: step))
    }

    /// Velocidad objetivo en un tick: derivada numerica de la curva de posicion.
    static func targetVelocity(of scratch: Scratch, atTick t: Tick, h: Tick = 20) -> Double {
        let a = PositionSampler.position(of: scratch, atTick: max(0, t - h))
        let b = PositionSampler.position(of: scratch, atTick: min(scratch.lengthTicks, t + h))
        let dt = Double(min(scratch.lengthTicks, t + h) - max(0, t - h))
        return dt > 0 ? (b - a) / dt : 0
    }

    static func analyze(target scratch: Scratch, take: Take) -> Result {
        let ticks = checkpointTicks(of: scratch)
        guard !ticks.isEmpty else { return Result(dtwDistance: 0, checkpointScores: []) }

        var tgt = ticks.map { targetVelocity(of: scratch, atTick: $0) }
        var usr = ticks.map { tk -> Double in
            let host = take.clock.hostTime(fromTick: tk)
            return MotionResampler.velocity(take.motion, atHostTime: host) ?? 0
        }

        // normalizacion relativa: dividir cada contorno por su maximo valor
        // absoluto (ADR-005). Si el usuario no movio nada, su contorno es 0 y la
        // distancia sale maxima, que es lo correcto.
        normalizeInPlace(&tgt)
        normalizeInPlace(&usr)

        let dtw = DTW.normalizedDistance(tgt, usr)

        // puntuacion local: mejor desplazamiento entero dentro de una banda que
        // minimiza la diferencia, y luego |dif| punto a punto.
        let lag = bestLag(tgt, usr, maxLag: 6)
        var scores: [Int] = []
        for i in tgt.indices {
            let j = i + lag
            let d = (j >= 0 && j < usr.count) ? abs(tgt[i] - usr[j]) : 1.0
            scores.append(ScoringConstants.points(for: d, bands: ScoringConstants.pitchBands))
        }
        return Result(dtwDistance: dtw, checkpointScores: scores)
    }

    private static func normalizeInPlace(_ v: inout [Double]) {
        let m = v.map { abs($0) }.max() ?? 0
        guard m > 1e-12 else { return }
        for i in v.indices { v[i] /= m }
    }

    private static func bestLag(_ a: [Double], _ b: [Double], maxLag: Int) -> Int {
        var best = 0
        var bestErr = Double.greatestFiniteMagnitude
        for lag in -maxLag...maxLag {
            var err = 0.0
            var n = 0
            for i in a.indices {
                let j = i + lag
                if j >= 0 && j < b.count { err += abs(a[i] - b[j]); n += 1 }
            }
            if n > 0 {
                let avg = err / Double(n)
                if avg < bestErr { bestErr = avg; best = lag }
            }
        }
        return best
    }
}
