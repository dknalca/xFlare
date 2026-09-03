// SPDX-License-Identifier: GPL-3.0-only
import XCTest
@testable import XFApp

/// TAP tempo puro: golpes -> BPM de la media de los últimos intervalos.
final class TapTempoTests: XCTestCase {

    private let t0 = Date(timeIntervalSinceReferenceDate: 1_000)

    func testUnSoloGolpeNoDaNada() {
        var tap = TapTempo()
        XCTAssertNil(tap.tap(at: t0))
    }

    func testDosGolpesA120BPM() {
        var tap = TapTempo()
        _ = tap.tap(at: t0)
        XCTAssertEqual(tap.tap(at: t0.addingTimeInterval(0.5)), 120)   // 0.5 s -> 120
    }

    func testPromediaVariosGolpes() {
        var tap = TapTempo()
        // 4 golpes espaciados 0.6 s -> 100 BPM
        var last: Int?
        for i in 0..<4 { last = tap.tap(at: t0.addingTimeInterval(0.6 * Double(i))) }
        XCTAssertEqual(last, 100)
    }

    func testUnGolpeSueltoNoTiraLaMedia() {
        var tap = TapTempo()
        // ritmo estable de 0.5 s con UN intervalo raro de 0.55: sigue ~120
        let ts = [0.0, 0.5, 1.0, 1.55, 2.05, 2.55].map { t0.addingTimeInterval($0) }
        var bpm: Int?
        for d in ts { bpm = tap.tap(at: d) }
        XCTAssertNotNil(bpm)
        XCTAssertEqual(Double(bpm!), 118, accuracy: 4)
    }

    func testUnaPausaLargaReiniciaLaCuenta() {
        var tap = TapTempo()
        _ = tap.tap(at: t0)
        _ = tap.tap(at: t0.addingTimeInterval(0.5))          // 120 BPM
        // pausa de 3 s -> se reinicia: el siguiente golpe es el primero de nuevo
        XCTAssertNil(tap.tap(at: t0.addingTimeInterval(3.5)))
        XCTAssertEqual(tap.tap(at: t0.addingTimeInterval(4.3)), 75)   // 0.8 s -> 75
    }

    func testRitmosImposiblesSeDescartan() {
        var tap = TapTempo()
        _ = tap.tap(at: t0)
        // 5 ms entre golpes: fuera de rango (250 BPM tope) -> nil
        XCTAssertNil(tap.tap(at: t0.addingTimeInterval(0.005)))
    }
}
