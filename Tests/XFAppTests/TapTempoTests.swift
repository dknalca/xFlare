// SPDX-License-Identifier: GPL-3.0-only
import XCTest
@testable import XFApp

/// TAP tempo puro: 4-8 golpes -> BPM de la media (recortada) de los intervalos.
final class TapTempoTests: XCTestCase {

    private let t0 = Date(timeIntervalSinceReferenceDate: 1_000)

    /// Da `n` golpes espaciados `gap` s a partir de `t0` y devuelve el último BPM.
    private func run(_ tap: inout TapTempo, gaps: [Double]) -> Int? {
        var t = 0.0
        var out: Int? = tap.tap(at: t0)
        for g in gaps { t += g; out = tap.tap(at: t0.addingTimeInterval(t)) }
        return out
    }

    func testNoDaNadaHastaCuatroGolpes() {
        var tap = TapTempo()
        XCTAssertNil(tap.tap(at: t0))
        XCTAssertNil(tap.tap(at: t0.addingTimeInterval(0.5)))
        XCTAssertNil(tap.tap(at: t0.addingTimeInterval(1.0)))
        XCTAssertEqual(tap.tap(at: t0.addingTimeInterval(1.5)), 120)   // 4º golpe: 0.5 s -> 120
    }

    func testPromediaVariosGolpes() {
        var tap = TapTempo()
        // 6 golpes espaciados 0.6 s -> 100 BPM
        XCTAssertEqual(run(&tap, gaps: [0.6, 0.6, 0.6, 0.6, 0.6]), 100)
    }

    func testUnGolpeFumadoNoTiraLaMedia() {
        var tap = TapTempo()
        // ritmo de 0.5 s con UN intervalo de 0.9 (golpe tardío): la media
        // recortada lo descarta y se queda en ~120, no en ~105.
        let bpm = run(&tap, gaps: [0.5, 0.5, 0.9, 0.5, 0.5, 0.5])
        XCTAssertNotNil(bpm)
        XCTAssertEqual(Double(bpm!), 120, accuracy: 6)
    }

    func testUnaPausaLargaReiniciaLaCuenta() {
        var tap = TapTempo()
        _ = run(&tap, gaps: [0.5, 0.5, 0.5])            // 120 BPM con 4 golpes
        // pausa de 3 s -> reinicia: hacen falta 4 golpes nuevos
        XCTAssertNil(tap.tap(at: t0.addingTimeInterval(4.5)))
        XCTAssertNil(tap.tap(at: t0.addingTimeInterval(5.3)))   // +0.8
        XCTAssertNil(tap.tap(at: t0.addingTimeInterval(6.1)))
        XCTAssertEqual(tap.tap(at: t0.addingTimeInterval(6.9)), 75)   // 0.8 s -> 75
    }

    func testRitmoFueraDeRangoDaNil() {
        var tap = TapTempo()
        // 4 golpes a 5 ms: ~12000 BPM, fuera de [30, 250] -> nil
        XCTAssertNil(run(&tap, gaps: [0.005, 0.005, 0.005]))
    }

    func testMediaRecortadaAisladamente() {
        XCTAssertEqual(TapTempo.trimmedMean([0.5, 0.5, 0.5, 0.9, 0.5])!, 0.5, accuracy: 1e-9)
        XCTAssertNil(TapTempo.trimmedMean([]))
    }
}
