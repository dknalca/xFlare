// SPDX-License-Identifier: GPL-3.0-only
import XCTest
import GRDB
@testable import XFPersistence

/// B10.1 — esquema GRDB y migraciones.
final class XFPersistenceTests: XCTestCase {

    private let allTables = [
        "practiceSession", "attempt", "attemptEvent", "exerciseProgress",
        "variantUnlock", "exerciseMastery", "reviewSchedule",
        "deviceCalibration", "practiceDay", "setting",
    ]

    // Columnas de data/schema/attempt.schema.json (properties completas).
    private let attemptColumns: Set<String> = [
        "id", "exerciseId", "variantId", "sessionId", "mode", "bpm", "startedAt",
        "durationMs", "score", "maxScore", "accuracy", "stars", "sigmaMs",
        "biasMs", "zeroEvents", "sessionFile", "countsForStars",
    ]

    func testAPIVersion() {
        XCTAssertEqual(XFPersistence.apiVersion, 1)
    }

    func testMigradorSeAplicaYQuedaAlDia() throws {
        let db = try XFDatabase.inMemory()
        XCTAssertTrue(try db.isUpToDate())
    }

    func testEstanTodasLasTablas() throws {
        let db = try XFDatabase.inMemory()
        try db.writer.read { d in
            for name in allTables {
                XCTAssertTrue(try d.tableExists(name), "falta la tabla \(name)")
            }
        }
    }

    func testColumnasDeAttemptCoincidenConElSchema() throws {
        let db = try XFDatabase.inMemory()
        let cols = try db.writer.read { try Set($0.columns(in: "attempt").map(\.name)) }
        XCTAssertEqual(cols, attemptColumns)
    }

    func testCountsForStarsPorDefectoEsVerdadero() throws {
        // ADR-027: un intento normal cuenta para estrellas salvo que se diga.
        let db = try XFDatabase.inMemory()
        try db.writer.write { d in
            try d.execute(sql: """
                INSERT INTO attempt (id, exerciseId, variantId, mode, bpm, startedAt,
                                     score, maxScore, accuracy, stars)
                VALUES ('a1', 'ex-l1-baby', 'base', 'ghost', 70, '2026-09-01 10:00:00',
                        3200, 3600, 0.89, 2)
                """)
            let counts = try Bool.fetchOne(d, sql: "SELECT countsForStars FROM attempt WHERE id = 'a1'")
            XCTAssertEqual(counts, true)
        }
    }

    func testClaveForaneaDeAttemptEventSeExige() throws {
        let db = try XFDatabase.inMemory()
        try db.writer.write { d in
            XCTAssertThrowsError(
                try d.execute(sql: """
                    INSERT INTO attemptEvent (attemptId, type, t, points)
                    VALUES ('no-existe', 'click', 480, 100)
                    """),
                "insertar un evento sin su intento debe violar la FK"
            ) { error in
                XCTAssertEqual((error as? DatabaseError)?.resultCode, .SQLITE_CONSTRAINT)
            }
        }
    }

    func testBorrarUnIntentoArrastraSusEventos() throws {
        let db = try XFDatabase.inMemory()
        try db.writer.write { d in
            try d.execute(sql: """
                INSERT INTO attempt (id, exerciseId, variantId, mode, bpm, startedAt,
                                     score, maxScore, accuracy, stars)
                VALUES ('a1', 'ex-l1-baby', 'base', 'ghost', 70, '2026-09-01 10:00:00',
                        3200, 3600, 0.89, 2)
                """)
            try d.execute(sql: """
                INSERT INTO attemptEvent (attemptId, type, t, points) VALUES
                ('a1', 'click', 480, 100), ('a1', 'pitch', 960, 80)
                """)
            XCTAssertEqual(try Int.fetchOne(d, sql: "SELECT COUNT(*) FROM attemptEvent"), 2)

            try d.execute(sql: "DELETE FROM attempt WHERE id = 'a1'")
            XCTAssertEqual(try Int.fetchOne(d, sql: "SELECT COUNT(*) FROM attemptEvent"), 0,
                           "ON DELETE CASCADE debe llevarse los eventos")
        }
    }

    func testAttemptSobreviveAlBorradoDeLaSesion() throws {
        let db = try XFDatabase.inMemory()
        try db.writer.write { d in
            try d.execute(sql: """
                INSERT INTO practiceSession (id, exerciseId, startedAt)
                VALUES ('s1', 'ex-l1-baby', '2026-09-01 10:00:00')
                """)
            try d.execute(sql: """
                INSERT INTO attempt (id, exerciseId, variantId, sessionId, mode, bpm,
                                     startedAt, score, maxScore, accuracy, stars)
                VALUES ('a1', 'ex-l1-baby', 'base', 's1', 'ghost', 70,
                        '2026-09-01 10:00:00', 3200, 3600, 0.89, 2)
                """)
            try d.execute(sql: "DELETE FROM practiceSession WHERE id = 's1'")

            let sessionId = try String.fetchOne(d, sql: "SELECT sessionId FROM attempt WHERE id = 'a1'")
            XCTAssertNil(sessionId, "el intento se queda, pero sin sesión (ON DELETE SET NULL)")
        }
    }

    func testMigradorEsIdempotente() throws {
        let db = try XFDatabase.inMemory()
        // Aplicarlo otra vez sobre la misma base no debe hacer nada ni fallar.
        XCTAssertNoThrow(try Schema.migrator.migrate(db.writer))
        XCTAssertTrue(try db.isUpToDate())
    }

    func testClavePrimariaCompuestaDeExerciseProgress() throws {
        let db = try XFDatabase.inMemory()
        try db.writer.write { d in
            try d.execute(sql: "INSERT INTO exerciseProgress (exerciseId, variantId) VALUES ('ex', 'base')")
            XCTAssertThrowsError(
                try d.execute(sql: "INSERT INTO exerciseProgress (exerciseId, variantId) VALUES ('ex', 'base')")
            )
            // otra variante del mismo ejercicio sí entra
            XCTAssertNoThrow(
                try d.execute(sql: "INSERT INTO exerciseProgress (exerciseId, variantId) VALUES ('ex', 'div16')")
            )
        }
    }
}
