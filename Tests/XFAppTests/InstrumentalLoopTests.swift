// SPDX-License-Identifier: GPL-3.0-only
import XCTest
@testable import XFApp

/// "Modo loop" de una instrumental subida: el fichero es un bucle de N compases
/// a velocidad natural y el BPM de la rejilla se deriva para que cuadre.
final class InstrumentalLoopTests: XCTestCase {

    func testLockedDerivaElBPMDeLosCompasesYLaDuracion() {
        // 4 compases 4/4 en 8 s -> 16 negras en 8 s -> 120 BPM
        let loop = InstrumentalLoop.locked(bars: 4, fileSeconds: 8.0,
                                           beatsPerBar: 4, ppq: 480)
        XCTAssertEqual(loop.bars, 4)
        XCTAssertEqual(loop.bpm, 120, accuracy: 1e-6)
        XCTAssertEqual(loop.loopTicks, 16 * 480, accuracy: 1e-6)
    }

    func testLockedAcotaLosCompasesA1_32() {
        XCTAssertEqual(InstrumentalLoop.locked(bars: 0,   fileSeconds: 4, beatsPerBar: 4, ppq: 480).bars, 1)
        XCTAssertEqual(InstrumentalLoop.locked(bars: 999, fileSeconds: 4, beatsPerBar: 4, ppq: 480).bars, 32)
    }

    func testGuessUsaLasNegrasDelAnalisis() {
        // 8 negras detectadas en 4 s = 2 compases a 120 BPM
        let loop = InstrumentalLoop.guess(fileSeconds: 4.0, beatsPerBar: 4,
                                          ppq: 480, analyzedBeats: 8)
        XCTAssertEqual(loop.bars, 2)
        XCTAssertEqual(loop.bpm, 120, accuracy: 1e-6)
    }

    func testGuessSinAnalisisSuponeTemposRazonables() {
        // sin tempo: ~2 s por compás -> un fichero de 4 s ≈ 2 compases, 120 BPM
        let loop = InstrumentalLoop.guess(fileSeconds: 4.0, beatsPerBar: 4,
                                          ppq: 480, analyzedBeats: nil)
        XCTAssertEqual(loop.bars, 2)
        XCTAssertGreaterThanOrEqual(loop.bpm, 70)
        XCTAssertLessThanOrEqual(loop.bpm, 180)
    }

    func testGuessCorrigeElDobleTiempo() {
        // el análisis dice 16 negras en 8 s (240 BPM: doble tiempo). Partiéndolo
        // a 2 compases (8 negras) baja a 60... sigue < 70, así que 4 compases:
        // realmente 8 s con 4 compases = 16 negras = 120 BPM. Debe caer en rango.
        let loop = InstrumentalLoop.guess(fileSeconds: 8.0, beatsPerBar: 4,
                                          ppq: 480, analyzedBeats: 32)
        XCTAssertGreaterThanOrEqual(loop.bpm, 70)
        XCTAssertLessThanOrEqual(loop.bpm, 180)
        // y los ticks siguen siendo coherentes con los compases elegidos
        XCTAssertEqual(loop.loopTicks, Double(loop.bars * 4 * 480), accuracy: 1e-6)
    }

    func testGuessCorrigeElMedioTiempo() {
        // 2 negras en 4 s = 30 BPM (medio tiempo). Debe doblar hasta rango.
        let loop = InstrumentalLoop.guess(fileSeconds: 4.0, beatsPerBar: 4,
                                          ppq: 480, analyzedBeats: 2)
        XCTAssertGreaterThanOrEqual(loop.bpm, 70)
        XCTAssertLessThanOrEqual(loop.bpm, 180)
    }
}
