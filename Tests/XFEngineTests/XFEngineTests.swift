// SPDX-License-Identifier: GPL-3.0-only
import XCTest
@testable import XFEngine
import XFTestKit

/// B9.1 — maquina de estados de la sesion (`SessionMachine`).
final class XFEngineTests: XCTestCase {

    func testEnlazaConSusDependencias() {
        // El modulo que orquesta la capa 1 compila y enlaza.
        XCTAssertEqual(XFEngine.apiVersion, 1)
        XCTAssertEqual(XFTestKit.scaffoldingVersion, 0)
    }

    // MARK: - recorrido nominal

    func testRecorridoCompleto3Series() {
        var s = SessionMachine()   // 3 series de 4 compases
        XCTAssertEqual(s.phase, .warmup)
        XCTAssertFalse(s.isScored)

        s.beginSeries()
        XCTAssertEqual(s.phase, .series(index: 0))
        XCTAssertTrue(s.isScored)
        XCTAssertEqual(s.currentSeriesIndex, 0)

        s.completeSeries(passed: true)
        XCTAssertEqual(s.phase, .rest(afterSeries: 0))
        XCTAssertFalse(s.isScored)

        s.endRest()
        XCTAssertEqual(s.phase, .series(index: 1))

        s.completeSeries(passed: false)
        XCTAssertEqual(s.phase, .rest(afterSeries: 1))

        s.endRest()
        XCTAssertEqual(s.phase, .series(index: 2))

        s.completeSeries(passed: true)          // era la ultima -> boss, sin descanso
        XCTAssertEqual(s.phase, .boss)
        XCTAssertTrue(s.isScored)

        s.completeBoss()
        XCTAssertEqual(s.phase, .results)
        XCTAssertTrue(s.isFinished)
        XCTAssertFalse(s.isScored)

        XCTAssertEqual(s.seriesOutcomes, [true, false, true])
        XCTAssertEqual(s.completedSeriesCount, 3)
    }

    func testUltimaSerieVaDirectaAlBossSinDescanso() {
        var s = SessionMachine(config: SessionConfig(seriesCount: 1, barsPerSeries: 4))
        s.beginSeries()
        XCTAssertEqual(s.phase, .series(index: 0))
        s.completeSeries(passed: true)
        XCTAssertEqual(s.phase, .boss, "con una sola serie no hay descanso")
    }

    func testNumeroDeSeriesConfigurable() {
        var s = SessionMachine(config: SessionConfig(seriesCount: 5, barsPerSeries: 2))
        s.beginSeries()
        for i in 0..<4 {
            s.completeSeries(passed: true)
            XCTAssertEqual(s.phase, .rest(afterSeries: i))
            s.endRest()
            XCTAssertEqual(s.phase, .series(index: i + 1))
        }
        s.completeSeries(passed: true)          // 5a serie
        XCTAssertEqual(s.phase, .boss)
        XCTAssertEqual(s.seriesOutcomes.count, 5)
    }

    // MARK: - eventos fuera de orden = no-op

    func testEventosFueraDeOrdenNoHacenNada() {
        var s = SessionMachine()

        s.endRest()                     // en warmup: nada
        XCTAssertEqual(s.phase, .warmup)
        s.completeSeries(passed: true)  // en warmup: nada
        XCTAssertEqual(s.phase, .warmup)
        s.completeBoss()                // en warmup: nada
        XCTAssertEqual(s.phase, .warmup)

        s.beginSeries()
        s.beginSeries()                 // ya no estamos en warmup: nada
        XCTAssertEqual(s.phase, .series(index: 0))
        s.endRest()                     // en serie: nada
        XCTAssertEqual(s.phase, .series(index: 0))

        s.completeSeries(passed: true)
        s.completeSeries(passed: true)  // en descanso: nada, no se duplica el resultado
        XCTAssertEqual(s.phase, .rest(afterSeries: 0))
        XCTAssertEqual(s.seriesOutcomes, [true])
    }

    func testResultsEsTerminal() {
        var s = SessionMachine(config: SessionConfig(seriesCount: 1, barsPerSeries: 1))
        s.beginSeries()
        s.completeSeries(passed: true)
        s.completeBoss()
        XCTAssertEqual(s.phase, .results)

        s.beginSeries(); s.endRest(); s.completeSeries(passed: false); s.completeBoss()
        XCTAssertEqual(s.phase, .results, "desde resultados no se sale salvo reset()")
    }

    // MARK: - reset

    func testResetVuelveAlCalentamiento() {
        var s = SessionMachine(config: SessionConfig(seriesCount: 2, barsPerSeries: 4))
        s.beginSeries()
        s.completeSeries(passed: false)
        s.endRest()
        s.completeSeries(passed: true)
        XCTAssertEqual(s.phase, .boss)
        XCTAssertEqual(s.seriesOutcomes, [false, true])

        s.reset()
        XCTAssertEqual(s.phase, .warmup)
        XCTAssertTrue(s.seriesOutcomes.isEmpty)
        XCTAssertFalse(s.isFinished)

        // y se puede volver a jugar
        s.beginSeries()
        XCTAssertEqual(s.phase, .series(index: 0))
    }

    // MARK: - valor

    func testEsUnValor() {
        var a = SessionMachine()
        a.beginSeries()
        var b = a
        b.completeSeries(passed: true)
        XCTAssertEqual(a.phase, .series(index: 0), "copiar no comparte estado")
        XCTAssertEqual(b.phase, .rest(afterSeries: 0))
    }
}
