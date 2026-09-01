// SPDX-License-Identifier: GPL-3.0-only

import Foundation
import GRDB

/// Una línea del desglose de puntuación de un intento (`eventScores` en
/// `data/schema/attempt.schema.json`). Se guarda como fila hija de `attempt`
/// (borrado en cascada).
public struct AttemptEvent: Codable, Equatable, Sendable,
                            FetchableRecord, MutablePersistableRecord {

    public enum EventType: String, Codable, Sendable, CaseIterable {
        case click, pitch, amplitude
    }

    /// `nil` hasta que se inserta; lo rellena SQLite.
    public var id: Int64?
    public var attemptId: String
    public var type: EventType
    /// Instante del evento en ticks musicales (PPQ 480).
    public var t: Int
    public var points: Int
    /// Desfase con signo del evento, ms (solo tiene sentido en `click`).
    public var offsetMs: Double?

    public static let databaseTableName = "attemptEvent"

    public init(id: Int64? = nil, attemptId: String, type: EventType,
                t: Int, points: Int, offsetMs: Double? = nil) {
        self.id = id
        self.attemptId = attemptId
        self.type = type
        self.t = t
        self.points = points
        self.offsetMs = offsetMs
    }

    // GRDB rellena el rowid asignado tras el INSERT.
    public mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}
