// SPDX-License-Identifier: GPL-3.0-only

import Foundation
import GRDB

/// B10.3 — repetición espaciada (1, 3, 7, 21 días).
///
/// "Días" se cuenta como `86 400 s` exactos, no como días de calendario: para la
/// repetición espaciada da igual y así es determinista y sin zona horaria.
extension XFDatabase {

    private static let secondsPerDay: TimeInterval = 86_400

    /// Programa el primer repaso de una variante recién superada: `stage 0`,
    /// dentro de 1 día. Si ya estaba programada, no hace nada.
    public func scheduleReview(exerciseId: String, variantId: String,
                               masteredAt date: Date) throws {
        try writer.write { db in
            let exists = try ReviewItem
                .filter(Column("exerciseId") == exerciseId && Column("variantId") == variantId)
                .fetchCount(db) > 0
            guard !exists else { return }
            let due = date.addingTimeInterval(Self.secondsPerDay * Double(ReviewItem.intervalDays[0]))
            try ReviewItem(exerciseId: exerciseId, variantId: variantId, stage: 0,
                           dueAt: due, lastReviewedAt: date).insert(db)
        }
    }

    /// Registra el resultado de un repaso y recoloca el siguiente:
    /// - **aprobado** → sube un escalón (tope 21 días);
    /// - **fallado** → vuelve al escalón 0 (1 día).
    ///
    /// Si la variante no estaba programada, se crea al vuelo (aprobar la mete en
    /// `stage 1`, fallar la deja en `stage 0`).
    @discardableResult
    public func recordReviewOutcome(exerciseId: String, variantId: String,
                                    passed: Bool, at date: Date) throws -> ReviewItem {
        try writer.write { db in
            let current = try ReviewItem
                .filter(Column("exerciseId") == exerciseId && Column("variantId") == variantId)
                .fetchOne(db)
            let baseStage = current?.stage ?? 0
            let newStage = passed
                ? min(baseStage + 1, ReviewItem.intervalDays.count - 1)
                : 0
            let due = date.addingTimeInterval(
                Self.secondsPerDay * Double(ReviewItem.intervalDays[newStage]))
            let item = ReviewItem(exerciseId: exerciseId, variantId: variantId,
                                  stage: newStage, dueAt: due, lastReviewedAt: date)
            try item.save(db)
            return item
        }
    }

    public func reviewItem(exerciseId: String, variantId: String) throws -> ReviewItem? {
        try writer.read { db in
            try ReviewItem
                .filter(Column("exerciseId") == exerciseId && Column("variantId") == variantId)
                .fetchOne(db)
        }
    }

    /// Variantes cuyo repaso ya toca (o ha pasado), de la más atrasada a la menos.
    public func dueReviews(asOf date: Date) throws -> [ReviewItem] {
        try writer.read { db in
            try ReviewItem
                .filter(Column("dueAt") <= date)
                .order(Column("dueAt"))
                .fetchAll(db)
        }
    }
}
