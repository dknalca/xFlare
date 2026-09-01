// SPDX-License-Identifier: GPL-3.0-only

import Foundation
import GRDB

/// Un intento = una toma puntuada. Campos de `data/schema/attempt.schema.json`.
///
/// `eventScores` (el desglose punto a punto) NO va aquí: son filas de
/// `AttemptEvent`, se guardan y se leen aparte con
/// `XFDatabase.saveAttempt(_:events:)` / `events(ofAttempt:)`.
public struct Attempt: Codable, Identifiable, Equatable, Sendable,
                       FetchableRecord, PersistableRecord {

    /// Modo en que se hizo la toma. `warmup` va siempre con
    /// `countsForStars == false` (ADR-027).
    public enum Mode: String, Codable, Sendable, CaseIterable {
        case ghost, free, listen, metronome, warmup
    }

    public var id: String
    public var exerciseId: String
    public var variantId: String
    /// Sesión a la que pertenece, o `nil` (modo libre suelto, o sesión borrada).
    public var sessionId: String?
    public var mode: Mode
    public var bpm: Double
    public var startedAt: Date
    public var durationMs: Double?
    public var score: Int
    public var maxScore: Int
    public var accuracy: Double
    public var stars: Int
    /// Desviación típica del desfase de clicks, ms.
    public var sigmaMs: Double?
    /// Sesgo (media del desfase con signo), ms. `+` = tarde.
    public var biasMs: Double?
    /// Nº de eventos que puntuaron 0.
    public var zeroEvents: Int?
    /// Ruta al `.xfsession` crudo de la toma, para volver a oírla / re-puntuarla.
    public var sessionFile: String?
    /// `false` en calentamiento: se registra pero no mueve estrellas ni progreso
    /// (ADR-027).
    public var countsForStars: Bool

    public static let databaseTableName = "attempt"

    public init(id: String, exerciseId: String, variantId: String,
                sessionId: String? = nil, mode: Mode, bpm: Double, startedAt: Date,
                durationMs: Double? = nil, score: Int, maxScore: Int,
                accuracy: Double, stars: Int, sigmaMs: Double? = nil,
                biasMs: Double? = nil, zeroEvents: Int? = nil,
                sessionFile: String? = nil, countsForStars: Bool = true) {
        self.id = id
        self.exerciseId = exerciseId
        self.variantId = variantId
        self.sessionId = sessionId
        self.mode = mode
        self.bpm = bpm
        self.startedAt = startedAt
        self.durationMs = durationMs
        self.score = score
        self.maxScore = maxScore
        self.accuracy = accuracy
        self.stars = stars
        self.sigmaMs = sigmaMs
        self.biasMs = biasMs
        self.zeroEvents = zeroEvents
        self.sessionFile = sessionFile
        self.countsForStars = countsForStars
    }
}
