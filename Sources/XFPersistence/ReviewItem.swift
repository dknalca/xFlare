// SPDX-License-Identifier: GPL-3.0-only

import Foundation
import GRDB

/// Una entrada de repetición espaciada: cuándo toca repasar una variante ya
/// superada. `docs/CURRICULUM.md` §7 / `docs/WARMUP.md`: intervalos de **1, 3,
/// 7 y 21 días**.
public struct ReviewItem: Codable, Equatable, Sendable,
                          FetchableRecord, PersistableRecord {

    /// Días entre repasos según el `stage` (0→1, 1→3, 2→7, 3→21).
    public static let intervalDays = [1, 3, 7, 21]

    public var exerciseId: String
    public var variantId: String
    /// Escalón dentro de `intervalDays`. Sube al aprobar un repaso, vuelve a 0 al
    /// fallarlo.
    public var stage: Int
    /// Cuándo vuelve a tocar repasar.
    public var dueAt: Date
    public var lastReviewedAt: Date?

    public static let databaseTableName = "reviewSchedule"

    /// Días que cubre el `stage` actual (1, 3, 7 o 21).
    public var stageDays: Int { Self.intervalDays[min(stage, Self.intervalDays.count - 1)] }

    public init(exerciseId: String, variantId: String, stage: Int,
                dueAt: Date, lastReviewedAt: Date? = nil) {
        self.exerciseId = exerciseId
        self.variantId = variantId
        self.stage = stage
        self.dueAt = dueAt
        self.lastReviewedAt = lastReviewedAt
    }
}
