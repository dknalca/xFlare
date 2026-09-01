// SPDX-License-Identifier: GPL-3.0-only

import Foundation
import XFPersistence

/// Persiste una toma y recalcula lo que depende de ella: progreso agregado,
/// dominado, desbloqueo de variantes y la programacion de repaso. Es el punto
/// donde el resultado de una practica se "asienta".
public enum AttemptRecorder {

    /// - Returns: ids de variantes **recien** desbloqueadas por esta toma.
    @discardableResult
    public static func record(_ attempt: Attempt, events: [AttemptEvent] = [],
                              db: XFDatabase, catalog: Catalog,
                              at date: Date = Date()) throws -> [String] {
        try db.saveAttempt(attempt, events: events)

        // el progreso solo cuenta si la toma cuenta (ADR-027)
        try db.recomputeProgress(exerciseId: attempt.exerciseId, variantId: attempt.variantId)

        let mastery = try db.refreshMastery(exerciseId: attempt.exerciseId, at: date)

        let rules = catalog.variants.compactMap { v -> VariantUnlockRule? in
            guard let req = v.requirement else { return nil }
            return VariantUnlockRule(variantId: v.id,
                                     requiresVariant: req.variant,
                                     requiresStars: req.stars)
        }
        let newlyUnlocked = try db.evaluateUnlocks(exerciseId: attempt.exerciseId,
                                                   rules: rules, at: date)

        // al dominar el ejercicio entra en la rotacion de repaso
        if mastery.isMastered {
            try db.scheduleReview(exerciseId: attempt.exerciseId, variantId: "base",
                                  masteredAt: mastery.masteredAt ?? date)
        }
        return newlyUnlocked
    }
}
