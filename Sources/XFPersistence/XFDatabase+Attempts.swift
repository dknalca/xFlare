// SPDX-License-Identifier: GPL-3.0-only

import Foundation
import GRDB

/// B10.2 / B10.6 — histórico de tomas: guardar y leer sesiones, intentos y su
/// desglose de eventos.
extension XFDatabase {

    // MARK: - sesiones

    /// Inserta o actualiza una sesión de práctica.
    public func saveSession(_ session: PracticeSession) throws {
        try writer.write { try session.save($0) }
    }

    public func session(id: String) throws -> PracticeSession? {
        try writer.read { try PracticeSession.fetchOne($0, key: id) }
    }

    // MARK: - intentos

    /// Guarda un intento y, en la misma transacción, su desglose de eventos
    /// (`eventScores`). Si el intento ya existía se reemplazan sus eventos.
    public func saveAttempt(_ attempt: Attempt, events: [AttemptEvent] = []) throws {
        try writer.write { db in
            try attempt.save(db)
            try AttemptEvent
                .filter(Column("attemptId") == attempt.id)
                .deleteAll(db)
            for var event in events {
                event.attemptId = attempt.id     // el llamante no tiene por qué repetirlo
                event.id = nil
                try event.insert(db)
            }
        }
    }

    public func attempt(id: String) throws -> Attempt? {
        try writer.read { try Attempt.fetchOne($0, key: id) }
    }

    /// Eventos de un intento, en orden de instante (`t`).
    public func events(ofAttempt attemptId: String) throws -> [AttemptEvent] {
        try writer.read { db in
            try AttemptEvent
                .filter(Column("attemptId") == attemptId)
                .order(Column("t"))
                .fetchAll(db)
        }
    }

    /// Histórico de intentos de una variante, del más reciente al más antiguo.
    /// `limit == nil` los trae todos. Incluye los de calentamiento
    /// (`countsForStars == false`); filtra tú si no los quieres.
    public func attempts(exerciseId: String, variantId: String,
                         limit: Int? = nil) throws -> [Attempt] {
        try writer.read { db in
            var request = Attempt
                .filter(Column("exerciseId") == exerciseId
                        && Column("variantId") == variantId)
                .order(Column("startedAt").desc)
            if let limit { request = request.limit(limit) }
            return try request.fetchAll(db)
        }
    }

    /// Todos los intentos de un ejercicio (todas sus variantes), del más
    /// reciente al más antiguo.
    public func attempts(exerciseId: String, limit: Int? = nil) throws -> [Attempt] {
        try writer.read { db in
            var request = Attempt
                .filter(Column("exerciseId") == exerciseId)
                .order(Column("startedAt").desc)
            if let limit { request = request.limit(limit) }
            return try request.fetchAll(db)
        }
    }
}
