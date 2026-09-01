// SPDX-License-Identifier: GPL-3.0-only

import XFClock
import XFNotation

/// Recorrido de cada trazo hacia delante (B8.3). Se normaliza respecto al rango
/// del propio usuario (ADR-005): lo que cuenta es la proporcion entre trazos, no
/// las vueltas absolutas.
enum AmplitudeAnalyzer {

    struct Result {
        /// Puntos (0..100) por cada trazo `fwd` del patron.
        let strokeScores: [Int]
        /// Error relativo medio (0 = perfecto).
        let meanError: Double
    }

    static func analyze(target scratch: Scratch, take: Take) -> Result {
        let fwd = scratch.record.filter { $0.dir == .fwd }
        guard !fwd.isEmpty else { return Result(strokeScores: [], meanError: 0) }

        // recorrido objetivo y de usuario por trazo
        let targetTravel = fwd.map { abs($0.pTo - $0.pFrom) }
        let userTravel = fwd.map { ph -> Double in
            let h0 = take.clock.hostTime(fromTick: ph.t)
            let h1 = take.clock.hostTime(fromTick: ph.t + ph.dur)
            let p0 = MotionResampler.position(take.motion, atHostTime: h0)
            let p1 = MotionResampler.position(take.motion, atHostTime: h1)
            if let a = p0, let b = p1 { return abs(b - a) }
            return 0
        }

        let tgtMax = targetTravel.max() ?? 1
        let usrMax = userTravel.max() ?? 0

        var scores: [Int] = []
        var errs: [Double] = []
        for i in fwd.indices {
            let tgtRatio = tgtMax > 1e-12 ? targetTravel[i] / tgtMax : 0
            let usrRatio = usrMax > 1e-12 ? userTravel[i] / usrMax : 0
            let relErr = abs(tgtRatio - usrRatio)
            errs.append(relErr)
            scores.append(ScoringConstants.points(for: relErr, bands: ScoringConstants.amplitudeBands))
        }
        let mean = errs.isEmpty ? 0 : errs.reduce(0, +) / Double(errs.count)
        return Result(strokeScores: scores, meanError: mean)
    }
}
