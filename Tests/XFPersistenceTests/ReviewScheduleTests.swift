// SPDX-License-Identifier: GPL-3.0-only
import XCTest
@testable import XFPersistence

/// B10.3 — repetición espaciada (1, 3, 7, 21 días).
final class ReviewScheduleTests: XCTestCase {

    private let t0 = Date(timeIntervalSince1970: 1_760_000_000)
    private let day: TimeInterval = 86_400

    func testPrimerRepasoAlDiaSiguiente() throws {
        let db = try XFDatabase.inMemory()
        try db.scheduleReview(exerciseId: "ex", variantId: "base", masteredAt: t0)

        let item = try XCTUnwrap(db.reviewItem(exerciseId: "ex", variantId: "base"))
        XCTAssertEqual(item.stage, 0)
        XCTAssertEqual(item.dueAt, t0.addingTimeInterval(day))
        XCTAssertEqual(item.lastReviewedAt, t0)
    }

    func testScheduleEsIdempotente() throws {
        let db = try XFDatabase.inMemory()
        try db.scheduleReview(exerciseId: "ex", variantId: "base", masteredAt: t0)
        try db.scheduleReview(exerciseId: "ex", variantId: "base",
                              masteredAt: t0.addingTimeInterval(999))
        XCTAssertEqual(try db.reviewItem(exerciseId: "ex", variantId: "base")?.dueAt,
                       t0.addingTimeInterval(day))
    }

    func testAprobarSubeLaEscaleraHasta21() throws {
        let db = try XFDatabase.inMemory()
        try db.scheduleReview(exerciseId: "ex", variantId: "base", masteredAt: t0)

        var when = t0.addingTimeInterval(day)
        let esperado = [3, 7, 21, 21]   // stage 1,2,3,3
        for (i, days) in esperado.enumerated() {
            let item = try db.recordReviewOutcome(exerciseId: "ex", variantId: "base",
                                                  passed: true, at: when)
            XCTAssertEqual(item.stage, min(i + 1, 3))
            XCTAssertEqual(item.dueAt, when.addingTimeInterval(Double(days) * day),
                           "tras \(i + 1) aprobados, +\(days) días")
            when = item.dueAt
        }
    }

    func testFallarVuelveAlEscalon0() throws {
        let db = try XFDatabase.inMemory()
        try db.scheduleReview(exerciseId: "ex", variantId: "base", masteredAt: t0)
        _ = try db.recordReviewOutcome(exerciseId: "ex", variantId: "base", passed: true, at: t0)
        _ = try db.recordReviewOutcome(exerciseId: "ex", variantId: "base", passed: true, at: t0)
        XCTAssertEqual(try db.reviewItem(exerciseId: "ex", variantId: "base")?.stage, 2)

        let item = try db.recordReviewOutcome(exerciseId: "ex", variantId: "base",
                                              passed: false, at: t0)
        XCTAssertEqual(item.stage, 0)
        XCTAssertEqual(item.dueAt, t0.addingTimeInterval(day))
    }

    func testOutcomeSinFilaLaCreaAlVuelo() throws {
        let db = try XFDatabase.inMemory()
        let item = try db.recordReviewOutcome(exerciseId: "ex", variantId: "div16",
                                              passed: true, at: t0)
        XCTAssertEqual(item.stage, 1)
        XCTAssertEqual(item.dueAt, t0.addingTimeInterval(3 * day))
    }

    func testDueReviewsDevuelveSoloLoVencidoOrdenado() throws {
        let db = try XFDatabase.inMemory()
        try db.scheduleReview(exerciseId: "ex", variantId: "a", masteredAt: t0)                 // due t0+1d
        try db.scheduleReview(exerciseId: "ex", variantId: "b", masteredAt: t0 - 5 * day)       // due t0-4d
        try db.scheduleReview(exerciseId: "ex", variantId: "c", masteredAt: t0 + 10 * day)      // due t0+11d

        let due = try db.dueReviews(asOf: t0.addingTimeInterval(2 * day))
        XCTAssertEqual(due.map(\.variantId), ["b", "a"], "vencido primero, futuro fuera")
    }
}
