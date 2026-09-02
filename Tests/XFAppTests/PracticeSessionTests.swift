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

    func testCongelarParaElRelojYLaTrazaPeroNoElPlato() throws {
        let s = PracticeSession(scratch: try scratch(), bpm: 120)
        for _ in 0..<30 { s.advance(by: 1.0 / 60.0) }
        let tickAntes = s.currentTick
        let trazaAntes = s.trace().count
        XCTAssertGreaterThan(tickAntes, 0)

        s.toggleFreeze()
        XCTAssertTrue(s.frozen)

        // empuja el plato y deja correr "congelado"
        s.scrollBy(60)
        var vistoMovimiento = false
        s.onAdvance = { vel, _, _ in if abs(vel) > 1e-6 { vistoMovimiento = true } }
        for _ in 0..<30 { s.advance(by: 1.0 / 60.0) }

        XCTAssertEqual(s.currentTick, tickAntes, "el reloj no avanza congelado")
        XCTAssertEqual(s.trace().count, trazaAntes, "la traza no crece congelada")
        XCTAssertTrue(vistoMovimiento, "el plato sigue vivo: se puede scratchear")

        s.toggleFreeze()
        XCTAssertFalse(s.frozen)
        for _ in 0..<10 { s.advance(by: 1.0 / 60.0) }
        XCTAssertGreaterThan(s.currentTick, tickAntes, "al descongelar el reloj vuelve a correr")
    }

    func testElPlatoRecorreTodoElRangoIndependienteDeLaAmplitud() throws {
        // la amplitud es cosa de la vista (escala la onda fantasma dibujada). El
        // PLATO llega SIEMPRE al final del sample al empujarlo a tope.
        let s = PracticeSession(scratch: try scratch(), bpm: 90)
        for _ in 0..<500 { s.scrollBy(80); s.advance(by: 1.0 / 60.0) }
        XCTAssertEqual(s.normalizedPosition, 1, accuracy: 1e-6)
        for _ in 0..<800 { s.scrollBy(-80); s.advance(by: 1.0 / 60.0) }
        XCTAssertEqual(s.normalizedPosition, 0, accuracy: 1e-6)
    }

    func testNudgeGridDesplazaElRelojYSePuedeResetear() throws {
        let s = PracticeSession(scratch: try scratch(), bpm: 120)
        for _ in 0..<30 { s.advance(by: 1.0 / 60.0) }
        let t0 = s.tick()

        s.nudgeGrid(40)
        s.nudgeGrid(40)
        XCTAssertEqual(s.tick() - t0, 80, accuracy: 1e-6, "el reloj (y con el la rejilla) se ha movido")
        XCTAssertEqual(s.gridPhaseOffset, 80, accuracy: 1e-6)

        s.nudgeGrid(-30)
        XCTAssertEqual(s.gridPhaseOffset, 50, accuracy: 1e-6)

        s.resetGridPhase()
        XCTAssertEqual(s.gridPhaseOffset, 0)
        XCTAssertEqual(s.tick() - t0, 0, accuracy: 1e-6, "vuelve donde estaba")
    }

    func testCue1VuelveAlInicioDelSample() throws {
        let s = PracticeSession(scratch: try scratch(), bpm: 90)
        // aleja el plato del inicio
        for _ in 0..<120 { s.scrollBy(60); s.advance(by: 1.0 / 60.0) }
        XCTAssertGreaterThan(s.normalizedPosition, 0.2)

        var cued: (v: Double, pos: Double)?
        s.onAdvance = { v, pos, _ in cued = (v, pos) }
        s.jumpToCue()

        XCTAssertEqual(s.normalizedPosition, 0, accuracy: 1e-9, "cue 1 = inicio del sample")
        XCTAssertEqual(s.platterVelocity, 0)
        XCTAssertEqual(cued?.pos, 0, "avisa al motor de que el sample vuelve a 0")
        XCTAssertEqual(cued?.v, 0)
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

    func testCrBarsEsParYAcotado() throws {
        let s = PracticeSession(scratch: try scratch("baby"), bpm: 90)
        XCTAssertEqual(s.crBars, 2)
        s.setCallResponseBars(4);  XCTAssertEqual(s.crBars, 4)
        s.setCallResponseBars(8);  XCTAssertEqual(s.crBars, 8)
        s.setCallResponseBars(3);  XCTAssertEqual(s.crBars, 2, "impar -> par por debajo")
        s.setCallResponseBars(99); XCTAssertEqual(s.crBars, 16, "tope 16")
        s.setCallResponseBars(0);  XCTAssertEqual(s.crBars, 2, "minimo 2")
    }

    func testMasCompasesAlargaLaFase() throws {
        let s = PracticeSession(scratch: try scratch("baby"), bpm: 120)
        s.setCallResponseBars(2)
        s.setCallResponse(true)
        // a 120 bpm, 2 compases = 4 s -> a los ~2 s sigue en listen
        for _ in 0..<120 { s.advance(by: 1.0 / 60.0) }
        XCTAssertEqual(s.crPhase, .listen, "con 2 compases ya habria cambiado si fuese 1")
        // con 8 compases, tras 4 s sigue en la primera fase
        let s2 = PracticeSession(scratch: try scratch("baby"), bpm: 120)
        s2.setCallResponseBars(8)
        s2.setCallResponse(true)
        for _ in 0..<300 { s2.advance(by: 1.0 / 60.0) }   // 5 s
        XCTAssertEqual(s2.crPhase, .listen, "8 compases = 16 s: sigue escuchando")
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
