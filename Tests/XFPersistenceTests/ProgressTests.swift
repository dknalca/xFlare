// SPDX-License-Identifier: GPL-3.0-only
import XCTest
@testable import XFPersistence

/// B10.7 — progreso agregado (`docs/SCORING.md` §3).
final class ProgressTests: XCTestCase {

    private let t0 = Date(timeIntervalSince1970: 1_760_000_000)

    private func save(_ db: XFDatabase, _ id: String, score: Int, stars: Int,
                      bpm: Double = 70, bias: Double? = nil, at s: TimeInterval,
                      dur: Double = 10_000, counts: Bool = true) throws {
        try db.saveAttempt(Attempt(
            id: id, exerciseId: "ex", variantId: "base", mode: counts ? .ghost : .warmup,
            bpm: bpm, startedAt: t0.addingTimeInterval(s), durationMs: dur,
            score: score, maxScore: 3600, accuracy: Double(score) / 3600,
            stars: stars, biasMs: bias, countsForStars: counts))
    }

    func testAgregaMejorUltimaEstrellasYSesgo() throws {
        let db = try XFDatabase.inMemory()
        try save(db, "a1", score: 3000, stars: 2, bias: -20, at: 0)
        try save(db, "a2", score: 3500, stars: 3, bpm: 80, bias: -10, at: 100)
        try save(db, "a3", score: 3200, stars: 2, bias:  -6, at: 200)

        let p = try db.recomputeProgress(exerciseId: "ex", variantId: "base")
        XCTAssertEqual(p.attempts, 3)
        XCTAssertEqual(p.bestScore, 3500)
        XCTAssertEqual(p.bestScoreAt, t0.addingTimeInterval(100))
        XCTAssertEqual(p.lastScore, 3200)
        XCTAssertEqual(p.lastAttemptAt, t0.addingTimeInterval(200))
        XCTAssertEqual(p.stars, 3, "el máximo, no baja")
        XCTAssertEqual(p.bestBpmWith3Stars, 80)
        XCTAssertEqual(try XCTUnwrap(p.meanBiasMs), -12, accuracy: 1e-9)
        XCTAssertEqual(p.totalPracticeMs, 30_000)
    }

    func testElCalentamientoNoCuentaParaEstrellasPeroSiParaElTiempo() throws {
        let db = try XFDatabase.inMemory()
        try save(db, "real", score: 3000, stars: 2, at: 0, dur: 10_000, counts: true)
        try save(db, "warm", score: 3500, stars: 3, at: 100, dur: 5_000, counts: false)

        let p = try db.recomputeProgress(exerciseId: "ex", variantId: "base")
        XCTAssertEqual(p.attempts, 1, "solo el que cuenta")
        XCTAssertEqual(p.bestScore, 3000, "la toma de calentamiento no sube el techo")
        XCTAssertEqual(p.stars, 2)
        XCTAssertNil(p.bestBpmWith3Stars, "el 3★ era de calentamiento")
        XCTAssertEqual(p.totalPracticeMs, 15_000, "pero el tiempo sí suma todo")
    }

    func testSinTresEstrellasNoHayMejorBpm() throws {
        let db = try XFDatabase.inMemory()
        try save(db, "a1", score: 3000, stars: 2, at: 0)
        let p = try db.recomputeProgress(exerciseId: "ex", variantId: "base")
        XCTAssertNil(p.bestBpmWith3Stars)
        XCTAssertNil(p.meanBiasMs, "no había ningún biasMs")
    }

    func testMediaDe5YLineaDe20() throws {
        let db = try XFDatabase.inMemory()
        for i in 0..<8 {
            try save(db, "a\(i)", score: 3000 + i * 10, stars: 2, at: Double(i) * 10)
        }
        try db.recomputeProgress(exerciseId: "ex", variantId: "base")
        let sum = try XCTUnwrap(db.progressSummary(exerciseId: "ex", variantId: "base"))

        // últimos 5 = a3..a7 -> 3030,3040,3050,3060,3070 -> media 3050
        XCTAssertEqual(try XCTUnwrap(sum.averageOfLast5), 3050, accuracy: 1e-9)
        // línea de los últimos 20 (aquí 8), del más antiguo al más reciente
        XCTAssertEqual(sum.recentScores, (0..<8).map { 3000 + $0 * 10 })
        XCTAssertEqual(sum.progress.attempts, 8)
    }

    func testProgressSummaryEsNilSinFila() throws {
        let db = try XFDatabase.inMemory()
        XCTAssertNil(try db.progressSummary(exerciseId: "ex", variantId: "base"))
    }

    func testRecomputeEsRepetible() throws {
        let db = try XFDatabase.inMemory()
        try save(db, "a1", score: 3000, stars: 2, at: 0)
        let p1 = try db.recomputeProgress(exerciseId: "ex", variantId: "base")
        let p2 = try db.recomputeProgress(exerciseId: "ex", variantId: "base")
        XCTAssertEqual(p1, p2)
        XCTAssertEqual(try db.progress(exerciseId: "ex", variantId: "base"), p2)
    }
}
