// SPDX-License-Identifier: GPL-3.0-only

import Foundation
import GRDB

/// Registro de que una variante de un ejercicio ha quedado desbloqueada. La
/// condición para desbloquearla (p. ej. "2★ en base") vive en los datos del
/// currículo (`data/curriculum/variants.json`); aquí solo se guarda el hecho y
/// su fecha.
public struct VariantUnlock: Codable, Equatable, Sendable,
                             FetchableRecord, PersistableRecord {

    public var exerciseId: String
    public var variantId: String
    public var unlockedAt: Date

    public static let databaseTableName = "variantUnlock"

    public init(exerciseId: String, variantId: String, unlockedAt: Date) {
        self.exerciseId = exerciseId
        self.variantId = variantId
        self.unlockedAt = unlockedAt
    }
}
