// SPDX-License-Identifier: GPL-3.0-only

import Foundation
import GRDB

/// Progreso agregado de una variante de un ejercicio. `docs/SCORING.md` §3.
///
/// Es una **fila derivada**: la recalcula `XFDatabase.recomputeProgress(...)` a
/// partir de la tabla `attempt`. Solo cuentan los intentos con
/// `countsForStars == true` (ADR-027), salvo `totalPracticeMs`, que suma todo el
/// tiempo tocado.
///
/// La "media de los últimos 5" y la línea de los últimos 20 no se guardan aquí
/// (son triviales de recalcular): van en `ProgressSummary`.
public struct ExerciseProgress: Codable, Equatable, Sendable,
                                FetchableRecord, PersistableRecord {

    public var exerciseId: String
    public var variantId: String
    /// Nº de intentos que cuentan para estrellas.
    public var attempts: Int
    public var bestScore: Int?
    public var bestScoreAt: Date?
    public var lastScore: Int?
    public var lastAttemptAt: Date?
    /// Máximo de estrellas conseguido. No baja nunca (`docs/SCORING.md` §2).
    public var stars: Int
    /// BPM más alto al que se han sacado 3★. La medida honesta de mejora.
    public var bestBpmWith3Stars: Int?
    /// Sesgo medio (ms, con signo). `+` = llegas tarde de forma sistemática.
    public var meanBiasMs: Double?
    /// Tiempo total tocado en esta variante, ms. Incluye el calentamiento.
    public var totalPracticeMs: Double

    public static let databaseTableName = "exerciseProgress"

    public init(exerciseId: String, variantId: String, attempts: Int = 0,
                bestScore: Int? = nil, bestScoreAt: Date? = nil,
                lastScore: Int? = nil, lastAttemptAt: Date? = nil,
                stars: Int = 0, bestBpmWith3Stars: Int? = nil,
                meanBiasMs: Double? = nil, totalPracticeMs: Double = 0) {
        self.exerciseId = exerciseId
        self.variantId = variantId
        self.attempts = attempts
        self.bestScore = bestScore
        self.bestScoreAt = bestScoreAt
        self.lastScore = lastScore
        self.lastAttemptAt = lastAttemptAt
        self.stars = stars
        self.bestBpmWith3Stars = bestBpmWith3Stars
        self.meanBiasMs = meanBiasMs
        self.totalPracticeMs = totalPracticeMs
    }
}
