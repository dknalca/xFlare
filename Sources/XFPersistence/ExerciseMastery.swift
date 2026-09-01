// SPDX-License-Identifier: GPL-3.0-only

import Foundation
import GRDB

/// Estado de dominio de un ejercicio. `docs/SCORING.md` §4: **dominado** =
/// 3★ en la base y 2★ en al menos tres variantes.
///
/// `oxidizedAt` lo pone el calentamiento (ADR-027 / `docs/WARMUP.md` §5) cuando
/// un ejercicio dominado baja de 2★ en un repaso: no le quita el dominio, pero
/// lo devuelve a la rotación de práctica.
public struct ExerciseMastery: Codable, Equatable, Sendable,
                               FetchableRecord, PersistableRecord {

    public var exerciseId: String
    /// Cuándo se dominó por primera vez. `nil` = aún no.
    public var masteredAt: Date?
    /// Cuándo se detectó oxidación por última vez. `nil` = fresco.
    public var oxidizedAt: Date?

    public static let databaseTableName = "exerciseMastery"

    public var isMastered: Bool { masteredAt != nil }

    public init(exerciseId: String, masteredAt: Date? = nil, oxidizedAt: Date? = nil) {
        self.exerciseId = exerciseId
        self.masteredAt = masteredAt
        self.oxidizedAt = oxidizedAt
    }
}
