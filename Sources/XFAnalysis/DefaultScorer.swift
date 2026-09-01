// SPDX-License-Identifier: GPL-3.0-only

import Foundation
import XFNotation

/// La implementacion de referencia de `Scorer` (B8.6). Junta el emparejado de
/// clicks, el contorno de tono, la amplitud, sigma, las estrellas y el
/// diagnostico en un `Report`.
public struct DefaultScorer: Scorer {

    public init() {}

    public func score(_ take: Take, against scratch: Scratch, atTargetBpm: Bool) -> Report {
        // --- clicks (B8.1) ---
        let clicks = ClickMatcher.match(target: scratch, take: take)
        let clickScore = clicks.reduce(0) { $0 + $1.score }
        let missed = clicks.filter { $0.isMissed }.count

        let offsets = clicks.compactMap { $0.offsetMs }
        let bias = offsets.isEmpty ? 0 : offsets.reduce(0, +) / Double(offsets.count)
        let sigma = standardDeviation(offsets, mean: bias)

        // --- tono (B8.2) ---
        let pitch = PitchAnalyzer.analyze(target: scratch, take: take)
        let pitchScore = pitch.checkpointScores.reduce(0, +)

        // --- amplitud (B8.3) ---
        let amp = AmplitudeAnalyzer.analyze(target: scratch, take: take)
        let ampScore = amp.strokeScores.reduce(0, +)

        // --- totales (B8.6) ---
        let events = ScoreEvents(of: scratch)
        let score = clickScore + pitchScore + ampScore
        let accuracy = events.maxScore > 0 ? Double(score) / Double(events.maxScore) : 0
        let finished = take.reachedEnd(of: scratch)

        // --- estrellas (B8.7) ---
        let zeroEvents = clicks.filter { $0.score == 0 }.count
            + pitch.checkpointScores.filter { $0 == 0 }.count
            + amp.strokeScores.filter { $0 == 0 }.count
        let stars = Stars.evaluate(accuracy: accuracy, finished: finished, sigmaMs: sigma,
                                   zeroScoredEvents: zeroEvents, atTargetBpm: atTargetBpm)

        // --- diagnostico (B8.4) ---
        let diagnostics = Diagnoser.diagnose(
            clickOffsets: clicks, biasMs: bias, sigmaMs: sigma,
            missedClicks: missed, amplitudeError: amp.meanError,
            pitchDistance: pitch.dtwDistance
        )

        return Report(
            score: score, maxScore: events.maxScore,
            clickOffsets: clicks,
            pitchDistance: pitch.dtwDistance,
            sigmaMs: sigma, biasMs: bias,
            amplitudeError: amp.meanError,
            missedClicks: missed,
            finished: finished,
            stars: stars.count, starReasons: stars.reasons,
            diagnostics: diagnostics
        )
    }

    private func standardDeviation(_ xs: [Double], mean: Double) -> Double {
        guard xs.count >= 2 else { return 0 }
        let v = xs.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(xs.count)
        return v.squareRoot()
    }
}
