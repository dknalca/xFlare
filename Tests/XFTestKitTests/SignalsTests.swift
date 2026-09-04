// SPDX-License-Identifier: GPL-3.0-only
import XCTest
@testable import XFTestKit

/// `Signals`: generadores sintéticos para tests de audio / timecode.
final class SignalsTests: XCTestCase {

    func testSineLongitudYAmplitud() {
        let s = Signals.sine(freq: 100, seconds: 0.5, sampleRate: 48_000, amplitude: 0.8)
        XCTAssertEqual(s.count, 24_000)
        let peak = s.map { abs($0) }.max() ?? 0
        XCTAssertEqual(Double(peak), 0.8, accuracy: 0.02)
        XCTAssertEqual(s.first, 0, "empieza en fase 0")
    }

    func testSineFrecuenciaPorCrucesPorCero() {
        // 10 Hz, 1 s -> ~20 cruces por cero (2 por ciclo)
        let s = Signals.sine(freq: 10, seconds: 1.0)
        var crossings = 0
        for i in 1..<s.count where (s[i - 1] <= 0) != (s[i] <= 0) { crossings += 1 }
        XCTAssertEqual(crossings, 20, accuracy: 2)
    }

    func testSilence() {
        let s = Signals.silence(seconds: 0.1, sampleRate: 48_000)
        XCTAssertEqual(s.count, 4_800)
        XCTAssertTrue(s.allSatisfy { $0 == 0 })
    }

    func testQuadratureTimecodeFormato() {
        let tc = Signals.quadratureTimecode(carrierHz: 1_000, secondaryPhaseDeg: 90,
                                            seconds: 0.25, sampleRate: 48_000)
        XCTAssertEqual(tc.count, 12_000 * 2, "estéreo intercalado: frames * 2")
        let peak = tc.map { abs(Int($0)) }.max() ?? 0
        XCTAssertGreaterThan(peak, 9_000)          // ~amplitud 10000
        XCTAssertLessThanOrEqual(peak, 10_001)
    }

    func testQuadratureFaseAdelanteVsAtras() {
        // el canal secundario va +90° (adelante) o -90° (atrás): en la primera
        // muestra no nula el signo relativo cambia.
        let fwd = Signals.quadratureTimecode(secondaryPhaseDeg: 90, seconds: 0.01)
        let rev = Signals.quadratureTimecode(secondaryPhaseDeg: -90, seconds: 0.01)
        // canal secundario (índices impares) del 2º frame, ya despegado de 0
        XCTAssertEqual(fwd[3], -rev[3], "±90° -> canal secundario opuesto")
    }

    func testSegundosCeroDaVacio() {
        XCTAssertTrue(Signals.sine(freq: 100, seconds: 0).isEmpty)
        XCTAssertTrue(Signals.quadratureTimecode(seconds: 0).isEmpty)
    }
}
