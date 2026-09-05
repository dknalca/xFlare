// SPDX-License-Identifier: GPL-3.0-only
import XCTest
@testable import XFApp
import XFNotation
import XFCapture
import XFAnalysis

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

    func testElBPMConservaUnDecimal() throws {
        let s = PracticeSession(scratch: try scratch(), bpm: 90)
        s.setBPM(120.53)
        XCTAssertEqual(s.bpm, 120.5, accuracy: 1e-9, "un decimal, redondeado")
        s.setBPM(95.06)
        XCTAssertEqual(s.bpm, 95.1, accuracy: 1e-9)
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

    func testGrabarUnaLineaLaExportaYSePuedeReproducir() throws {
        let s = PracticeSession(scratch: try scratch(), bpm: 90)
        XCTAssertFalse(s.recording)

        s.startRecording()
        XCTAssertTrue(s.recording)
        // mueve el plato adelante y atras un rato
        for i in 0..<120 {
            s.scrollBy(i % 40 < 20 ? 30 : -30)
            s.advance(by: 1.0 / 60.0)
        }
        let take = try XCTUnwrap(s.stopRecording())
        XCTAssertFalse(s.recording)
        XCTAssertGreaterThan(take.motion.count, 100)
        XCTAssertEqual(take.header.tempoBPM, 90, accuracy: 1e-9)

        // ida y vuelta por el fichero .xfsession
        let text = take.encodedJSONLines()
        let reloaded = try XFSession(jsonLines: text)
        XCTAssertEqual(reloaded.motion.count, take.motion.count)

        // reproducirla: el plato lo mueve el fichero, no el input
        let p = PracticeSession(scratch: try scratch(), bpm: 90)
        p.loadPlayback(reloaded)
        XCTAssertTrue(p.playingBack)
        var moved = false
        let start = p.platterPosition
        for _ in 0..<200 {
            p.advance(by: 1.0 / 60.0)
            if abs(p.platterPosition - start) > 1e-6 { moved = true }
        }
        XCTAssertTrue(moved, "la linea grabada mueve el plato al reproducirse")

        p.stopPlayback()
        XCTAssertFalse(p.playingBack)
    }

    func testLaClaquetaRetrasaElInicioYLaTomaCuadraACompases() throws {
        // ppq 480, 4/4 -> 1 compas = 1920 ticks. A 120 bpm son 0,5 s (~30 fps).
        let s = PracticeSession(scratch: try scratch(), bpm: 120)
        s.setInstrumentalLoopTicks(1920 * 2)      // bucle de 2 compases
        s.setInstrumentalName("mi base 90bpm")
        s.advance(by: 1.0 / 60.0)

        s.armRecording()
        XCTAssertTrue(s.recArming)
        XCTAssertFalse(s.recording)
        XCTAssertGreaterThan(s.recCountBeats, 0, "hay cuenta de claqueta")

        var startedAt = -1
        for i in 0..<400 {
            s.scrollBy(i % 40 < 20 ? 25 : -25)
            s.advance(by: 1.0 / 60.0)
            if s.recording && startedAt < 0 { startedAt = i }
        }
        // la grabacion no arranca durante la claqueta (al menos ~medio compas)
        XCTAssertGreaterThan(startedAt, 15, "no graba durante la claqueta")
        XCTAssertFalse(s.recArming)
        XCTAssertEqual(s.recCountBeats, 0)

        let take = try XCTUnwrap(s.stopRecording())
        // la longitud del bucle viaja en la cabecera y es multiplo del bucle
        // de la instrumental (2 compases = 3840 ticks)
        let loop = try XCTUnwrap(PracticeSession.parseLoopTicks(take.header.notes))
        XCTAssertGreaterThanOrEqual(loop, 3840)
        XCTAssertEqual(loop.truncatingRemainder(dividingBy: 3840), 0, accuracy: 1e-3)
        // y el nombre de la base (sin espacios)
        XCTAssertEqual(PracticeSession.parseInstrName(take.header.notes), "mi_base_90bpm")

        // al reproducirla, la sesion expone sobre que base se grabo
        let p = PracticeSession(scratch: try scratch(), bpm: 120)
        p.loadPlayback(take)
        XCTAssertTrue(p.playingBack)
        XCTAssertEqual(p.playbackInstrName, "mi_base_90bpm")
        p.stopPlayback()
        XCTAssertEqual(p.playbackInstrName, "")
    }

    func testUnaTomaGrabadaSePuntuaConXFAnalysis() throws {
        // el wire práctica -> XFAnalysis: una toma grabada se convierte en `Take`
        // y `DefaultScorer` la puntúa sin reventar, con score en [0, maxScore].
        let sc = try scratch("baby")
        let s = PracticeSession(scratch: sc, bpm: 90)
        s.startRecording()
        for i in 0..<240 {
            s.scrollBy(sin(Double(i) * 0.13) * 40)
            s.advance(by: 1.0 / 60.0)
        }
        let take = try XCTUnwrap(s.stopRecording())

        let t = Take(motion: take.motion, fader: take.fader, clock: take.clockMap)
        let report = DefaultScorer().score(t, against: sc, atTargetBpm: true)

        XCTAssertEqual(report.maxScore, ScoreEvents(of: sc).maxScore)
        XCTAssertGreaterThanOrEqual(report.score, 0)
        XCTAssertLessThanOrEqual(report.score, report.maxScore)
        XCTAssert((0...3).contains(report.stars))

        // y se traduce a lo que pinta la pantalla de resultados
        let summary = ResultsSummary.build(report: report, isBestScore: false)
        XCTAssertEqual(summary.stars.count, 3)
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

    func testCuePointSaltaAUnaFraccionDelSample() throws {
        let s = PracticeSession(scratch: try scratch(), bpm: 90)
        var cued: (v: Double, pos: Double)?
        s.onAdvance = { v, pos, _ in cued = (v, pos) }

        s.jumpTo(sampleFraction: 0.5)
        XCTAssertEqual(s.normalizedPosition, 0.5, accuracy: 1e-6, "cue A/B a media longitud")
        XCTAssertEqual(s.platterVelocity, 0)
        XCTAssertEqual(cued?.pos ?? -1, 0.5, accuracy: 1e-6, "avisa al motor con la fracción")
        XCTAssertEqual(cued?.v, 0)

        // se acota a 0…1
        s.jumpTo(sampleFraction: 2.0)
        XCTAssertEqual(s.normalizedPosition, 1, accuracy: 1e-6)
        s.jumpTo(sampleFraction: -1)
        XCTAssertEqual(s.normalizedPosition, 0, accuracy: 1e-6)
    }

    func testReloadCambiaElPatronEnCalienteYLimpiaLaTraza() throws {
        let s = PracticeSession(scratch: try scratch("baby"), bpm: 120)
        // acumula algo de traza y hace correr el reloj
        s.scrollBy(20)
        for _ in 0..<30 { s.advance(by: 1.0 / 60.0) }
        XCTAssertFalse(s.trace().isEmpty)
        let tickBefore = s.tick()
        XCTAssertGreaterThan(tickBefore, 0)

        var advised: (v: Double, pos: Double)?
        s.onAdvance = { v, pos, _ in advised = (v, pos) }

        s.reload(scratch: try scratch("forward-cut"))

        XCTAssertTrue(s.trace().isEmpty, "la traza vieja se borra al cambiar de ejercicio")
        XCTAssertEqual(s.platterVelocity, 0, "el plato queda quieto al inicio")
        XCTAssertEqual(s.normalizedPosition, 0, accuracy: 1e-6, "vuelve al inicio del sample")
        XCTAssertGreaterThanOrEqual(s.tick(), tickBefore, "el reloj NO se reinicia: la rejilla sigue")
        XCTAssertEqual(advised?.v, 0, "avisa al motor del reinicio")
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

    func testGridPhaseTicksDesfasaElFantasmaQueSeOye() throws {
        // Mover la rejilla con ◀/▶ desplaza el fantasma que se DIBUJA; para que
        // el que se OYE lo siga, la sesión lo evalúa en `currentTick + gridPhaseTicks`.
        let a = PracticeSession(scratch: try scratch("baby"), bpm: 120)
        a.setCallResponse(true)
        let b = PracticeSession(scratch: try scratch("baby"), bpm: 120)
        b.setCallResponse(true)
        b.gridPhaseTicks = 120   // 1/4 de compás a ppq 480

        var pa: [Double] = [], pb: [Double] = []
        a.onAdvance = { _, pos, _ in pa.append(pos) }
        b.onAdvance = { _, pos, _ in pb.append(pos) }
        for _ in 0..<120 {
            a.advance(by: 1.0 / 60.0)
            b.advance(by: 1.0 / 60.0)
        }
        // ambas siguen al fantasma (rango parecido) pero desfasadas en el tiempo
        XCTAssertGreaterThan((pa.max() ?? 0) - (pa.min() ?? 0), 0.05)
        XCTAssertGreaterThan((pb.max() ?? 0) - (pb.min() ?? 0), 0.05)
        let maxDiff = zip(pa, pb).map { abs($0 - $1) }.max() ?? 0
        XCTAssertGreaterThan(maxDiff, 0.02, "el desfase cambia lo que hace el fantasma en cada instante")

        // con gridPhaseTicks = 0 (por defecto) son idénticas
        let c = PracticeSession(scratch: try scratch("baby"), bpm: 120)
        c.setCallResponse(true)
        var pc: [Double] = []
        c.onAdvance = { _, pos, _ in pc.append(pos) }
        for _ in 0..<120 { c.advance(by: 1.0 / 60.0) }
        XCTAssertEqual(zip(pa, pc).map { abs($0 - $1) }.max() ?? 1, 0, accuracy: 1e-9)
    }

    func testAlEmpezarTuTurnoElFaderQuedaAbierto() throws {
        // chirp: el patrón cierra el fader. Sin el arreglo, "tu turno" arrancaba
        // mudo porque el último tick de la escucha dejaba `faderClosed == true`.
        let s = PracticeSession(scratch: try scratch("chirp"), bpm: 120)
        s.setCallResponse(true)
        XCTAssertEqual(s.crPhase, .listen)

        var sawClosedInListen = false
        var faderWhenRespondStarted: Bool?
        var prev = s.crPhase
        for _ in 0..<900 {
            s.advance(by: 1.0 / 60.0)
            if s.crPhase == .listen, s.faderClosed { sawClosedInListen = true }
            if prev == .listen, s.crPhase == .respond, faderWhenRespondStarted == nil {
                faderWhenRespondStarted = s.faderClosed
            }
            prev = s.crPhase
        }
        XCTAssertTrue(sawClosedInListen, "el fantasma del chirp cierra el fader en la escucha")
        XCTAssertEqual(faderWhenRespondStarted, false, "tu turno arranca con el sonido abierto")
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

    // MARK: - F.44: scrub (control de posición del trackpad)

    func testElScrubImponeLaVelocidadYNoLaAcumula() throws {
        let s = PracticeSession(scratch: try scratch(), bpm: 90)
        s.scrub(pointsPerSecond: 120)
        let v1 = s.platterVelocity
        XCTAssertGreaterThan(v1, 0, "el scrub fija una velocidad hacia adelante")
        s.scrub(pointsPerSecond: 120)             // mismo gesto otra vez
        XCTAssertEqual(s.platterVelocity, v1, accuracy: 1e-9,
                       "impone, no acumula (a diferencia de scrollBy)")
        s.scrollBy(120)
        XCTAssertGreaterThan(s.platterVelocity, v1, "scrollBy (rueda) sí acumula")
    }

    func testMientrasScrubeasElPlatoNoFrena() throws {
        let s = PracticeSession(scratch: try scratch(), bpm: 90)
        s.scrub(pointsPerSecond: 60)
        let v = s.platterVelocity
        // varios fotogramas sin nuevo evento (el bucle de test corre en µs, muy
        // por debajo del auto-soltado de 80 ms): la velocidad se mantiene.
        for _ in 0..<5 { s.advance(by: 1.0 / 60.0) }
        XCTAssertEqual(s.platterVelocity, v, accuracy: 1e-9, "sujeta la velocidad de la mano")

        // parar la mano SIN levantarla -> el plato se para en seco
        s.scrub(pointsPerSecond: 0)
        s.advance(by: 1.0 / 60.0)
        XCTAssertEqual(s.platterVelocity, 0, "scrub(0) = sujetar el vinilo quieto")
    }

    func testAlSoltarElScrubVuelveLaFriccion() throws {
        let s = PracticeSession(scratch: try scratch(), bpm: 90)
        s.scrub(pointsPerSecond: 60)
        s.endScrub()
        let v0 = s.platterVelocity
        for _ in 0..<30 { s.advance(by: 1.0 / 60.0) }
        XCTAssertLessThan(s.platterVelocity, v0, "sin dedos, la fricción frena")
        for _ in 0..<120 { s.advance(by: 1.0 / 60.0) }
        XCTAssertEqual(s.platterVelocity, 0, "y acaba parando del todo")
    }

    // MARK: - F.65/F.74: vinilo de timecode real

    /// `LivePracticeView.onAdvance` hace `engine.setVelocity(normalizedVelocity
    /// * full/sr)`, y `sampleDurationSeconds` = `full/sr`. Si `pushRealMotion`
    /// deshace bien la conversión, `normalizedVelocity * sampleDurationSeconds`
    /// tiene que devolver EXACTAMENTE el ratio real (1.0 = 33⅓ rpm nominal,
    /// `MotionSample.velocity`) sin importar la duración del sample cargado.
    /// `position` no afecta a la velocidad -- 0 vale para estos tests.
    func testPushRealMotionLaVelocidadLlegaIntactaTrasNormalizedVelocity() throws {
        let s = PracticeSession(scratch: try scratch(), bpm: 90)
        s.pushRealMotion(position: 0, velocity: 1.0, sampleDurationSeconds: 2.3)
        XCTAssertEqual(s.normalizedVelocity * 2.3, 1.0, accuracy: 1e-9)
    }

    func testPushRealMotionLaVelocidadEscalaConElRatioYLaDuracionDelSample() throws {
        let s = PracticeSession(scratch: try scratch(), bpm: 90)
        s.pushRealMotion(position: 0, velocity: 2.0, sampleDurationSeconds: 1.5)
        XCTAssertEqual(s.normalizedVelocity * 1.5, 2.0, accuracy: 1e-9, "v=2 dobla el ritmo")
        s.pushRealMotion(position: 0, velocity: -0.5, sampleDurationSeconds: 1.5)
        XCTAssertEqual(s.normalizedVelocity * 1.5, -0.5, accuracy: 1e-9, "negativo = hacia atrás")
    }

    func testPushRealMotionNoFrenaEntreMuestrasComoElScrub() throws {
        let s = PracticeSession(scratch: try scratch(), bpm: 90)
        s.pushRealMotion(position: 0, velocity: 1.0, sampleDurationSeconds: 2.0)
        let v = s.platterVelocity
        for _ in 0..<5 { s.advance(by: 1.0 / 60.0) }
        XCTAssertEqual(s.platterVelocity, v, accuracy: 1e-9,
                       "como el scrub, sujeta la velocidad mientras llegan muestras (< 80 ms)")
    }

    func testPushRealMotionSeIgnoraSiLaMaquinaLlevaElDisco() throws {
        let s = PracticeSession(scratch: try scratch(), bpm: 90)
        s.setAssist(.fader)
        s.pushRealMotion(position: 0, velocity: 1.0, sampleDurationSeconds: 2.0)
        XCTAssertEqual(s.platterVelocity, 0,
                       "igual que scrub/nudge/scrollBy: se ignora si el disco no lo llevas tú")
    }

    func testPushRealMotionConDuracionCeroNoRevienta() throws {
        let s = PracticeSession(scratch: try scratch(), bpm: 90)
        s.pushRealMotion(position: 0, velocity: 1.0, sampleDurationSeconds: 0)
        XCTAssertEqual(s.platterVelocity, 0)
    }

    /// F.70 — a diferencia de soltar el trackpad (`testAlSoltarElScrubVuelveLaFriccion`,
    /// donde SÍ vuelve la física), si el vinilo real deja de mandar velocidad
    /// (aguja levantada, o lo paraste con la mano) el plato se para EN FIRME:
    /// "el teal" solo se mueve con la señal real, sin decaimiento sintético de
    /// por medio que lo deje deslizando un rato más.
    func testPushRealMotionSeParaEnFirmeSiDejaDeLlegarSenal() throws {
        let s = PracticeSession(scratch: try scratch(), bpm: 90)
        s.pushRealMotion(position: 0, velocity: 1.0, sampleDurationSeconds: 2.0)
        XCTAssertNotEqual(s.platterVelocity, 0)
        Thread.sleep(forTimeInterval: 0.12)   // > 80 ms sin nueva muestra real
        s.advance(by: 1.0 / 60.0)
        XCTAssertEqual(s.platterVelocity, 0,
                       "sin señal real, parada en firme -- nada de fricción sintética")
    }

    /// F.74 (ADR-078) — "sticker drift": antes `PracticeSession` solo recibía
    /// la velocidad y RE-INTEGRABA la posición ella misma a 60 Hz, sujetando
    /// la última velocidad conocida entre dos muestras reales (~33 ms al
    /// sondeo de 30 Hz) — una aproximación que se separaba poco a poco de
    /// dónde estaba el vinilo DE VERDAD. Ahora `pushRealMotion` recibe
    /// también `position` (segundos-nominales acumulados por el decoder
    /// xwax) y RE-ANCLA `platterPosition` a ese valor exacto en cada
    /// muestra. La PRIMERA muestra tras (re)empezar a recibir señal solo fija
    /// el ancla (no mueve el plato de golpe); a partir de ahí, la posición
    /// sigue EXACTAMENTE al decoder, sin importar cuánto haya interpolado
    /// `coastPlatter` de por medio.
    func testPushRealMotionSigueLaPosicionDelDecoderSinAcumularError() throws {
        let s = PracticeSession(scratch: try scratch(), bpm: 90)
        let start = s.platterPosition

        s.pushRealMotion(position: 100, velocity: -1.0, sampleDurationSeconds: 2.0)
        XCTAssertEqual(s.platterPosition, start, accuracy: 1e-9,
                       "la primera muestra tras empezar a recibir señal solo ancla")

        s.pushRealMotion(position: 100 - 0.3, velocity: -1.0, sampleDurationSeconds: 2.0)
        let backPos = s.platterPosition
        XCTAssertLessThan(backPos, start,
                          "se mueve según la posición real del decoder, no una velocidad reintegrada")

        // volver EXACTAMENTE a la posición de decoder del ancla -> vuelve
        // EXACTO al punto de partida, sin importar el camino intermedio
        // (ninguna cadena de sumas que pueda acumular error).
        s.pushRealMotion(position: 100, velocity: 1.0, sampleDurationSeconds: 2.0)
        XCTAssertEqual(s.platterPosition, start, accuracy: 1e-9,
                       "vuelve EXACTO al ancla: sin deriva por el camino")
    }

    /// F.70 (ADR-076) — si el vinilo real retrocede más allá del principio del
    /// sample, la posición YA NO se clava ahí. `normalizedPosition` sigue
    /// acotado a 0 aparte (silencio), pero `platterPosition` sigue integrando
    /// el giro real de más -- comprobado aquí vía la posición del decoder.
    func testPushRealMotionHaciaAtrasDelPrincipioNoClavaLaPosicion() throws {
        let s = PracticeSession(scratch: try scratch(), bpm: 90)
        let start = s.platterPosition
        s.pushRealMotion(position: 0, velocity: -1.0, sampleDurationSeconds: 2.0)   // ancla
        s.pushRealMotion(position: -5, velocity: -1.0, sampleDurationSeconds: 2.0)  // 5 s-nominales hacia atrás
        XCTAssertLessThan(s.platterPosition, start,
                          "sigue el giro real hacia atrás del principio, no se clava en 0")
        XCTAssertEqual(s.normalizedPosition, 0, "no hay sample que sonar antes del principio: silencio")
    }

    /// Tras un corte de señal (watchdog de 80 ms, F.70) el ancla se suelta; la
    /// siguiente muestra real, aunque traiga una posición de decoder muy
    /// distinta (el vinilo pudo seguir girando durante el corte, o el
    /// decoder se reinició), tiene que RE-ANCLAR sin saltar el plato --
    /// exactamente igual que la primera muestra de una sesión.
    func testTrasUnCorteDeSenalLaSiguienteMuestraReanclaSinSaltar() throws {
        let s = PracticeSession(scratch: try scratch(), bpm: 90)
        s.pushRealMotion(position: 0, velocity: -1.0, sampleDurationSeconds: 2.0)
        s.pushRealMotion(position: -0.5, velocity: -1.0, sampleDurationSeconds: 2.0)
        let posBeforeCut = s.platterPosition

        Thread.sleep(forTimeInterval: 0.12)
        s.advance(by: 1.0 / 60.0)   // dispara el watchdog: suelta el ancla

        s.pushRealMotion(position: 9_999, velocity: 0, sampleDurationSeconds: 2.0)
        XCTAssertEqual(s.platterPosition, posBeforeCut, accuracy: 1e-9,
                       "re-ancla fresco tras el corte, no salta usando una posición de decoder vieja")
    }

    // MARK: - F.81 (ADR-085): desplazamiento fijo con la posición absoluta

    /// El caso que motivó F.81: F.78 reanclaba en cada transición
    /// enganche<->sin enganche, así que cualquier sesgo acumulado por la
    /// integral durante un tramo SIN enganche quedaba congelado para
    /// siempre en el nuevo ancla. Aquí `position` (la integral) se separa
    /// de la posición absoluta real DURANTE un tramo sin enganche (simula
    /// el sesgo del filtro de pitch de xwax); al recuperar el enganche con
    /// la MISMA posición absoluta de antes, `platterPosition` tiene que
    /// volver EXACTO a donde estaba -- no quedarse desplazado por el sesgo
    /// que se coló mientras tanto.
    func testAlRecuperarElEngancheCorrigeElSesgoAcumuladoSinEl() throws {
        let s = PracticeSession(scratch: try scratch(), bpm: 90)
        let start = s.platterPosition

        // enganchado: ancla el desplazamiento fijo.
        s.pushRealMotion(position: 100, absolutePosition: 50, velocity: -1.0, sampleDurationSeconds: 2.0)
        XCTAssertEqual(s.platterPosition, start, accuracy: 1e-9)

        // se pierde el enganche: la primera muestra sin enganche solo ancla
        // el respaldo (integral), como la primera muestra de una sesión.
        s.pushRealMotion(position: 105, absolutePosition: nil, velocity: -1.0, sampleDurationSeconds: 2.0)
        // la SIGUIENTE ya se mueve según la integral -- y esa es la que se
        // desvía sola, simulando el sesgo del filtro de pitch de xwax.
        s.pushRealMotion(position: 106, absolutePosition: nil, velocity: -1.0, sampleDurationSeconds: 2.0)
        XCTAssertNotEqual(s.platterPosition, start, accuracy: 1e-9,
                          "sin enganche, la integral SÍ puede desviar el plato")

        // se recupera el enganche con la MISMA posición absoluta de antes:
        // tiene que volver EXACTO al punto de partida, sin importar cuánto
        // se desvió la integral mientras no había enganche.
        s.pushRealMotion(position: 999, absolutePosition: 50, velocity: 1.0, sampleDurationSeconds: 2.0)
        XCTAssertEqual(s.platterPosition, start, accuracy: 1e-9,
                       "recuperar el enganche corrige de vuelta a la verdad del vinilo")
    }

    /// Con la posición absoluta SIEMPRE enganchada, `platterPosition` la
    /// sigue 1:1 -- ninguna cadena de sumas que pueda acumular error, igual
    /// que la integral (F.74) pero con una fuente que no tiene sesgo nunca.
    func testConEngancheContinuoSigueLaPosicionAbsoluta1a1() throws {
        let s = PracticeSession(scratch: try scratch(), bpm: 90)
        let start = s.platterPosition
        s.pushRealMotion(position: 0, absolutePosition: 50, velocity: -1.0, sampleDurationSeconds: 2.0)
        s.pushRealMotion(position: 0, absolutePosition: 49.7, velocity: -1.0, sampleDurationSeconds: 2.0)
        XCTAssertLessThan(s.platterPosition, start)
        s.pushRealMotion(position: 0, absolutePosition: 50, velocity: 1.0, sampleDurationSeconds: 2.0)
        XCTAssertEqual(s.platterPosition, start, accuracy: 1e-9, "vuelve EXACTO, sin deriva por el camino")
    }

    func testElScrubSeIgnoraSiLaMaquinaLlevaElDisco() throws {
        let s = PracticeSession(scratch: try scratch("baby"), bpm: 120)
        s.setAssist(.fader)                       // la máquina mueve el disco
        s.scrub(pointsPerSecond: 200)
        XCTAssertEqual(s.platterVelocity, 0, "en 'solo fader' el scrub no entra")
    }

    // MARK: - F.08: rozamiento seco (Coulomb)

    func testElRozamientoSecoParaElPlatoEnFirme() throws {
        // con Coulomb, el plato llega a velocidad EXACTAMENTE 0 (no se arrastra
        // asintoticamente). Empuje pequeno para no chocar con el tope del recorrido.
        let s = PracticeSession(scratch: try scratch(), bpm: 90)
        s.nudge(forward: true)                        // impulso ~2.2 unidades/s
        var framesToStop = 0
        for i in 1...120 {
            s.advance(by: 1.0 / 60.0)
            if s.platterVelocity == 0 { framesToStop = i; break }
        }
        XCTAssertGreaterThan(framesToStop, 0, "el plato se para del todo (v == 0 exacto)")
        XCTAssertLessThan(framesToStop, 90, "y rapido (< 1,5 s)")

        // sin Coulomb (0) el exponencial se arrastra: sigue moviendose al mismo tiempo
        let s2 = PracticeSession(scratch: try scratch(), bpm: 90)
        s2.coulombFriction = 0
        s2.nudge(forward: true)
        for _ in 0..<framesToStop { s2.advance(by: 1.0 / 60.0) }
        XCTAssertGreaterThan(abs(s2.platterVelocity), 1e-6,
                             "solo exponencial: todavia rueda cuando el Coulomb ya lo habia parado")
    }

    // MARK: - F.23: descomposición mano / fader

    func testSoloMano_tuMuevesElDiscoYLaMaquinaCortaElFader() throws {
        // forward-cut: el patrón abre y cierra el fader a lo largo del compás.
        let s = PracticeSession(scratch: try scratch("forward-cut"), bpm: 120)
        s.setAssist(.hand)

        // tu input de fader (Espacio / MIDI) se ignora: lo lleva la máquina
        s.setFaderClosed(true)
        XCTAssertFalse(s.faderClosed, "en 'solo mano' el fader no lo cierras tú")

        // pero tu scroll SÍ mueve el disco
        let p0 = s.platterPosition
        s.scrollBy(35)
        for _ in 0..<20 { s.advance(by: 1.0 / 60.0) }
        XCTAssertGreaterThan(s.platterPosition, p0, "el disco lo mueves tú")

        // y a lo largo de dos compases el fader lo abre y lo cierra el patrón
        var sawOpen = false, sawClosed = false
        for _ in 0..<Int(60 * 2) {
            s.advance(by: 1.0 / 60.0)
            s.faderClosed ? (sawClosed = true) : (sawOpen = true)
        }
        XCTAssertTrue(sawOpen && sawClosed, "el corte lo lleva la máquina, siguiendo el patrón")
    }

    func testSoloFader_laMaquinaMueveElDiscoYTuCortas() throws {
        let s = PracticeSession(scratch: try scratch("baby"), bpm: 120)
        s.setAssist(.fader)

        // tu scroll se ignora: el disco lo lleva la máquina
        s.scrollBy(80)
        var positions: [Double] = []
        for _ in 0..<48 { s.advance(by: 1.0 / 60.0); positions.append(s.platterPosition) }
        let travel = (positions.max() ?? 0) - (positions.min() ?? 0)
        XCTAssertGreaterThan(travel, 1e-3, "el disco se mueve solo (lo lleva la máquina)")

        // tu fader SÍ funciona
        s.setFaderClosed(true)
        XCTAssertTrue(s.faderClosed, "en 'solo fader' el corte lo llevas tú")
    }

    func testLasDos_esLaPracticaNormal() throws {
        let s = PracticeSession(scratch: try scratch("baby"), bpm: 120)
        XCTAssertEqual(s.assist, .both)
        // sin scroll, el disco no se mueve (la máquina no interviene)
        let p0 = s.platterPosition
        for _ in 0..<30 { s.advance(by: 1.0 / 60.0) }
        XCTAssertEqual(s.platterPosition, p0, accuracy: 1e-6)
        // y tu fader funciona
        s.setFaderClosed(true)
        XCTAssertTrue(s.faderClosed)
    }

    func testCicloDeManos() throws {
        let s = PracticeSession(scratch: try scratch(), bpm: 90)
        XCTAssertEqual(s.assist, .both)
        s.cycleAssist(); XCTAssertEqual(s.assist, .hand)
        s.cycleAssist(); XCTAssertEqual(s.assist, .fader)
        s.cycleAssist(); XCTAssertEqual(s.assist, .both)
    }

    func testLaEscuchaMandaSobreElModoDeManos() throws {
        // en 'solo mano' dices que el disco es tuyo; pero en la ESCUCHA del
        // "repite conmigo" la máquina toca las dos capas igual.
        let s = PracticeSession(scratch: try scratch("forward-cut"), bpm: 120)
        s.setAssist(.hand)
        s.setCallResponse(true)
        XCTAssertEqual(s.crPhase, .listen)
        s.setFaderClosed(true)
        XCTAssertFalse(s.faderClosed, "en escucha el input de fader se ignora igualmente")
        // y tu scroll tampoco entra en escucha
        s.scrollBy(80)
        XCTAssertEqual(s.platterVelocity, 0, accuracy: 1e-9)
    }

    func testAlRecuperarElFaderQuedaAbierto() throws {
        // chirp: el patrón cierra el fader. Al pasar de 'solo mano' a 'las dos'
        // se te devuelve abierto para no arrancar mudo.
        let s = PracticeSession(scratch: try scratch("chirp"), bpm: 120)
        s.setAssist(.hand)
        var closed = false
        for _ in 0..<600 {
            s.advance(by: 1.0 / 60.0)
            if s.faderClosed { closed = true; break }
        }
        XCTAssertTrue(closed, "el patrón del chirp cierra el fader")
        s.setAssist(.both)
        XCTAssertFalse(s.faderClosed, "al recuperar el fader, abierto")
    }
}
