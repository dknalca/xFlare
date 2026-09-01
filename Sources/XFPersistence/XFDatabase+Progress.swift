// SPDX-License-Identifier: GPL-3.0-only

import Foundation
import GRDB

/// B10.7 — progreso agregado por (ejercicio, variante). `docs/SCORING.md` §3.
extension XFDatabase {

    /// Recalcula la fila de `exerciseProgress` a partir de la tabla `attempt` y
    /// la guarda. Llamar después de cada `saveAttempt`.
    ///
    /// Cuentan solo los intentos con `countsForStars == true` (ADR-027), excepto
    /// `totalPracticeMs`, que suma el tiempo de todos (el calentamiento también
    /// es tiempo tocado).
    @discardableResult
    public func recomputeProgress(exerciseId: String, variantId: String) throws -> ExerciseProgress {
        try writer.write { db in
            let scoredWhere = "exerciseId = ? AND variantId = ? AND countsForStars = 1"
            let key: [DatabaseValueConvertible] = [exerciseId, variantId]

            let agg = try Row.fetchOne(db, sql: """
                SELECT COUNT(*)                             AS n,
                       MAX(score)                           AS best,
                       MAX(stars)                           AS stars,
                       AVG(biasMs)                          AS meanBias,
                       MAX(CASE WHEN stars = 3 THEN bpm END) AS bestBpm3
                FROM attempt WHERE \(scoredWhere)
                """, arguments: StatementArguments(key))!

            let n: Int = agg["n"]
            let best: Int? = agg["best"]
            let stars: Int = agg["stars"] ?? 0
            let meanBias: Double? = agg["meanBias"]
            let bestBpm3: Double? = agg["bestBpm3"]

            // Fecha del primer intento que alcanzó el mejor score.
            var bestAt: Date?
            if let best {
                bestAt = try Date.fetchOne(db, sql: """
                    SELECT startedAt FROM attempt WHERE \(scoredWhere) AND score = ?
                    ORDER BY startedAt ASC LIMIT 1
                    """, arguments: StatementArguments(key + [best]))
            }

            let lastRow = try Row.fetchOne(db, sql: """
                SELECT score, startedAt FROM attempt WHERE \(scoredWhere)
                ORDER BY startedAt DESC LIMIT 1
                """, arguments: StatementArguments(key))
            let lastScore: Int? = lastRow?["score"]
            let lastAt: Date? = lastRow?["startedAt"]

            let total = try Double.fetchOne(db, sql: """
                SELECT COALESCE(SUM(durationMs), 0) FROM attempt
                WHERE exerciseId = ? AND variantId = ?
                """, arguments: [exerciseId, variantId]) ?? 0

            let progress = ExerciseProgress(
                exerciseId: exerciseId, variantId: variantId,
                attempts: n, bestScore: best, bestScoreAt: bestAt,
                lastScore: lastScore, lastAttemptAt: lastAt,
                stars: stars,
                bestBpmWith3Stars: bestBpm3.map { Int($0.rounded()) },
                meanBiasMs: meanBias, totalPracticeMs: total)
            try progress.save(db)
            return progress
        }
    }

    public func progress(exerciseId: String, variantId: String) throws -> ExerciseProgress? {
        try writer.read { db in
            try ExerciseProgress
                .filter(Column("exerciseId") == exerciseId && Column("variantId") == variantId)
                .fetchOne(db)
        }
    }

    /// El progreso guardado más la media de los últimos 5 y la línea de los
    /// últimos 20. `nil` si esa variante no tiene fila de progreso todavía.
    public func progressSummary(exerciseId: String, variantId: String) throws -> ProgressSummary? {
        try writer.read { db in
            guard let progress = try ExerciseProgress
                .filter(Column("exerciseId") == exerciseId && Column("variantId") == variantId)
                .fetchOne(db)
            else { return nil }

            let scoredWhere = "exerciseId = ? AND variantId = ? AND countsForStars = 1"
            let key: StatementArguments = [exerciseId, variantId]

            let last5 = try Int.fetchAll(db, sql: """
                SELECT score FROM attempt WHERE \(scoredWhere)
                ORDER BY startedAt DESC LIMIT 5
                """, arguments: key)
            let avg5: Double? = last5.isEmpty ? nil
                : Double(last5.reduce(0, +)) / Double(last5.count)

            let last20 = try Int.fetchAll(db, sql: """
                SELECT score FROM attempt WHERE \(scoredWhere)
                ORDER BY startedAt DESC LIMIT 20
                """, arguments: key)

            return ProgressSummary(progress: progress,
                                   averageOfLast5: avg5,
                                   recentScores: last20.reversed())
        }
    }
}
