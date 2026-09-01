// SPDX-License-Identifier: GPL-3.0-only
import XCTest
@testable import XFApp
import XFDesign
import XFEngine

/// B11.3 — barras de la pantalla de práctica (`PracticeHUD`).
final class PracticeHUDTests: XCTestCase {

    private func session(config: SessionConfig = SessionConfig(seriesCount: 3, barsPerSeries: 4)) -> Session {
        Session(config: config,
                ladder: BPMLadder(rungs: [60, 70, 80, 90], startBPM: 80),
                unlock: UnlockTracker(rule: UnlockRule(accuracy: 0.8, consecutiveBars: 8)))
    }

    private func hud(_ s: Session, accuracy: Double? = nil, countIn: Int = 0,
                     offsets: [Double] = [], feedback: String? = nil) -> PracticeHUD {
        PracticeHUD.build(session: s, exerciseName: "2-Click Flare", accuracy: accuracy,
                          countInBarsRemaining: countIn, recentClickOffsetsMs: offsets,
                          liveFeedback: feedback)
    }

    func testCalentamientoNoPuntuaYNoTieneEtiquetaDeSerie() {
        let h = hud(session(), accuracy: 0.9)
        XCTAssertEqual(h.phaseLabel, "Calentamiento")
        XCTAssertNil(h.seriesLabel)
        XCTAssertNil(h.accuracyPercent, "el calentamiento no puntúa")
        XCTAssertEqual(h.bpm, 80)
    }

    func testSerieMuestraLaEtiquetaYElPorcentaje() {
        var s = session()
        s.beginSeries()                 // -> series(0)
        s.recordBar(accuracy: 0.9)
        s.recordBar(accuracy: 0.9)
        s.recordBar(accuracy: 0.9)      // -> series(0) todavía (4 por serie)
        let h = hud(s, accuracy: 0.9412)
        XCTAssertEqual(h.phaseLabel, "Serie 1/3")
        XCTAssertEqual(h.seriesLabel, "Serie 1/3")
        XCTAssertEqual(h.accuracyPercent, 94, "redondea a entero")
    }

    func testDuranteLaCuentaAtrasNoHayPorcentaje() {
        var s = session()
        s.beginSeries()
        let h = hud(s, accuracy: 0.9, countIn: 2)
        XCTAssertTrue(h.isCountingIn)
        XCTAssertNil(h.accuracyPercent)
    }

    func testBossYResultados() {
        var s = session(config: SessionConfig(seriesCount: 1, barsPerSeries: 1))
        s.beginSeries(); s.recordBar(accuracy: 0.9)     // -> boss
        XCTAssertEqual(hud(s, accuracy: 0.8).phaseLabel, "Boss")
        s.recordBoss(accuracy: 0.8)                     // -> results
        let h = hud(s)
        XCTAssertEqual(h.phaseLabel, "Resultados")
        XCTAssertNil(h.seriesLabel)
        XCTAssertNil(h.accuracyPercent)
    }

    func testUltimosClicksSonLosCincoMasRecientesClasificados() {
        var s = session(); s.beginSeries()
        let h = hud(s, accuracy: 0.9, offsets: [5, -80, 200, 15, -45, 8])
        XCTAssertEqual(h.recentClicks.count, 5, "descarta el más antiguo (el 5)")
        XCTAssertEqual(h.recentClicks, [
            .offbeat,   // |-80|
            .miss,      // |200|
            .perfect,   // |15|
            .good,      // |-45|
            .perfect,   // |8|
        ])
    }

    func testFeedbackEnVivoPasaTalCual() {
        var s = session(); s.beginSeries()
        XCTAssertEqual(hud(s, accuracy: 0.9, feedback: "vas un pelín tarde").liveFeedback,
                       "vas un pelín tarde")
        XCTAssertNil(hud(s, accuracy: 0.9).liveFeedback)
    }
}
