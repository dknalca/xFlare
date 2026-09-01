// SPDX-License-Identifier: GPL-3.0-only

import Foundation
import XFPersistence

/// Formatea el progreso de una variante para la pantalla de progreso
/// (`docs/UI_DESIGN.md` §3.4b, campos de `docs/SCORING.md` §3). Value type puro.
public struct ExerciseProgressDisplay: Equatable, Sendable {

    public var attempts: Int
    public var bestScore: String        // "3.840" o "—"
    public var bestScoreDate: String?   // "2026-08-14" o nil
    public var lastScore: String
    public var averageOfLast5: String   // "3.512" o "—"
    public var stars: Int
    public var bestBpmWith3Stars: String   // "92 BPM" o "—"
    public var meanBias: String         // "+15 ms" / "−8 ms" / "—"
    public var totalPracticeTime: String   // "1 h 12 min"
    /// La línea de puntuaciones (últimos 20, del más antiguo al más reciente).
    public var sparkline: [Int]

    public static func build(_ summary: ProgressSummary,
                             calendar: Calendar = .current) -> ExerciseProgressDisplay {
        let p = summary.progress
        return ExerciseProgressDisplay(
            attempts: p.attempts,
            bestScore: p.bestScore.map(grouped) ?? "—",
            bestScoreDate: p.bestScoreAt.map { isoDay($0, calendar) },
            lastScore: p.lastScore.map(grouped) ?? "—",
            averageOfLast5: summary.averageOfLast5.map { grouped(Int($0.rounded())) } ?? "—",
            stars: p.stars,
            bestBpmWith3Stars: p.bestBpmWith3Stars.map { "\($0) BPM" } ?? "—",
            meanBias: p.meanBiasMs.map(signedMs) ?? "—",
            totalPracticeTime: duration(ms: p.totalPracticeMs),
            sparkline: summary.recentScores)
    }

    // MARK: - formato

    static func grouped(_ n: Int) -> String { ResultsSummary.grouped(n) }

    static func signedMs(_ ms: Double) -> String {
        let r = Int(ms.rounded())
        if r == 0 { return "0 ms" }
        return (r > 0 ? "+" : "−") + "\(abs(r)) ms"
    }

    static func duration(ms: Double) -> String {
        let totalMin = Int((ms / 60_000).rounded(.down))
        let h = totalMin / 60, m = totalMin % 60
        if h == 0 { return "\(m) min" }
        return "\(h) h \(m) min"
    }

    private static func isoDay(_ date: Date, _ cal: Calendar) -> String {
        let c = cal.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }
}
