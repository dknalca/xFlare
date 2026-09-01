// SPDX-License-Identifier: GPL-3.0-only
import XCTest
@testable import XFPersistence

/// B10.8 — dominado y desbloqueo de variantes.
final class MasteryTests: XCTestCase {

    private let now = Date(timeIntervalSince1970: 1_760_000_000)

    /// Fija las estrellas de una variante metiendo un intento y recalculando.
    private func setStars(_ db: XFDatabase, exercise: String = "ex",
                          variant: String, stars: Int) throws {
        try db.saveAttempt(Attempt(
            id: "\(exercise)-\(variant)-s\(stars)", exerciseId: exercise, variantId: variant,
            mode: .ghost, bpm: 80, startedAt: now, durationMs: 1000,
            score: 3000, maxScore: 3600, accuracy: 0.83, stars: stars))
        try db.recomputeProgress(exerciseId: exercise, variantId: variant)
    }

    // MARK: - dominado

    func testDominadoConTresEstrellasBaseYDosEnTresVariantes() throws {
        let db = try XFDatabase.inMemory()
        try setStars(db, variant: "base", stars: 3)
        try setStars(db, variant: "off25", stars: 2)
        try setStars(db, variant: "off50", stars: 2)

        var m = try db.refreshMastery(exerciseId: "ex", at: now)
        XCTAssertFalse(m.isMastered, "solo 2 variantes fuertes")

        try setStars(db, variant: "amp50", stars: 2)
        m = try db.refreshMastery(exerciseId: "ex", at: now)
        XCTAssertTrue(m.isMastered)
        XCTAssertEqual(m.masteredAt, now)
        XCTAssertEqual(try db.masteredExercises(), ["ex"])
    }

    func testSinTresEstrellasEnBaseNoHayDominio() throws {
        let db = try XFDatabase.inMemory()
        try setStars(db, variant: "base", stars: 2)
        for v in ["off25", "off50", "amp50", "amp150"] { try setStars(db, variant: v, stars: 3) }
        let m = try db.refreshMastery(exerciseId: "ex", at: now)
        XCTAssertFalse(m.isMastered)
    }

    func testElDominioNoSePierde() throws {
        let db = try XFDatabase.inMemory()
        try setStars(db, variant: "base", stars: 3)
        for v in ["off25", "off50", "amp50"] { try setStars(db, variant: v, stars: 2) }
        let first = try db.refreshMastery(exerciseId: "ex", at: now)
        XCTAssertEqual(first.masteredAt, now)

        // recalcular más tarde no mueve la fecha
        let later = try db.refreshMastery(exerciseId: "ex", at: now.addingTimeInterval(99_999))
        XCTAssertEqual(later.masteredAt, now)
    }

    func testOxidacionSePoneYSeQuita() throws {
        let db = try XFDatabase.inMemory()
        try db.setOxidized(exerciseId: "ex", at: now)
        XCTAssertEqual(try db.mastery(exerciseId: "ex")?.oxidizedAt, now)
        try db.setOxidized(exerciseId: "ex", at: nil)
        XCTAssertNil(try db.mastery(exerciseId: "ex")?.oxidizedAt)
    }

    // MARK: - desbloqueo de variantes

    func testEvaluaReglasContraLasEstrellas() throws {
        let db = try XFDatabase.inMemory()
        try setStars(db, variant: "base", stars: 2)

        let rules = [
            VariantUnlockRule(variantId: "off25", requiresVariant: "base", requiresStars: 2),
            VariantUnlockRule(variantId: "off50", requiresVariant: "base", requiresStars: 2),
            VariantUnlockRule(variantId: "mirror", requiresVariant: "base", requiresStars: 3),
            VariantUnlockRule(variantId: "off75", requiresVariant: "off50", requiresStars: 2),
        ]

        let firstPass = try db.evaluateUnlocks(exerciseId: "ex", rules: rules, at: now)
        XCTAssertEqual(Set(firstPass), ["off25", "off50"])
        XCTAssertEqual(try db.unlockedVariants(exerciseId: "ex"), ["off25", "off50"])

        // volver a evaluar no re-desbloquea lo ya hecho
        XCTAssertEqual(try db.evaluateUnlocks(exerciseId: "ex", rules: rules, at: now), [])

        // ahora base a 3★ y off50 a 2★ -> se abren mirror y off75
        try setStars(db, variant: "base", stars: 3)
        try setStars(db, variant: "off50", stars: 2)
        XCTAssertEqual(Set(try db.evaluateUnlocks(exerciseId: "ex", rules: rules, at: now)),
                       ["mirror", "off75"])
    }
}
