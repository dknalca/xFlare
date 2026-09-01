// SPDX-License-Identifier: GPL-3.0-only
import XCTest
@testable import XFCapture

/// B6.5 — binarizacion del fader con cut-in e histeresis (ADR-017).
final class FaderBinarizerTests: XCTestCase {

    func testAbreYCierraConHisteresis() {
        var b = FaderBinarizer(cutIn: 0.5, hysteresis: 0.1)   // banda 0.45..0.55
        XCTAssertFalse(b.update(rawValue: 0.5))   // dentro de la banda: sigue cerrado
        XCTAssertFalse(b.update(rawValue: 0.54))
        XCTAssertTrue(b.update(rawValue: 0.56))   // supera 0.55 -> abre
        XCTAssertTrue(b.update(rawValue: 0.5))    // dentro de la banda: sigue abierto
        XCTAssertTrue(b.update(rawValue: 0.46))
        XCTAssertFalse(b.update(rawValue: 0.44))  // baja de 0.45 -> cierra
    }

    /// "0 eventos fantasma en 1 min de fader quieto": ruido +-0.03 alrededor del
    /// punto de corte con banda 0.08 no debe producir NI UNA transicion.
    func testFaderQuietoConRuidoNoGeneraEventos() {
        var b = FaderBinarizer(cutIn: 0.5, hysteresis: 0.08, initiallyOpen: false)
        var rng = UInt64(1)
        var transitions = 0
        var last = b.isOpen
        // 60 s a 1 kHz de lecturas
        for _ in 0..<60_000 {
            rng = rng &* 6364136223846793005 &+ 1
            let noise = (Double(rng >> 40) / Double(1 << 24) - 0.5) * 2 * 0.03
            let o = b.update(rawValue: Float(0.5 + noise))
            if o != last { transitions += 1; last = o }
        }
        XCTAssertEqual(transitions, 0, "el ruido no debe cruzar la banda muerta")
    }

    func testHamsterInvierteLaZonaAbierta() {
        var normal = FaderBinarizer(cutIn: 0.5, hysteresis: 0.05)
        var hamster = FaderBinarizer(cutIn: 0.5, hysteresis: 0.05, hamster: true)
        // fader arriba (value alto)
        XCTAssertTrue(normal.update(rawValue: 0.9))    // normal: abierto arriba
        XCTAssertFalse(hamster.update(rawValue: 0.9))  // hamster: cerrado arriba
        // fader abajo
        XCTAssertFalse(normal.update(rawValue: 0.1))
        XCTAssertTrue(hamster.update(rawValue: 0.1))   // hamster: abierto abajo
    }

    func testBinarizeMantieneEstadoYProduceUnSamplePorLectura() {
        var b = FaderBinarizer(cutIn: 0.5, hysteresis: 0.1)
        let raw: [(hostTime: UInt64, value: Float)] = [
            (0, 0.0), (10, 0.7), (20, 0.5), (30, 0.4), (40, 0.5), (50, 0.9),
        ]
        let out = b.binarize(raw)
        XCTAssertEqual(out.map(\.isOpen), [false, true, true, false, false, true])
        XCTAssertEqual(out.count, raw.count)
        XCTAssertEqual(out.map(\.hostTime), [0, 10, 20, 30, 40, 50])
    }
}
