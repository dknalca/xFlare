// SPDX-License-Identifier: GPL-3.0-only
import XCTest
@testable import XFClock

/// B2.2 — transporte: play, stop, loop, cuenta atras. "tests de estado y de
/// limites".
final class TransportTests: XCTestCase {

    func testEstadoInicial() {
        let tr = Transport()
        XCTAssertEqual(tr.state, .stopped)
        XCTAssertEqual(tr.position, 0)
        XCTAssertFalse(tr.isPlaying)
        XCTAssertEqual(tr.bar, 0)
        XCTAssertEqual(tr.countInBarsRemaining, 0)
    }

    func testPlaySinCuentaAtras() {
        var tr = Transport()
        tr.play()
        XCTAssertEqual(tr.state, .playing)
        XCTAssertEqual(tr.position, 0)
        XCTAssertEqual(tr.bar, 1)
    }

    func testPlayConCuentaAtrasDeDosCompases() {
        var tr = Transport()                       // 4/4 -> 1920 ticks/compas
        tr.play(countInBars: 2)
        XCTAssertEqual(tr.state, .countIn)
        XCTAssertEqual(tr.position, -3840)
        XCTAssertEqual(tr.countInBarsRemaining, 2)
        XCTAssertEqual(tr.bar, 0)

        tr.advance(by: 1920)
        XCTAssertEqual(tr.state, .countIn)
        XCTAssertEqual(tr.position, -1920)
        XCTAssertEqual(tr.countInBarsRemaining, 1)

        tr.advance(by: 1920)
        XCTAssertEqual(tr.state, .playing)
        XCTAssertEqual(tr.position, 0)
        XCTAssertEqual(tr.countInBarsRemaining, 0)
        XCTAssertEqual(tr.bar, 1)
    }

    func testCuentaAtrasRedondeaHaciaArriba() {
        var tr = Transport()
        tr.play(countInBars: 2)
        tr.advance(by: 100)                         // aun faltan 3740 ticks
        XCTAssertEqual(tr.countInBarsRemaining, 2)  // ceil(3740/1920) = 2
        tr.advance(by: 1900)                        // faltan 1840
        XCTAssertEqual(tr.countInBarsRemaining, 1)  // ceil(1840/1920) = 1
    }

    func testCuentaAtrasQueSePasaDeCero() {
        var tr = Transport()
        tr.play(countInBars: 1)                     // position -1920
        tr.advance(by: 2000)                        // se pasa 80 ticks
        XCTAssertEqual(tr.state, .playing)
        XCTAssertEqual(tr.position, 80)
    }

    func testStopRebobina() {
        var tr = Transport()
        tr.play()
        tr.advance(by: 5000)
        XCTAssertEqual(tr.position, 5000)
        tr.stop()
        XCTAssertEqual(tr.state, .stopped)
        XCTAssertEqual(tr.position, 0)
    }

    func testAdvanceEnStoppedNoHaceNada() {
        var tr = Transport()
        tr.advance(by: 1000)
        XCTAssertEqual(tr.state, .stopped)
        XCTAssertEqual(tr.position, 0)
    }

    func testAdvanceCeroEsInocuo() {
        var tr = Transport()
        tr.play()
        tr.advance(by: 0)
        XCTAssertEqual(tr.position, 0)
        XCTAssertEqual(tr.state, .playing)
    }

    func testAvanceDeCompases() {
        var tr = Transport()
        tr.play()
        tr.advance(by: 1920)
        XCTAssertEqual(tr.bar, 2)
        tr.advance(by: 1919)
        XCTAssertEqual(tr.bar, 2)                   // aun en el compas 2
        tr.advance(by: 1)
        XCTAssertEqual(tr.bar, 3)
    }

    // MARK: - loop

    func testLoopEnvuelveDesdeCero() {
        var tr = Transport()
        tr.loop = Transport.Loop(start: 0, end: 960)
        tr.play()
        tr.advance(by: 1000)
        XCTAssertEqual(tr.position, 40)             // 1000 % 960
    }

    func testLoopConVariasVueltasEnUnAdvance() {
        var tr = Transport()
        tr.loop = Transport.Loop(start: 0, end: 960)
        tr.play()
        tr.advance(by: 40)
        tr.advance(by: 2500)                        // 40 + 2500 = 2540 ; 2540 % 960 = 620
        XCTAssertEqual(tr.position, 620)
    }

    func testLoopConInicioDesplazado() {
        var tr = Transport()
        tr.loop = Transport.Loop(start: 480, end: 960)   // longitud 480
        tr.play()
        tr.advance(by: 2000)                        // over = 2000-480 = 1520 ; 1520 % 480 = 80
        XCTAssertEqual(tr.position, 560)            // 480 + 80
    }

    func testLoopNoActuaAntesDeLlegarAlFinal() {
        var tr = Transport()
        tr.loop = Transport.Loop(start: 0, end: 960)
        tr.play()
        tr.advance(by: 959)
        XCTAssertEqual(tr.position, 959)            // sin envolver
        tr.advance(by: 1)
        XCTAssertEqual(tr.position, 0)              // 960 % 960
    }

    func testLoopSeAplicaAlSalirDeLaCuentaAtras() {
        var tr = Transport()
        tr.loop = Transport.Loop(start: 0, end: 500)
        tr.play(countInBars: 1)                     // position -1920
        tr.advance(by: 1920 + 1200)                // entra a playing y se pasa: 1200 ; 1200 % 500 = 200
        XCTAssertEqual(tr.state, .playing)
        XCTAssertEqual(tr.position, 200)
    }

    func testLoopStructLength() {
        let l = Transport.Loop(start: 100, end: 340)
        XCTAssertEqual(l.length, 240)
    }

    func testTransportEquatable() {
        var a = Transport()
        var b = Transport()
        XCTAssertEqual(a, b)
        a.play()
        XCTAssertNotEqual(a, b)
        b.play()
        XCTAssertEqual(a, b)
    }
}
