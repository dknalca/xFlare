// SPDX-License-Identifier: GPL-3.0-only
import XCTest
import XFClock
import XFNotation
@testable import XFAnalysis

final class XFAnalysisTests: XCTestCase {

    func testAPIVersion() {
        XCTAssertEqual(XFAnalysis.apiVersion, 1)
    }

    // MARK: - DTW (B8.2)

    func testDTWSeriesIdenticas() {
        let a = [0.0, 1, 2, 1, 0, -1, -2, -1, 0]
        XCTAssertEqual(DTW.normalizedDistance(a, a), 0, accuracy: 1e-12)
    }

    func testDTWToleraDesplazamientoTemporal() {
        // misma forma, una empieza mas tarde
        let a = [0.0, 0, 1, 2, 1, 0, 0]
        let b = [0.0, 1, 2, 1, 0, 0, 0]
        let d = DTW.normalizedDistance(a, b)
        XCTAssertLessThan(d, 0.05)          // casi 0: es la misma forma
    }

    func testDTWDistingueFormasDistintas() {
        let subeYbaja = [0.0, 1, 2, 1, 0]
        let plano     = [0.0, 0, 0, 0, 0]
        XCTAssertGreaterThan(DTW.normalizedDistance(subeYbaja, plano), 0.1)
    }

    // MARK: - estrellas (B8.7)

    func testEstrellaDosCastigaElFalloSuelto() {
        // 88% pero con un evento a 0 -> NO son 2 estrellas (ADR-025)
        let r = Stars.evaluate(accuracy: 0.88, finished: true, sigmaMs: 10,
                               zeroScoredEvents: 1, atTargetBpm: true)
        XCTAssertEqual(r.count, 1)
        XCTAssertTrue(r.reasons.contains { $0.contains("a 0") })
    }

    func testEstrellaTresExigeRegularidadYTempo() {
        let casi = Stars.evaluate(accuracy: 0.97, finished: true, sigmaMs: 22,
                                  zeroScoredEvents: 0, atTargetBpm: true)
        XCTAssertEqual(casi.count, 2)      // sigma 22 > 15
        let bpm = Stars.evaluate(accuracy: 0.97, finished: true, sigmaMs: 10,
                                 zeroScoredEvents: 0, atTargetBpm: false)
        XCTAssertEqual(bpm.count, 2)       // no al BPM objetivo
        let ok = Stars.evaluate(accuracy: 0.97, finished: true, sigmaMs: 10,
                                zeroScoredEvents: 0, atTargetBpm: true)
        XCTAssertEqual(ok.count, 3)
    }
}
