// SPDX-License-Identifier: GPL-3.0-only
import XCTest
@testable import XFEngine

/// B9.2 — escalera de BPM adaptativa (`docs/CURRICULUM.md` §3).
final class BPMLadderTests: XCTestCase {

    private func ladder(start: Int = 80) -> BPMLadder {
        BPMLadder(rungs: [60, 70, 80, 90, 100], startBPM: start)
    }

    func testArranqueEnElEscalonPedido() {
        let l = ladder(start: 80)
        XCTAssertEqual(l.currentBPM, 80)
        XCTAssertFalse(l.isAtTop)
        XCTAssertFalse(l.isAtBottom)
    }

    // MARK: - subir

    func testTresAprobadosSeguidosSuben() {
        var l = ladder(start: 80)
        XCTAssertEqual(l.record(passed: true), .hold)
        XCTAssertEqual(l.record(passed: true), .hold)
        XCTAssertEqual(l.record(passed: true), .up)
        XCTAssertEqual(l.currentBPM, 90)
    }

    func testHacenFaltaTRESseguidos_unFalloReiniciaLaRacha() {
        var l = ladder(start: 80)
        l.record(passed: true)
        l.record(passed: true)
        XCTAssertEqual(l.record(passed: false), .hold)   // corta la racha (1 fallo, no baja)
        l.record(passed: true)
        l.record(passed: true)
        XCTAssertEqual(l.record(passed: true), .up)       // ahora sí, 3 limpios
        XCTAssertEqual(l.currentBPM, 90)
    }

    func testSubidasEncadenadas() {
        var l = ladder(start: 60)
        for _ in 0..<9 { l.record(passed: true) }         // 3 subidas: 60 -> 70 -> 80 -> 90
        XCTAssertEqual(l.currentBPM, 90)
    }

    // MARK: - bajar

    func testDosFallosSeguidosBajan() {
        var l = ladder(start: 80)
        XCTAssertEqual(l.record(passed: false), .hold)
        XCTAssertEqual(l.record(passed: false), .down)
        XCTAssertEqual(l.currentBPM, 70)
    }

    func testUnAprobadoCortaLaRachaDeFallos() {
        var l = ladder(start: 80)
        l.record(passed: false)
        XCTAssertEqual(l.record(passed: true), .hold)     // corta
        XCTAssertEqual(l.record(passed: false), .hold)    // vuelve a empezar
        XCTAssertEqual(l.record(passed: false), .down)
        XCTAssertEqual(l.currentBPM, 70)
    }

    // MARK: - topes

    func testNoSubeDelTecho() {
        var l = ladder(start: 100)
        XCTAssertTrue(l.isAtTop)
        l.record(passed: true)
        l.record(passed: true)
        XCTAssertEqual(l.record(passed: true), .hold, "en el techo no se mueve")
        XCTAssertEqual(l.currentBPM, 100)
    }

    func testNoBajaDelSuelo() {
        var l = ladder(start: 60)
        XCTAssertTrue(l.isAtBottom)
        l.record(passed: false)
        XCTAssertEqual(l.record(passed: false), .hold, "en el suelo no se mueve")
        XCTAssertEqual(l.currentBPM, 60)
    }

    func testEnElTechoElContadorSeReinicia_noDisparaEnCadaSerie() {
        var l = ladder(start: 90)
        l.record(passed: true); l.record(passed: true)
        XCTAssertEqual(l.record(passed: true), .up)       // 90 -> 100 (techo)
        XCTAssertTrue(l.isAtTop)
        // tres aprobados más: intenta subir una vez (y no puede), no en cada uno
        XCTAssertEqual(l.record(passed: true), .hold)
        XCTAssertEqual(l.record(passed: true), .hold)
        XCTAssertEqual(l.record(passed: true), .hold)
        XCTAssertEqual(l.currentBPM, 100)
    }

    // MARK: - subir y bajar en la misma sesión

    func testSecuenciaMixta() {
        var l = ladder(start: 80)
        // FF -> baja a 70
        l.record(passed: false); XCTAssertEqual(l.record(passed: false), .down)
        XCTAssertEqual(l.currentBPM, 70)
        // PPP -> sube a 80
        l.record(passed: true); l.record(passed: true)
        XCTAssertEqual(l.record(passed: true), .up)
        XCTAssertEqual(l.currentBPM, 80)
        // PP F F -> baja a 70 (la P no cuenta para la racha de fallos)
        l.record(passed: true); l.record(passed: true)
        l.record(passed: false); XCTAssertEqual(l.record(passed: false), .down)
        XCTAssertEqual(l.currentBPM, 70)
    }

    // MARK: - valor

    func testEsUnValor() {
        var a = ladder(start: 80)
        a.record(passed: true); a.record(passed: true)
        var b = a
        b.record(passed: true)                            // b sube, a no
        XCTAssertEqual(a.currentBPM, 80)
        XCTAssertEqual(b.currentBPM, 90)
    }
}
