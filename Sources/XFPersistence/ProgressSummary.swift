// SPDX-License-Identifier: GPL-3.0-only

import Foundation

/// Lo que la pantalla de progreso necesita mostrar (`docs/SCORING.md` §3): el
/// progreso guardado más los dos datos que se recalculan al vuelo.
public struct ProgressSummary: Equatable, Sendable {

    /// La fila agregada (intentos, mejor, estrellas, mejor BPM con 3★, sesgo
    /// medio, tiempo total).
    public var progress: ExerciseProgress

    /// Media de la puntuación de los últimos 5 intentos que cuentan. `nil` si no
    /// hay ninguno. "Tu nivel real, sin el pico de suerte."
    public var averageOfLast5: Double?

    /// Puntuación de los últimos 20 intentos que cuentan, del más antiguo al más
    /// reciente. Es la línea que enseña la mejora.
    public var recentScores: [Int]

    public init(progress: ExerciseProgress, averageOfLast5: Double?, recentScores: [Int]) {
        self.progress = progress
        self.averageOfLast5 = averageOfLast5
        self.recentScores = recentScores
    }
}
