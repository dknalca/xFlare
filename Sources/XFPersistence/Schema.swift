// SPDX-License-Identifier: GPL-3.0-only

import GRDB

/// El esquema de la base local y sus migraciones.
///
/// Regla de oro de las migraciones: **una migración publicada no se toca nunca**.
/// Cualquier cambio de esquema entra como una migración nueva (`v2`, `v3`...); la
/// base de cada usuario se pone al día aplicando solo las que le falten. Por eso
/// `v1` crea de golpe todas las tablas del bloque B10, aunque el código que las
/// consulta (histórico, progreso agregado, repetición espaciada, calibración,
/// desbloqueos) llegue en tareas posteriores.
///
/// Nombres de tabla y columna en inglés (como el resto del código). Fechas como
/// `DATETIME` (GRDB las guarda en texto ISO-8601). Booleanos como `BOOLEAN`
/// (0/1).
///
/// Detalle interno: la app solo necesita `XFDatabase`, que aplica esto al abrir.
enum Schema {

    /// El migrador con todas las migraciones conocidas, en orden.
    static var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()
        registerV1(in: &migrator)
        return migrator
    }

    // MARK: - v1 · esquema inicial del progreso

    private static func registerV1(in migrator: inout DatabaseMigrator) {
        migrator.registerMigration("v1") { db in

            // Una pasada por el bucle de gimnasio (calentamiento → series → boss).
            // La referencian los intentos por `sessionId`.
            try db.create(table: "practiceSession") { t in
                t.column("id", .text).primaryKey()
                t.column("exerciseId", .text).notNull()
                t.column("startedAt", .datetime).notNull()
                t.column("endedAt", .datetime)
                t.column("finalBpm", .integer)
            }

            // Un intento = una toma puntuada. Campos de
            // `data/schema/attempt.schema.json`.
            try db.create(table: "attempt") { t in
                t.column("id", .text).primaryKey()
                t.column("exerciseId", .text).notNull()
                t.column("variantId", .text).notNull()
                // Si se borra la sesión, el intento sobrevive sin ella.
                t.column("sessionId", .text)
                    .references("practiceSession", onDelete: .setNull)
                t.column("mode", .text).notNull()          // ghost|free|listen|metronome|warmup
                t.column("bpm", .double).notNull()
                t.column("startedAt", .datetime).notNull()
                t.column("durationMs", .double)
                t.column("score", .integer).notNull()
                t.column("maxScore", .integer).notNull()
                t.column("accuracy", .double).notNull()
                t.column("stars", .integer).notNull()
                t.column("sigmaMs", .double)
                t.column("biasMs", .double)
                t.column("zeroEvents", .integer)
                t.column("sessionFile", .text)             // ruta al .xfsession crudo
                // ADR-027: el calentamiento registra pero no cuenta para estrellas.
                t.column("countsForStars", .boolean).notNull().defaults(to: true)
            }
            try db.create(
                index: "attempt_on_exercise_variant",
                on: "attempt", columns: ["exerciseId", "variantId"]
            )
            try db.create(
                index: "attempt_on_startedAt",
                on: "attempt", columns: ["startedAt"]
            )

            // Desglose por evento de un intento (`eventScores` del schema).
            try db.create(table: "attemptEvent") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("attemptId", .text).notNull()
                    .references("attempt", onDelete: .cascade)
                t.column("type", .text).notNull()          // click|pitch|amplitude
                t.column("t", .integer).notNull()          // instante en ticks
                t.column("points", .integer).notNull()
                t.column("offsetMs", .double)
            }
            try db.create(
                index: "attemptEvent_on_attempt",
                on: "attemptEvent", columns: ["attemptId"]
            )

            // Progreso agregado por (ejercicio, variante). `docs/SCORING.md` §3.
            try db.create(table: "exerciseProgress") { t in
                t.column("exerciseId", .text).notNull()
                t.column("variantId", .text).notNull()
                t.column("attempts", .integer).notNull().defaults(to: 0)
                t.column("bestScore", .integer)
                t.column("bestScoreAt", .datetime)
                t.column("lastScore", .integer)
                t.column("lastAttemptAt", .datetime)
                t.column("stars", .integer).notNull().defaults(to: 0)
                t.column("bestBpmWith3Stars", .integer)
                t.column("meanBiasMs", .double)
                t.column("totalPracticeMs", .double).notNull().defaults(to: 0)
                t.primaryKey(["exerciseId", "variantId"])
            }

            // Variantes desbloqueadas (B10.8).
            try db.create(table: "variantUnlock") { t in
                t.column("exerciseId", .text).notNull()
                t.column("variantId", .text).notNull()
                t.column("unlockedAt", .datetime).notNull()
                t.primaryKey(["exerciseId", "variantId"])
            }

            // Estado de dominado / oxidado por ejercicio (B10.8 + ADR-027).
            try db.create(table: "exerciseMastery") { t in
                t.column("exerciseId", .text).primaryKey()
                t.column("masteredAt", .datetime)
                t.column("oxidizedAt", .datetime)
            }

            // Repetición espaciada: 1, 3, 7, 21 días (B10.3). `stage` indexa esa
            // lista; `dueAt` es cuándo toca repasar.
            try db.create(table: "reviewSchedule") { t in
                t.column("exerciseId", .text).notNull()
                t.column("variantId", .text).notNull()
                t.column("stage", .integer).notNull().defaults(to: 0)
                t.column("dueAt", .datetime).notNull()
                t.column("lastReviewedAt", .datetime)
                t.primaryKey(["exerciseId", "variantId"])
            }
            try db.create(
                index: "reviewSchedule_on_dueAt",
                on: "reviewSchedule", columns: ["dueAt"]
            )

            // Calibración por dispositivo de audio/MIDI (B10.4). `deviceKey` es
            // el identificador estable del dispositivo (UID de audio o nombre de
            // puerto MIDI); `profileId` es el perfil de `XFProfiles`.
            try db.create(table: "deviceCalibration") { t in
                t.column("deviceKey", .text).primaryKey()
                t.column("profileId", .text).notNull()
                t.column("faderCutIn", .double).notNull()
                t.column("faderHysteresis", .double).notNull()
                t.column("hamster", .boolean).notNull().defaults(to: false)
                t.column("latencyMs", .double)
                t.column("updatedAt", .datetime).notNull()
            }

            // Minutos practicados por día, para la racha diaria (`CURRICULUM` §7).
            try db.create(table: "practiceDay") { t in
                t.column("day", .text).primaryKey()        // 'YYYY-MM-DD'
                t.column("practiceMs", .double).notNull().defaults(to: 0)
            }

            // Ajustes de la app, clave/valor.
            try db.create(table: "setting") { t in
                t.column("key", .text).primaryKey()
                t.column("value", .text).notNull()
            }
        }
    }
}
