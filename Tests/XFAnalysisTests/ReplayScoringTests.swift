// SPDX-License-Identifier: GPL-3.0-only
import XCTest
import XFClock
import XFNotation
@testable import XFAnalysis

/// B8.5 (version sintetica) — good / late / sloppy. Cuando haya `.xfsession`
/// grabados reales, estos tests se repiten contra ellos; de momento generan la
/// toma a partir del patron para probar la logica del scoring.
final class ReplayScoringTests: XCTestCase {

    private func flare2c() throws -> Scratch {
        try Composer.compose(hand: "baby", fader: "flare_2c", division: "1/8", cycles: 4,
                             primitives: try AnalysisFixtures.primitives())
    }

    private func clock(bpm: Double = 90) -> ClockMap {
        ClockMap(anchorHostTime: 2_000_000_000_000, anchorTick: 0,
                 tempo: Tempo(bpm: bpm), host: HostClock(numer: 1, denom: 1))
    }

    /// good: la toma reproduce el patron -> puntua alto y saca 3 estrellas.
    func testGood() throws {
        let sc = try flare2c()
        let take = SyntheticTake.make(for: sc, clock: clock())
        let r = DefaultScorer().score(take, against: sc, atTargetBpm: true)

        XCTAssertGreaterThanOrEqual(r.accuracy, 0.88, "good deberia puntuar >= 0.88, dio \(r.accuracy)")
        XCTAssertEqual(r.missedClicks, 0)
        XCTAssertEqual(r.stars, 3, "reasons: \(r.starReasons)")
        XCTAssertLessThan(abs(r.biasMs), 5)
        XCTAssertLessThan(r.sigmaMs, 8)
        XCTAssertTrue(r.diagnostics.contains { $0.kind == .good })
    }

    /// late: todos los clicks +35 ms -> se detecta SESGO positivo, no dispersion.
    func testLate() throws {
        let sc = try flare2c()
        let take = SyntheticTake.make(for: sc, clock: clock(), clickBiasMs: 35)
        let r = DefaultScorer().score(take, against: sc, atTargetBpm: true)

        XCTAssertEqual(r.missedClicks, 0)
        XCTAssertGreaterThan(r.biasMs, 25, "esperaba sesgo ~+35 ms, dio \(r.biasMs)")
        XCTAssertLessThan(r.sigmaMs, 10, "el sesgo es sistematico: poca dispersion")
        XCTAssertLessThan(r.stars, 3)
        let bias = r.diagnostics.first { $0.kind == .timingBias }
        XCTAssertNotNil(bias, "debe salir un diagnostico de sesgo")
        XCTAssertTrue(bias?.text.contains("tarde") ?? false)
        XCTAssertFalse(r.diagnostics.contains { $0.kind == .timingSpread })
    }

    /// sloppy: jitter de ±45 ms -> puntua bajo y se senala DISPERSION.
    func testSloppy() throws {
        let sc = try flare2c()
        let take = SyntheticTake.make(for: sc, clock: clock(),
                                      clickJitterMs: 45, velocityNoise: 0.02, seed: 99)
        let r = DefaultScorer().score(take, against: sc, atTargetBpm: true)

        XCTAssertLessThanOrEqual(r.accuracy, 0.75, "sloppy deberia puntuar bajo, dio \(r.accuracy)")
        XCTAssertGreaterThan(r.sigmaMs, 18)
        XCTAssertLessThanOrEqual(r.stars, 2)
        XCTAssertTrue(r.diagnostics.contains { $0.kind == .timingSpread },
                      "debe senalar dispersion: \(r.diagnostics.map(\.text))")
    }

    /// clicks perdidos: si el usuario se deja 2, se cuenta y se dice.
    func testClicksPerdidos() throws {
        let sc = try flare2c()
        let take = SyntheticTake.make(for: sc, clock: clock(), dropClickIndices: [3, 9])
        let r = DefaultScorer().score(take, against: sc, atTargetBpm: true)

        XCTAssertEqual(r.missedClicks, 2)
        XCTAssertLessThan(r.stars, 2)   // un evento a 0 -> no llega a 2 estrellas
        XCTAssertTrue(r.diagnostics.contains { $0.kind == .missedClicks })
    }
}
