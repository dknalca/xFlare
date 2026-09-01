// SPDX-License-Identifier: GPL-3.0-only

import Foundation
import GRDB

/// Una pasada por el bucle de gimnasio (calentamiento → series → boss). Los
/// intentos la referencian por `id`; si se borra, el intento se queda sin
/// sesión (no se borra).
public struct PracticeSession: Codable, Identifiable, Equatable, Sendable,
                               FetchableRecord, PersistableRecord {

    public var id: String
    public var exerciseId: String
    public var startedAt: Date
    public var endedAt: Date?
    /// BPM al que acabó el bloque principal (donde dejó la escalera adaptativa).
    public var finalBpm: Int?

    public static let databaseTableName = "practiceSession"

    public init(id: String, exerciseId: String, startedAt: Date,
                endedAt: Date? = nil, finalBpm: Int? = nil) {
        self.id = id
        self.exerciseId = exerciseId
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.finalBpm = finalBpm
    }
}
