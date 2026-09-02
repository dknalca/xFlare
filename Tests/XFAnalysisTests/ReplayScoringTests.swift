// SPDX-License-Identifier: GPL-3.0-only
import XCTest
import XFClock
import XFNotation
@testable import XFAnalysis

/// B8.5 (versión sintética) — good / late / sloppy **por patrón de nivel 1-4**
/// (`docs/TESTING.md` §"Tests de replay"). Cuando haya `.xfsession` grabados
/// reales (bloqueado por hardware), estos tests se repiten contra ellos; de
/// momento `SyntheticTake` genera la toma a partir del patrón para fijar el
/// comportamiento del scoring en todo el rango de complejidad, no solo en un
/// flare.
final class ReplayScoringTests: XCTestCase {

    private func compose(_ hand: String, _ fader: String,
                         division: String = "1/8", cycles: Int = 4) throws -> Scratch {
        try Composer.compose(hand: hand, fader: fader, division: division, cycles: cycles,
                             primitives: try AnalysisFixtures.primitives())
    }

    private func flare2c() throws -> Scratch { try compose("baby", "flare_2c") }

    private func clock(bpm: Double = 90) -> ClockMap {
        ClockMap(anchorHostTime: 2_000_000_000_000, anchorTick: 0,
                 tempo: Tempo(bpm: bpm), host: HostClock(numer: 1, denom: 1))
    }

    // MARK: - la batería good / late / sloppy, parametrizada por patrón

    /// Corre las tres tomas sintéticas contra `sc` y comprueba el comportamiento
    /// esperado del scoring. Los umbrales absolutos son holgados (los finos son
    /// B8.4); lo que se fija con firmeza son las **invariantes**: good ≫ sloppy,
    /// late = sesgo (no dispersión), sloppy = dispersión.
    private func runReplaySuite(_ label: String, _ sc: Scratch,
                                file: StaticString = #filePath, line: UInt = #line) {
        let scorer = DefaultScorer()

        // --- good: la toma reproduce el patrón ---
        let good = scorer.score(SyntheticTake.make(for: sc, clock: clock()),
                                against: sc, atTargetBpm: true)
        XCTAssertGreaterThanOrEqual(good.accuracy, 0.85,
            "\(label) good debería puntuar ≥ 0.85, dio \(good.accuracy)", file: file, line: line)
        XCTAssertEqual(good.missedClicks, 0, "\(label) good sin clicks perdidos", file: file, line: line)
        XCTAssertLessThan(abs(good.biasMs), 8, "\(label) good casi sin sesgo", file: file, line: line)
        XCTAssertLessThan(good.sigmaMs, 12, "\(label) good regular", file: file, line: line)
        XCTAssertGreaterThanOrEqual(good.stars, 2,
            "\(label) good ≥ 2 estrellas (reasons: \(good.starReasons))", file: file, line: line)

        // --- late: todos los clicks +35 ms -> SESGO, no dispersión ---
        let late = scorer.score(SyntheticTake.make(for: sc, clock: clock(), clickBiasMs: 35),
                                against: sc, atTargetBpm: true)
        XCTAssertEqual(late.missedClicks, 0, "\(label) late sin clicks perdidos", file: file, line: line)
        XCTAssertGreaterThan(late.biasMs, 20,
            "\(label) late: sesgo ~+35 ms, dio \(late.biasMs)", file: file, line: line)
        XCTAssertLessThan(late.sigmaMs, 16,
            "\(label) late: el sesgo es sistemático, poca dispersión (σ=\(late.sigmaMs))", file: file, line: line)
        XCTAssertTrue(late.diagnostics.contains { $0.kind == .timingBias },
            "\(label) late debe señalar sesgo: \(late.diagnostics.map(\.text))", file: file, line: line)
        XCTAssertFalse(late.diagnostics.contains { $0.kind == .timingSpread },
            "\(label) late NO es dispersión", file: file, line: line)

        // --- sloppy: jitter ±45 ms -> DISPERSIÓN y peor puntuación ---
        let sloppy = scorer.score(
            SyntheticTake.make(for: sc, clock: clock(), clickJitterMs: 45,
                               velocityNoise: 0.02, seed: 99),
            against: sc, atTargetBpm: true)
        XCTAssertGreaterThan(sloppy.sigmaMs, 20,
            "\(label) sloppy: mucha dispersión (σ=\(sloppy.sigmaMs))", file: file, line: line)
        XCTAssertTrue(sloppy.diagnostics.contains { $0.kind == .timingSpread },
            "\(label) sloppy debe señalar dispersión: \(sloppy.diagnostics.map(\.text))", file: file, line: line)
        XCTAssertLessThanOrEqual(sloppy.stars, 2, "\(label) sloppy ≤ 2 estrellas", file: file, line: line)

        // --- invariante fuerte: good es claramente mejor que sloppy ---
        XCTAssertGreaterThan(good.accuracy, sloppy.accuracy + 0.15,
            "\(label): good (\(good.accuracy)) debe superar a sloppy (\(sloppy.accuracy)) con margen",
            file: file, line: line)
        XCTAssertEqual(good.stars, 3,
            "\(label) good al BPM objetivo saca 3 estrellas (reasons: \(good.starReasons))",
            file: file, line: line)
    }

    /// L1 — corte simple hacia delante: pocos clicks, gesto básico.
    func testReplayNivel1_forwardCut() throws {
        try runReplaySuite("L1 forward-cut", compose("baby", "forward_cut"))
    }

    /// L2 — transformer de 2: fader troceado, clicks regulares.
    func testReplayNivel2_transformer2() throws {
        try runReplaySuite("L2 transformer-2", compose("baby", "transformer_2"))
    }

    /// L3 — flare de 1 click: un cierre breve por movimiento.
    func testReplayNivel3_flare1c() throws {
        try runReplaySuite("L3 flare-1c", compose("baby", "flare_1c"))
    }

    /// L4 — flare de 2 clicks: el patrón más denso de la batería.
    func testReplayNivel4_flare2c() throws {
        try runReplaySuite("L4 flare-2c", flare2c())
    }

    // MARK: - casos concretos

    /// clicks perdidos: si el usuario se deja 2, se cuenta y se dice.
    func testClicksPerdidos() throws {
        let sc = try flare2c()
        let take = SyntheticTake.make(for: sc, clock: clock(), dropClickIndices: [3, 9])
        let r = DefaultScorer().score(take, against: sc, atTargetBpm: true)

        XCTAssertEqual(r.missedClicks, 2)
        XCTAssertLessThan(r.stars, 2)   // un evento a 0 -> no llega a 2 estrellas
        XCTAssertTrue(r.diagnostics.contains { $0.kind == .missedClicks })
    }

    /// toma que se corta antes de acabar el patron: los checkpoints posteriores
    /// al ultimo sample NO deben reventar (resta de `UInt64` con underflow en
    /// `MotionResampler.velocity`). Antes de esto crasheaba con SIGILL.
    func testTomaMasCortaQueElPatronNoRevienta() throws {
        let sc = try flare2c()
        let full = SyntheticTake.make(for: sc, clock: clock())
        // deja solo el primer tercio de las muestras de movimiento
        let cut = max(2, full.motion.count / 3)
        let short = Take(motion: Array(full.motion.prefix(cut)),
                         fader: full.fader, clock: full.clock)

        let r = DefaultScorer().score(short, against: sc, atTargetBpm: true)
        XCTAssertFalse(r.finished)
        XCTAssertGreaterThanOrEqual(r.score, 0)
        XCTAssertLessThanOrEqual(r.score, r.maxScore)

        // y el resampler devuelve el extremo, no revienta, pasado el ultimo sample
        let past = short.motion.last!.hostTime + 10_000_000
        XCTAssertEqual(MotionResampler.velocity(short.motion, atHostTime: past),
                       short.motion.last!.velocity)
    }
}
