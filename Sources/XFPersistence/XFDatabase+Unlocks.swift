// SPDX-License-Identifier: GPL-3.0-only

import Foundation
import GRDB

/// B10.2 / B10.8 — desbloqueo de variantes (guardar el hecho y consultarlo).
/// La evaluación de las reglas del currículo está en `XFDatabase+Mastery.swift`.
extension XFDatabase {

    /// Marca una variante como desbloqueada. Idempotente: si ya lo estaba,
    /// conserva la fecha original.
    public func markVariantUnlocked(exerciseId: String, variantId: String,
                                    at date: Date) throws {
        try writer.write { db in
            let already = try VariantUnlock
                .filter(Column("exerciseId") == exerciseId
                        && Column("variantId") == variantId)
                .fetchCount(db) > 0
            guard !already else { return }
            try VariantUnlock(exerciseId: exerciseId, variantId: variantId,
                              unlockedAt: date).insert(db)
        }
    }

    public func isVariantUnlocked(exerciseId: String, variantId: String) throws -> Bool {
        try writer.read { db in
            try VariantUnlock
                .filter(Column("exerciseId") == exerciseId
                        && Column("variantId") == variantId)
                .fetchCount(db) > 0
        }
    }

    /// Ids de las variantes desbloqueadas de un ejercicio.
    public func unlockedVariants(exerciseId: String) throws -> Set<String> {
        try writer.read { db in
            let rows = try VariantUnlock
                .filter(Column("exerciseId") == exerciseId)
                .fetchAll(db)
            return Set(rows.map(\.variantId))
        }
    }
}
