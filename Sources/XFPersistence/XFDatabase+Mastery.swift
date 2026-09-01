// SPDX-License-Identifier: GPL-3.0-only

import Foundation
import GRDB

/// B10.8 — estado de dominado y evaluación del desbloqueo de variantes.
extension XFDatabase {

    /// Umbrales de "dominado" (`docs/SCORING.md` §4). Constantes de producto, no
    /// configurables: 3★ en la base y 2★ en al menos 3 variantes.
    public static let masteryBaseStars = 3
    public static let masteryVariantStars = 2
    public static let masteryVariantCount = 3

    // MARK: - dominado

    /// Recalcula el estado de dominio de un ejercicio mirando las estrellas de
    /// sus filas de `exerciseProgress`, y lo guarda.
    ///
    /// `masteredAt` se pone la **primera** vez que se cumple y ya no se borra
    /// (que se domine no se pierde; lo que avisa de recaídas es `oxidizedAt`).
    @discardableResult
    public func refreshMastery(exerciseId: String,
                               baseVariantId: String = "base",
                               at date: Date) throws -> ExerciseMastery {
        try writer.write { db in
            let rows = try ExerciseProgress
                .filter(Column("exerciseId") == exerciseId)
                .fetchAll(db)

            let baseStars = rows.first { $0.variantId == baseVariantId }?.stars ?? 0
            let strongVariants = rows
                .filter { $0.variantId != baseVariantId && $0.stars >= Self.masteryVariantStars }
                .count
            let nowMastered = baseStars >= Self.masteryBaseStars
                && strongVariants >= Self.masteryVariantCount

            var mastery = try ExerciseMastery.fetchOne(db, key: exerciseId)
                ?? ExerciseMastery(exerciseId: exerciseId)
            if nowMastered && mastery.masteredAt == nil {
                mastery.masteredAt = date
            }
            try mastery.save(db)
            return mastery
        }
    }

    public func mastery(exerciseId: String) throws -> ExerciseMastery? {
        try writer.read { try ExerciseMastery.fetchOne($0, key: exerciseId) }
    }

    public func isMastered(exerciseId: String) throws -> Bool {
        try mastery(exerciseId: exerciseId)?.isMastered ?? false
    }

    /// Ids de los ejercicios dominados (el conjunto del que tira el
    /// calentamiento).
    public func masteredExercises() throws -> [String] {
        try writer.read { db in
            try ExerciseMastery
                .filter(Column("masteredAt") != nil)
                .order(Column("exerciseId"))
                .fetchAll(db)
                .map(\.exerciseId)
        }
    }

    /// Marca (o limpia) la oxidación de un ejercicio. `date == nil` la limpia
    /// (volvió a estar fino).
    public func setOxidized(exerciseId: String, at date: Date?) throws {
        try writer.write { db in
            var mastery = try ExerciseMastery.fetchOne(db, key: exerciseId)
                ?? ExerciseMastery(exerciseId: exerciseId)
            mastery.oxidizedAt = date
            try mastery.save(db)
        }
    }

    // MARK: - desbloqueo de variantes

    /// Evalúa las reglas de desbloqueo contra las estrellas guardadas y marca
    /// como desbloqueadas las que ya se cumplen. Devuelve las **recién**
    /// desbloqueadas.
    ///
    /// Una sola pasada: las reglas miran estrellas, no el estado de desbloqueo,
    /// así que no hace falta cascada.
    @discardableResult
    public func evaluateUnlocks(exerciseId: String,
                                rules: [VariantUnlockRule],
                                at date: Date) throws -> [String] {
        try writer.write { db in
            let stars = try Dictionary(
                uniqueKeysWithValues: ExerciseProgress
                    .filter(Column("exerciseId") == exerciseId)
                    .fetchAll(db)
                    .map { ($0.variantId, $0.stars) }
            )
            let alreadyUnlocked = Set(try VariantUnlock
                .filter(Column("exerciseId") == exerciseId)
                .fetchAll(db)
                .map(\.variantId))

            var newlyUnlocked: [String] = []
            for rule in rules where !alreadyUnlocked.contains(rule.variantId) {
                guard (stars[rule.requiresVariant] ?? 0) >= rule.requiresStars else { continue }
                try VariantUnlock(exerciseId: exerciseId, variantId: rule.variantId,
                                  unlockedAt: date).insert(db)
                newlyUnlocked.append(rule.variantId)
            }
            return newlyUnlocked
        }
    }
}
