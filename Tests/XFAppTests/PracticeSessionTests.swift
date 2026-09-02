// SPDX-License-Identifier: GPL-3.0-only
import XCTest
@testable import XFApp
import XFNotation

/// El motor de la practica rudimentaria: reloj musical propio + plato de juguete.
/// Aqui se prueba la fisica (que es pura); el pegamento con `NSView` no.
final class PracticeSessionTests: XCTestCase {

    private func scratch(_ id: String = "baby") throws -> Scratch {
        let catalog = try CatalogLoader.load(from: RepoContentLoader())
        return try XCTUnwrap(catalog.library.scratch(id: id))
    }

    func testArrancaEnCero() throws {
        let s = PracticeSession(scratch: try scratch(), bpm: 90)
        XCTAssertEqual(s.tick(), 0)
        XCTAssertTrue(s.trace().isEmpty)
        XCTAssertEqual(s.bpm, 90)
    }

    func testElRelojAvanzaSegunElBPM() throws {
        let s = PracticeSession(scratch: try scratch(), bpm: 120)   // ppq 480
        // 1 s de fotogramas de 1/60 (cada paso <= el tope de 0,05 s)
        for _ in 0..<60 { s.advance(by: 1.0 / 60.0) }
        // 120 bpm = 2 negras/s; 2 * 480 ppq = 960 ticks en 1 s
        XCTAssertEqual(s.tick(), 960, accuracy: 1.0)
    }

    func testUnPasoLargoSeAcotaParaNoPegarSaltos() throws {
        let s = PracticeSession(scratch: try scratch(), bpm: 120)
        s.advance(by: 5.0)                       // el hilo se atasco 5 s
        // se aplica como un solo fotograma de 0,05 s: 0,05 * 2 * 480 = 48
        XCTAssertEqual(s.tick(), 48, accuracy: 1.0)
    }

    func testElScrollMueveElPlatoYLuegoFrena() throws {
        let s = PracticeSession(scratch: try scratch(), bpm: 90)
        s.advance(by: 1.0 / 60.0)
        let p0 = s.platterPosition

        s.scrollBy(20)                     // empujon
        for _ in 0..<30 { s.advance(by: 1.0 / 60.0) }
        let pMoved = s.platterPosition
        XCTAssertGreaterThan(pMoved, p0, "el plato se ha movido hacia adelante")

        // sin mas entrada, la friccion lo para
        for _ in 0..<120 { s.advance(by: 1.0 / 60.0) }
        XCTAssertEqual(s.platterVelocity, 0, accuracy: 1e-3, "coast hasta parar")
    }

    func testAyDMuevenEnSentidosOpuestos() throws {
        let s = PracticeSession(scratch: try scratch(), bpm: 90)
        s.nudge(forward: true)
        XCTAssertGreaterThan(s.platterVelocity, 0)
        s.nudge(forward: false)
        s.nudge(forward: false)
        XCTAssertLessThan(s.platterVelocity, 0)
    }

    func testLaPosicionNoSeSaleDeLaAutopista() throws {
        let s = PracticeSession(scratch: try scratch(), bpm: 90)
        // martilleo hacia un lado
        for _ in 0..<200 {
            s.scrollBy(100)
            s.advance(by: 1.0 / 60.0)
        }
        let hi = s.platterPosition
        for _ in 0..<400 {
            s.scrollBy(-100)
            s.advance(by: 1.0 / 60.0)
        }
        let lo = s.platterPosition
        XCTAssertLessThan(lo, hi)
        XCTAssertGreaterThan(hi - lo, 0.1, "hay recorrido util")
        // no explota a infinito: se queda en un rango acotado y pequeno
        XCTAssertLessThan(abs(hi), 10)
        XCTAssertLessThan(abs(lo), 10)
    }

    func testPosicionNormalizadaVaDe0a1() throws {
        let s = PracticeSession(scratch: try scratch(), bpm: 90)
        XCTAssert((0.0...1.0).contains(s.normalizedPosition))

        // hasta el tope de arriba
        for _ in 0..<300 { s.scrollBy(100); s.advance(by: 1.0 / 60.0) }
        XCTAssertEqual(s.normalizedPosition, 1, accuracy: 1e-6)
        // hasta el tope de abajo
        for _ in 0..<600 { s.scrollBy(-100); s.advance(by: 1.0 / 60.0) }
        XCTAssertEqual(s.normalizedPosition, 0, accuracy: 1e-6)
    }

    func testOnAdvanceEntregaVelocidadYPosicion() throws {
        let s = PracticeSession(scratch: try scratch(), bpm: 90)
        var last: (v: Double, pos: Double, tick: Double)?
        s.onAdvance = { v, pos, tick in last = (v, pos, tick) }

        s.nudge(forward: true)
        s.advance(by: 1.0 / 60.0)

        let got = try XCTUnwrap(last)
        XCTAssertGreaterThan(got.v, 0)
        XCTAssert((0.0...1.0).contains(got.pos))
        XCTAssertGreaterThan(got.tick, 0)
    }

    func testLaTrazaAcumulaYRecortaLaHistoriaVieja() throws {
        let s = PracticeSession(scratch: try scratch(), bpm: 120)   // ppq 480
        for _ in 0..<600 { s.advance(by: 1.0 / 60.0) }              // 10 s -> 9600 ticks
        let trace = s.trace()
        XCTAssertFalse(trace.isEmpty)
        // historia = 8 negras = 3840 ticks; nada mas viejo que now - 3840
        let oldest = try XCTUnwrap(trace.map(\.tick).min())
        XCTAssertGreaterThanOrEqual(oldest, s.tick() - 3840 - 1)
        // y el ultimo punto es ~ahora
        XCTAssertEqual(try XCTUnwrap(trace.map(\.tick).max()), s.tick(), accuracy: 32)
    }

    func testElBPMSeAcota() throws {
        let s = PracticeSession(scratch: try scratch(), bpm: 90)
        s.setBPM(9_000)
        XCTAssertEqual(s.bpm, 220)
        s.setBPM(1)
        XCTAssertEqual(s.bpm, 40)
    }

    func testElFaderCerradoEsUnFlag() throws {
        let s = PracticeSession(scratch: try scratch(), bpm: 90)
        XCTAssertFalse(s.faderClosed)
        s.setFaderClosed(true)
        XCTAssertTrue(s.faderClosed)
        s.setFaderClosed(false)
        XCTAssertFalse(s.faderClosed)
    }

    func testConstruyeConCualquierScratchDeLaLibreria() throws {
        let catalog = try CatalogLoader.load(from: RepoContentLoader())
        for sc in catalog.library.scratches {
            let s = PracticeSession(scratch: sc, bpm: 100)
            s.advance(by: 0.1)
            XCTAssertGreaterThan(s.tick(), 0)
        }
    }

    // MARK: - llamada y respuesta

    func testEnEscuchaElFantasmaMueveElPlatoYSeIgnoraElInput() throws {
        let s = PracticeSession(scratch: try scratch("baby"), bpm: 90)
        s.setCallResponse(true)
        XCTAssertEqual(s.crPhase, .listen)

        var positions: [Double] = []
        for _ in 0..<40 {
            s.scrollBy(500)                     // input del usuario: debe ignorarse
            s.advance(by: 1.0 / 60.0)
            positions.append(s.platterPosition)
        }
        // el plato se mueve (lo mueve el fantasma, no el scroll)
        XCTAssertGreaterThan((positions.max() ?? 0) - (positions.min() ?? 0), 0.05,
                             "el fantasma mueve el plato en escucha")
        // y `onAdvance` (que empuja el audio) recibe posiciones que cambian
        var norms: [Double] = []
        s.onAdvance = { _, pos, _ in norms.append(pos) }
        for _ in 0..<40 { s.advance(by: 1.0 / 60.0) }
        XCTAssertGreaterThan((norms.max() ?? 0) - (norms.min() ?? 0), 0.02)
    }

    func testAlternaEscuchaYTuTurnoCadaCrBars() throws {
        let s = PracticeSession(scratch: try scratch("baby"), bpm: 120)
        s.setCallResponse(true)
        XCTAssertEqual(s.crPhase, .listen)

        var sawRespond = false
        var sawListenAgain = false
        // corre bastante: baby = 1 compas, crBars = 2 -> fase de 2 compases.
        // a 120 bpm, 2 compases = 4 s. Corremos 12 s.
        for _ in 0..<720 {
            s.advance(by: 1.0 / 60.0)
            if s.crPhase == .respond { sawRespond = true }
            if sawRespond && s.crPhase == .listen { sawListenAgain = true }
        }
        XCTAssertTrue(sawRespond, "pasa a tu turno")
        XCTAssertTrue(sawListenAgain, "y vuelve a escucha")
    }

    func testApagarCallResponseVuelveAControlManual() throws {
        let s = PracticeSession(scratch: try scratch("baby"), bpm: 90)
        s.setCallResponse(true)
        for _ in 0..<20 { s.advance(by: 1.0 / 60.0) }
        s.setCallResponse(false)
        XCTAssertEqual(s.crPhase, .off)

        let p0 = s.platterPosition
        s.scrollBy(40)
        for _ in 0..<20 { s.advance(by: 1.0 / 60.0) }
        XCTAssertGreaterThan(abs(s.platterPosition - p0), 1e-6, "el scroll vuelve a mover el plato")
    }
}
