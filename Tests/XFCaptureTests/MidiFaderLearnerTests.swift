// SPDX-License-Identifier: GPL-3.0-only
import XCTest
@testable import XFCapture

/// F.67 — "aprender" qué CC/canal es el crossfader observando el tráfico
/// mientras se mueve de tope a tope. Puro: bytes sintéticos, sin CoreMIDI.
final class MidiFaderLearnerTests: XCTestCase {

    /// CC en canal `channel` (1-based) con valor `value`.
    private func cc(_ number: Int, value: Int, channel: Int = 1) -> (UInt8, UInt8, UInt8) {
        (UInt8(0xB0 | (channel - 1)), UInt8(number), UInt8(value))
    }

    func testSinMensajesNoHayCandidato() {
        let l = MidiFaderLearner()
        XCTAssertNil(l.bestGuess())
        XCTAssertEqual(l.bestSpanSoFar, 0)
    }

    func testUnBarridoDeTopeATopeSeReconoce() throws {
        let l = MidiFaderLearner()
        for v in stride(from: 0, through: 127, by: 1) {
            let (s, d1, d2) = cc(8, value: v, channel: 16)
            l.ingest(status: s, data1: d1, data2: d2)
        }
        let g = try XCTUnwrap(l.bestGuess())
        XCTAssertEqual(g.channel, 16)
        XCTAssertEqual(g.cc, 8)
        XCTAssertEqual(g.rawMin, 0)
        XCTAssertEqual(g.rawMax, 127)
        XCTAssertEqual(l.bestSpanSoFar, 127)
    }

    func testIgnoraMensajesQueNoSonControlChange() {
        let l = MidiFaderLearner()
        // Note On, no CC: no debe contar como candidato.
        l.ingest(status: 0x90, data1: 8, data2: 100)
        XCTAssertEqual(l.bestSpanSoFar, 0)
    }

    func testElRuidoDeUnBotonCercanoNoGanaAlFaderReal() throws {
        let l = MidiFaderLearner()
        // El fader: barrido casi completo.
        for v in [0, 30, 60, 90, 120, 127] {
            let (s, d1, d2) = cc(8, value: v, channel: 16)
            l.ingest(status: s, data1: d1, data2: d2)
        }
        // Ruido: un pad que manda un par de valores parecidos, rango pequeño.
        for v in [63, 64, 65] {
            let (s, d1, d2) = cc(20, value: v, channel: 1)
            l.ingest(status: s, data1: d1, data2: d2)
        }
        let g = try XCTUnwrap(l.bestGuess())
        XCTAssertEqual(g.cc, 8)
        XCTAssertEqual(g.channel, 16)
    }

    func testSinBarridoSuficienteNoHayGanador() {
        let l = MidiFaderLearner()
        // Roce accidental: apenas se mueve.
        for v in [63, 64, 65] {
            let (s, d1, d2) = cc(28, value: v, channel: 1)
            l.ingest(status: s, data1: d1, data2: d2)
        }
        XCTAssertNil(l.bestGuess(minSpan: 20))
        XCTAssertEqual(l.bestSpanSoFar, 2)
    }

    func testEmpateDeRangoLoDecideElNumeroDeMensajes() throws {
        let l = MidiFaderLearner()
        // Dos candidatos con el mismo rango (0-127), pero uno con más mensajes.
        for v in [0, 127] {
            let (s, d1, d2) = cc(9, value: v, channel: 1)
            l.ingest(status: s, data1: d1, data2: d2)
        }
        for v in Array(stride(from: 0, through: 120, by: 5)) + [127] {
            let (s, d1, d2) = cc(8, value: v, channel: 16)
            l.ingest(status: s, data1: d1, data2: d2)
        }
        let g = try XCTUnwrap(l.bestGuess())
        XCTAssertEqual(g.cc, 8)
        XCTAssertEqual(g.channel, 16, "mismo rango, gana el que trae más mensajes")
    }

    func testResetOlvidaLoAnterior() {
        let l = MidiFaderLearner()
        for v in stride(from: 0, through: 127, by: 1) {
            let (s, d1, d2) = cc(8, value: v, channel: 16)
            l.ingest(status: s, data1: d1, data2: d2)
        }
        XCTAssertNotNil(l.bestGuess())
        l.reset()
        XCTAssertNil(l.bestGuess())
        XCTAssertEqual(l.bestSpanSoFar, 0)
    }
}
