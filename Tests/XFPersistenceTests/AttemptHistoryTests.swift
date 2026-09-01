// SPDX-License-Identifier: GPL-3.0-only
import XCTest
import GRDB
@testable import XFPersistence

/// B10.2 / B10.6 — histórico de tomas y su desglose de eventos.
final class AttemptHistoryTests: XCTestCase {

    private let t0 = Date(timeIntervalSince1970: 1_760_000_000)

    private func attempt(_ id: String, exercise: String = "ex-l1-baby",
                         variant: String = "base", score: Int = 3200,
                         stars: Int = 2, bpm: Double = 70,
                         at offset: TimeInterval = 0,
                         counts: Bool = true) -> Attempt {
        Attempt(id: id, exerciseId: exercise, variantId: variant, mode: .ghost,
                bpm: bpm, startedAt: t0.addingTimeInterval(offset),
                durationMs: 12_000, score: score, maxScore: 3600,
                accuracy: Double(score) / 3600, stars: stars,
                sigmaMs: 12, biasMs: -8, zeroEvents: 0,
                sessionFile: "sessions/\(id).xfsession", countsForStars: counts)
    }

    func testGuardaYLeeUnIntentoConTodosSusCampos() throws {
        let db = try XFDatabase.inMemory()
        let a = attempt("a1")
        try db.saveAttempt(a)

        let back = try XCTUnwrap(db.attempt(id: "a1"))
        XCTAssertEqual(back, a, "ida y vuelta sin pérdida de ningún campo del schema")
        XCTAssertEqual(back.sessionFile, "sessions/a1.xfsession")
        XCTAssertEqual(back.mode, .ghost)
    }

    func testHistoricoOrdenadoDelMasRecienteAlMasAntiguo() throws {
        let db = try XFDatabase.inMemory()
        try db.saveAttempt(attempt("viejo", at: 0))
        try db.saveAttempt(attempt("medio", at: 100))
        try db.saveAttempt(attempt("nuevo", at: 200))

        let hist = try db.attempts(exerciseId: "ex-l1-baby", variantId: "base")
        XCTAssertEqual(hist.map(\.id), ["nuevo", "medio", "viejo"])

        let ultimos2 = try db.attempts(exerciseId: "ex-l1-baby", variantId: "base", limit: 2)
        XCTAssertEqual(ultimos2.map(\.id), ["nuevo", "medio"])
    }

    func testHistoricoPorEjercicioAbarcaTodasLasVariantes() throws {
        let db = try XFDatabase.inMemory()
        try db.saveAttempt(attempt("b", variant: "base", at: 0))
        try db.saveAttempt(attempt("d", variant: "div16", at: 50))

        XCTAssertEqual(try db.attempts(exerciseId: "ex-l1-baby").count, 2)
        XCTAssertEqual(try db.attempts(exerciseId: "ex-l1-baby", variantId: "div16").map(\.id), ["d"])
    }

    func testIntentoConLosOpcionalesVaciosRoundTrip() throws {
        let db = try XFDatabase.inMemory()
        let minimo = Attempt(id: "m1", exerciseId: "ex", variantId: "base",
                             mode: .metronome, bpm: 84, startedAt: t0,
                             score: 0, maxScore: 3600, accuracy: 0, stars: 0)
        try db.saveAttempt(minimo)
        let back = try XCTUnwrap(db.attempt(id: "m1"))
        XCTAssertEqual(back, minimo)
        XCTAssertNil(back.sessionId)
        XCTAssertNil(back.durationMs)
        XCTAssertNil(back.sigmaMs)
        XCTAssertNil(back.sessionFile)
        XCTAssertTrue(back.countsForStars, "por defecto cuenta (ADR-027 solo lo apaga en warmup)")
    }

    func testTodosLosModosRoundTrip() throws {
        let db = try XFDatabase.inMemory()
        for (i, mode) in Attempt.Mode.allCases.enumerated() {
            var a = attempt("mode-\(i)")
            a.mode = mode
            a.countsForStars = (mode != .warmup)
            try db.saveAttempt(a)
            XCTAssertEqual(try db.attempt(id: "mode-\(i)")?.mode, mode)
        }
    }

    // MARK: - eventos (eventScores)

    func testGuardaYLeeElDesgloseDeEventos() throws {
        let db = try XFDatabase.inMemory()
        let events = [
            AttemptEvent(attemptId: "ignored", type: .click, t: 480, points: 100, offsetMs: -12),
            AttemptEvent(attemptId: "ignored", type: .pitch, t: 240, points: 80),
            AttemptEvent(attemptId: "ignored", type: .amplitude, t: 960, points: 40),
        ]
        try db.saveAttempt(attempt("a1"), events: events)

        let back = try db.events(ofAttempt: "a1")
        XCTAssertEqual(back.map(\.t), [240, 480, 960], "vienen ordenados por instante")
        XCTAssertEqual(back.map(\.type), [.pitch, .click, .amplitude])
        XCTAssertEqual(back.first { $0.type == .click }?.offsetMs, -12)
        XCTAssertNil(back.first { $0.type == .pitch }?.offsetMs)
        XCTAssertTrue(back.allSatisfy { $0.attemptId == "a1" }, "saveAttempt rellena el attemptId")
    }

    func testReguardarUnIntentoReemplazaSusEventos() throws {
        let db = try XFDatabase.inMemory()
        try db.saveAttempt(attempt("a1"), events: [
            AttemptEvent(attemptId: "a1", type: .click, t: 1, points: 10),
            AttemptEvent(attemptId: "a1", type: .click, t: 2, points: 10),
        ])
        try db.saveAttempt(attempt("a1", score: 3400), events: [
            AttemptEvent(attemptId: "a1", type: .click, t: 3, points: 100),
        ])

        let back = try db.events(ofAttempt: "a1")
        XCTAssertEqual(back.map(\.t), [3])
        XCTAssertEqual(try db.attempt(id: "a1")?.score, 3400)
    }

    func testBorrarElIntentoSeLlevaLosEventos() throws {
        let db = try XFDatabase.inMemory()
        try db.saveAttempt(attempt("a1"), events: [
            AttemptEvent(attemptId: "a1", type: .click, t: 1, points: 10),
        ])
        try db.writer.write { try Attempt.deleteOne($0, key: "a1") }
        XCTAssertEqual(try db.events(ofAttempt: "a1").count, 0)
    }

    // MARK: - sesión

    func testIntentoConservaLaSesionYSobreviveASuBorrado() throws {
        let db = try XFDatabase.inMemory()
        try db.saveSession(PracticeSession(id: "s1", exerciseId: "ex-l1-baby",
                                           startedAt: t0, finalBpm: 80))
        var a = attempt("a1"); a.sessionId = "s1"
        try db.saveAttempt(a)

        XCTAssertEqual(try db.attempt(id: "a1")?.sessionId, "s1")
        try db.writer.write { try PracticeSession.deleteOne($0, key: "s1") }
        XCTAssertNil(try db.attempt(id: "a1")?.sessionId, "ON DELETE SET NULL")
        XCTAssertNotNil(try db.attempt(id: "a1"), "el intento se queda")
    }
}
