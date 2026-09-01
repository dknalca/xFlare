// SPDX-License-Identifier: GPL-3.0-only
import XCTest
@testable import XFEngine

/// B9.4 — `Session`, el facade que cablea `SessionMachine` + `BPMLadder` +
/// `UnlockTracker`.
final class SessionTests: XCTestCase {

    // Ejercicio de juguete: 3 series de 2 compases, escalera 60..100 desde 80,
    // desbloqueo a 0.8 en 4 compases seguidos sin gate de BPM.
    private func makeSession() -> Session {
        Session(
            config: SessionConfig(seriesCount: 3, barsPerSeries: 2),
            ladder: BPMLadder(rungs: [60, 70, 80, 90, 100], startBPM: 80),
            unlock: UnlockTracker(rule: UnlockRule(accuracy: 0.8, consecutiveBars: 4))
        )
    }

    /// Registra `n` compases limpios (0.95) en la serie en curso.
    private func playCleanBars(_ s: inout Session, _ n: Int) {
        for _ in 0..<n { s.recordBar(accuracy: 0.95) }
    }

    // MARK: - recorrido completo

    func testRecorridoNominalConDesbloqueo() {
        var s = makeSession()
        XCTAssertEqual(s.phase, .warmup)
        XCTAssertEqual(s.currentBPM, 80)

        // los compases de calentamiento se ignoran
        XCTAssertEqual(s.recordBar(accuracy: 0.9), .ignored)

        s.beginSeries()
        XCTAssertEqual(s.phase, .series(index: 0))

        // serie 0: 1er compas -> sigue; 2o -> cierra la serie, aprobada
        XCTAssertEqual(s.recordBar(accuracy: 0.9), .barRecorded)
        XCTAssertEqual(s.recordBar(accuracy: 0.9), .seriesEnded(passed: true, bpmStep: .hold))
        XCTAssertEqual(s.phase, .rest(afterSeries: 0))

        s.endRest()
        XCTAssertEqual(s.phase, .series(index: 1))
        playCleanBars(&s, 2)                       // serie 1 aprobada; ya van 4 compases buenos seguidos
        XCTAssertTrue(s.isUnlocked, "4 compases seguidos >= umbral -> desbloqueo")
        XCTAssertEqual(s.phase, .rest(afterSeries: 1))

        s.endRest()
        playCleanBars(&s, 2)                       // serie 2 (ultima): 3a aprobada seguida -> boss
        XCTAssertEqual(s.phase, .boss)
        XCTAssertEqual(s.currentBPM, 90, "3 series aprobadas seguidas -> sube un escalon")

        XCTAssertNil(s.summary)
        s.recordBoss(accuracy: 0.7)
        XCTAssertEqual(s.phase, .results)

        let sum = try! XCTUnwrap(s.summary)
        XCTAssertEqual(sum.seriesOutcomes, [true, true, true])
        XCTAssertEqual(sum.finalBPM, 90)
        XCTAssertEqual(sum.bossAccuracy, 0.7)
        XCTAssertTrue(sum.unlocked)
        XCTAssertGreaterThanOrEqual(sum.bestStreak, 6)
    }

    // MARK: - serie: aprueba por streak, no por media

    func testUnCompasFlojoSuspendeLaSerieAunqueLaMediaSeaAlta() {
        var s = makeSession()
        s.beginSeries()
        s.recordBar(accuracy: 0.99)
        let ev = s.recordBar(accuracy: 0.6)       // media 0.795, pero un compas flojo
        XCTAssertEqual(ev, .seriesEnded(passed: false, bpmStep: .hold))
    }

    // MARK: - la escalera se mueve con el resultado de las series

    func testDosSeriesSuspendidasBajanElBPM() {
        var s = makeSession()
        s.beginSeries()

        // serie 0 suspendida
        s.recordBar(accuracy: 0.9)
        XCTAssertEqual(s.recordBar(accuracy: 0.2), .seriesEnded(passed: false, bpmStep: .hold))
        s.endRest()
        // serie 1 suspendida -> 2 seguidas -> baja
        s.recordBar(accuracy: 0.9)
        XCTAssertEqual(s.recordBar(accuracy: 0.2), .seriesEnded(passed: false, bpmStep: .down))
        XCTAssertEqual(s.currentBPM, 70, "el BPM de la serie 2 ya es el nuevo")
    }

    func testTresSeriesAprobadasSubenElBPM() {
        // 3 series de 1 compas para encadenar 3 aprobados limpios
        var s = Session(
            config: SessionConfig(seriesCount: 3, barsPerSeries: 1),
            ladder: BPMLadder(rungs: [60, 70, 80], startBPM: 70),
            unlock: UnlockTracker(rule: UnlockRule(accuracy: 0.8, consecutiveBars: 99))
        )
        s.beginSeries()
        XCTAssertEqual(s.recordBar(accuracy: 0.9), .seriesEnded(passed: true, bpmStep: .hold))
        s.endRest()
        XCTAssertEqual(s.recordBar(accuracy: 0.9), .seriesEnded(passed: true, bpmStep: .hold))
        s.endRest()
        XCTAssertEqual(s.recordBar(accuracy: 0.9), .seriesEnded(passed: true, bpmStep: .up))
        XCTAssertEqual(s.currentBPM, 80)
    }

    // MARK: - gate de BPM del desbloqueo

    func testDesbloqueoRespetaElMinBPM() {
        var s = Session(
            config: SessionConfig(seriesCount: 3, barsPerSeries: 2),
            ladder: BPMLadder(rungs: [60, 70, 80], startBPM: 60),
            unlock: UnlockTracker(rule: UnlockRule(accuracy: 0.8, consecutiveBars: 2, minBPM: 70))
        )
        s.beginSeries()
        playCleanBars(&s, 2)                       // serie a 60 BPM: precisa pero lenta
        XCTAssertFalse(s.isUnlocked, "la racha a 60 no cuenta para el desbloqueo (minBPM 70)")
        // subimos el BPM aprobando 3 series... aqui basta forzar: no es el foco del test
    }

    // MARK: - boss y reset

    func testRecordBossFueraDeFaseNoHaceNada() {
        var s = makeSession()
        s.recordBoss(accuracy: 0.9)
        XCTAssertEqual(s.phase, .warmup)
        XCTAssertNil(s.summary)
    }

    func testResetDejaTodoComoAlPrincipio() {
        var s = makeSession()
        s.beginSeries()
        playCleanBars(&s, 2); s.endRest()
        playCleanBars(&s, 2)
        XCTAssertTrue(s.isUnlocked)

        s.reset()
        XCTAssertEqual(s.phase, .warmup)
        XCTAssertEqual(s.currentBPM, 80)
        XCTAssertFalse(s.isUnlocked)
        XCTAssertEqual(s.barsToUnlock, 4)
        XCTAssertNil(s.summary)

        // y se puede jugar otra vez
        s.beginSeries()
        XCTAssertEqual(s.recordBar(accuracy: 0.9), .barRecorded)
    }

    func testEsUnValor() {
        var a = makeSession()
        a.beginSeries()
        a.recordBar(accuracy: 0.9)
        var b = a
        b.recordBar(accuracy: 0.9)                 // cierra la serie en b, no en a
        XCTAssertEqual(a.phase, .series(index: 0))
        XCTAssertEqual(b.phase, .rest(afterSeries: 0))
    }
}
