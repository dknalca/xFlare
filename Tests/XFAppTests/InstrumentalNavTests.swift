// SPDX-License-Identifier: GPL-3.0-only

import XCTest
@testable import XFApp

final class InstrumentalNavTests: XCTestCase {

    // MARK: - relativeCue

    func testCueSiguienteYAnterior() {
        let cues = [2.0, 5.0, 9.0]
        XCTAssertEqual(InstrumentalNav.relativeCue(cues: cues, hereSeconds: 3.0, dir: 1), 5.0)
        XCTAssertEqual(InstrumentalNav.relativeCue(cues: cues, hereSeconds: 6.0, dir: -1), 5.0)
    }

    func testCueDaLaVueltaEnLosExtremos() {
        let cues = [2.0, 5.0, 9.0]
        // más allá del último -> vuelve al primero
        XCTAssertEqual(InstrumentalNav.relativeCue(cues: cues, hereSeconds: 12.0, dir: 1), 2.0)
        // antes del primero -> salta al último
        XCTAssertEqual(InstrumentalNav.relativeCue(cues: cues, hereSeconds: 0.5, dir: -1), 9.0)
    }

    func testCueIgnoraElActualPorEpsilon() {
        let cues = [2.0, 5.0, 9.0]
        // justo encima del 5 -> "siguiente" es el 9, no el 5 otra vez
        XCTAssertEqual(InstrumentalNav.relativeCue(cues: cues, hereSeconds: 5.01, dir: 1), 9.0)
    }

    func testCueAceptaListaDesordenadaYVacia() {
        XCTAssertEqual(InstrumentalNav.relativeCue(cues: [9.0, 2.0, 5.0], hereSeconds: 3.0, dir: 1), 5.0)
        XCTAssertNil(InstrumentalNav.relativeCue(cues: [], hereSeconds: 0, dir: 1))
    }

    // MARK: - cycledLoopIndex

    func testCicloDeLoopsHaciaDelante() {
        XCTAssertEqual(InstrumentalNav.cycledLoopIndex(current: nil, count: 3, dir: 1), 0)
        XCTAssertEqual(InstrumentalNav.cycledLoopIndex(current: 0, count: 3, dir: 1), 1)
        XCTAssertEqual(InstrumentalNav.cycledLoopIndex(current: 2, count: 3, dir: 1), 0)   // da la vuelta
    }

    func testCicloDeLoopsHaciaAtras() {
        XCTAssertEqual(InstrumentalNav.cycledLoopIndex(current: nil, count: 3, dir: -1), 2)
        XCTAssertEqual(InstrumentalNav.cycledLoopIndex(current: 0, count: 3, dir: -1), 2)  // da la vuelta
        XCTAssertEqual(InstrumentalNav.cycledLoopIndex(current: 2, count: 3, dir: -1), 1)
    }

    func testCicloSinRegiones() {
        XCTAssertNil(InstrumentalNav.cycledLoopIndex(current: nil, count: 0, dir: 1))
    }
}
