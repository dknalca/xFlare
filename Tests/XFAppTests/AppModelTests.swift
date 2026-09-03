// SPDX-License-Identifier: GPL-3.0-only
import XCTest
import Combine
@testable import XFApp
import XFPersistence
import XFNotation
import XFCapture

/// El coordinador de la app: navegacion + datos montados con los assemblers.
final class AppModelTests: XCTestCase {

    private func model() throws -> AppModel {
        let catalog = try CatalogLoader.load(from: RepoContentLoader())
        return AppModel(catalog: catalog, db: try .inMemory())
    }

    func testArrancaEnHome() throws {
        let m = try model()
        m.refreshHome()
        XCTAssertEqual(m.screen, .home)
        XCTAssertEqual(m.home?.cells.count, 12)
    }

    func testNavegacion() throws {
        let m = try model()
        m.openLibrary()
        XCTAssertEqual(m.screen, .library)
        XCTAssertNotNil(m.library)

        m.openMediaLibrary(); XCTAssertEqual(m.screen, .mediaLibrary)   // "Librería" (medios)
        m.openMyTable();   XCTAssertEqual(m.screen, .myTable)
        m.openSettings();  XCTAssertEqual(m.screen, .settings)
        m.openCalibration(); XCTAssertEqual(m.screen, .calibration)
        m.goHome();        XCTAssertEqual(m.screen, .home)
    }

    func testSeleccionarUnScratchAbreLaFichaNoLaPractica() throws {
        let m = try model()
        m.selectScratch("baby")
        XCTAssertEqual(m.screen, .exerciseDetail(scratchId: "baby"))
        // la ficha trae dibujo + descripción
        let d = try XCTUnwrap(m.exerciseDetail(scratchId: "baby"))
        XCTAssertEqual(d.exerciseId, "ex-l1-baby")
        XCTAssertFalse(d.description.isEmpty)
        XCTAssertNotNil(d.thumbnail)
        // y desde ahí se lanza la práctica
        m.startPractice(exerciseId: "ex-l1-baby")
        XCTAssertEqual(m.screen, .practice(exerciseId: "ex-l1-baby", variantId: "base"))
        XCTAssertEqual(m.continueExerciseId, "ex-l1-baby")
    }

    func testSeleccionarUnaFamiliaAbreLaFichaConSusMiembros() throws {
        let m = try model()
        m.selectScratch("flare")
        XCTAssertEqual(m.screen, .exerciseDetail(scratchId: "flare"))
        let d = try XCTUnwrap(m.exerciseDetail(scratchId: "flare"))
        XCTAssertEqual(d.name, "Flare")
        XCTAssertFalse(d.members.isEmpty)
        XCTAssertTrue(d.members.contains { $0.scratchId == "orbit-2c" })
        // desde un miembro se lanza la practica con su ejercicio real
        let ex = try XCTUnwrap(d.members.first { $0.scratchId == "flare-2c" }?.exerciseId)
        m.startPractice(exerciseId: ex, variantId: "base")
        XCTAssertEqual(m.screen, .practice(exerciseId: "ex-l4-flare-2c", variantId: "base"))
    }

    func testSeleccionarUnScratchInexistenteNoHaceNada() throws {
        let m = try model()
        m.selectScratch("no-existe")
        XCTAssertEqual(m.screen, .home)
    }

    // MARK: - patron a practicar
    // (Variantes DESACTIVADAS de momento: solo `base`. La maquinaria de
    //  transformacion -subdivision, mirror, offset...- sigue en `AppModel.scratch`
    //  y volvera con datos en `variants.json` cuando se reactiven.)

    func testLaVarianteBaseDevuelveElPatronTalCual() throws {
        let m = try model()
        let base = try XCTUnwrap(m.scratch(exerciseId: "ex-l1-baby", variantId: "base"))
        XCTAssertEqual(base.div, "1/8")
        XCTAssertEqual(base.id, "baby")
    }

    func testUnaVarianteDesconocidaCaeALaBase() throws {
        let m = try model()
        let s = try XCTUnwrap(m.scratch(exerciseId: "ex-l1-baby", variantId: "no-existe"))
        XCTAssertEqual(s.div, "1/8")
    }

    func testFinishPracticeAsientaYVaAResultados() throws {
        let m = try model()
        let a = Attempt(id: "a1", exerciseId: "ex-l1-baby", variantId: "base",
                        mode: .ghost, bpm: 70, startedAt: Date(), durationMs: 12_000,
                        score: 3200, maxScore: 3600, accuracy: 0.89, stars: 2)
        m.finishPractice(attempt: a, events: [],
                         starReasons: ["★★★ Solido: necesitas 95% (tienes 89%)."],
                         diagnostics: ["Vas 12 ms tarde de media."])

        XCTAssertEqual(m.screen, .results)
        XCTAssertEqual(m.lastResults?.scoreText, "3.200 / 3.600")
        XCTAssertEqual(m.lastResults?.stars.map(\.filled), [true, true, false])
        XCTAssertEqual(try m.db.progress(exerciseId: "ex-l1-baby", variantId: "base")?.stars, 2)
        // aparece en el Home refrescado
        XCTAssertEqual(m.home?.cells.first { $0.scratchId == "baby" }?.state, .practiced(stars: 2))
    }

    func testMejorMarcaMarcaRecord() throws {
        let m = try model()
        func take(_ score: Int) -> Attempt {
            Attempt(id: UUID().uuidString, exerciseId: "ex-l1-baby", variantId: "base",
                    mode: .ghost, bpm: 70, startedAt: Date(), durationMs: 1000,
                    score: score, maxScore: 3600, accuracy: Double(score) / 3600, stars: 1)
        }
        m.finishPractice(attempt: take(3000), events: [], starReasons: [], diagnostics: [])
        XCTAssertTrue(m.lastResults?.isBestScore ?? false)
        m.finishPractice(attempt: take(2800), events: [], starReasons: [], diagnostics: [])
        XCTAssertFalse(m.lastResults?.isBestScore ?? true, "peor que la anterior, no es record")
        m.finishPractice(attempt: take(3400), events: [], starReasons: [], diagnostics: [])
        XCTAssertTrue(m.lastResults?.isBestScore ?? false)
    }

    func testRachaYMinutosDesdeLosIntentos() throws {
        let m = try model()
        let today = Date()
        try m.db.saveAttempt(Attempt(id: "x", exerciseId: "ex-l1-baby", variantId: "base",
                                     mode: .ghost, bpm: 70, startedAt: today, durationMs: 600_000,
                                     score: 1, maxScore: 2, accuracy: 0.5, stars: 0))
        XCTAssertEqual(m.currentStreakDays(), 1)
        XCTAssertEqual(m.minutesPracticedToday(), 10)
    }

    func testVariantOptions() throws {
        let m = try model()
        // variantes DESACTIVADAS de momento: solo `base`, desbloqueada
        let opts = m.variantOptions(exerciseId: "ex-l1-baby")
        XCTAssertEqual(opts.map(\.variantId), ["base"])
        XCTAssertTrue(opts.allSatisfy { $0.isUnlocked })
    }

    func testFailedDaUnModeloEnError() {
        let m = AppModel.failed("boom")
        XCTAssertEqual(m.screen, .error("boom"))
        XCTAssertEqual(m.catalog.exercises.count, 0)
    }

    // MARK: - comandos por MIDI

    func testUnOverrideDeUsuarioSeEnrutaAlSubjectDeComandos() throws {
        let m = try model()
        // el usuario asigna Note On 36 (canal 1) al comando "cue"
        m.settings.midiCommandOverrides = ["cue": "note:1:36"]

        var got: [PracticeCommandEvent] = []
        let c = m.practiceCommandEvents.sink { got.append($0) }
        defer { c.cancel() }

        m.midiCommands.ingest(bytes: [0x90, 36, 100])   // Note On 36
        m.midiCommands.ingest(bytes: [0x90, 40, 100])   // otra nota: nada

        XCTAssertEqual(got, [.trigger(.cue)])
    }

    func testCalentamientoEsUnaSolaSesionEncadenada() throws {
        let m = try model()
        m.openWarmup()
        XCTAssertEqual(m.screen, .warmup)
        XCTAssertFalse(m.warmup.isEmpty, "sin historial sale la rutina de arranque")

        m.startWarmupSession(rows: m.warmup)
        // abre la practica en el primer ejercicio, con la tanda entera cargada
        guard case .practice = m.screen else {
            return XCTFail("startWarmupSession debe abrir la practica")
        }
        XCTAssertGreaterThanOrEqual(m.warmupSteps.count, 4, "Forward/Reverse/Chirp/Transformer")
        XCTAssertEqual(m.warmupSteps.first?.phraseCount, 8)
        XCTAssertEqual(m.startCallResponseBars, 2, "arranca en 'repite conmigo' a 2 compases")

        // volver a casa limpia la tanda
        m.goHome()
        XCTAssertTrue(m.warmupSteps.isEmpty)
    }

    func testElUsuarioEditaElPlanDeCalentamientoAntesDeEmpezar() throws {
        let m = try model()
        m.openWarmup()
        var rows = m.warmup
        XCTAssertGreaterThanOrEqual(rows.count, 4)

        // borra el primero, dobla la duración del que queda primero
        rows.removeFirst()
        rows[0].phraseCount = 16
        let expectedCount = rows.count

        m.startWarmupSession(rows: rows)
        XCTAssertEqual(m.warmupSteps.count, expectedCount, "respeta las filas borradas")
        XCTAssertEqual(m.warmupSteps.first?.phraseCount, 16, "respeta la duración editada")

        // la librería para el botón "+" trae los ejercicios del catálogo
        XCTAssertFalse(m.warmupLibrary.isEmpty)
        XCTAssertLessThanOrEqual(m.warmupLibrary.count, m.catalog.exercises.count)
    }

    func testUnaTomaDeCalentamientoSeRegistraComoWarmupYDetectaOxidacion() throws {
        let m = try model()
        let ex = try XCTUnwrap(m.catalog.exercises.first)

        // toma floja (1★): debe volver como "oxidado" con un aviso concreto
        let msg = m.settleWarmupTake(exerciseId: ex.id, variantId: "base",
                                     score: 30, maxScore: 100, stars: 1)
        XCTAssertNotNil(msg, "1★ en calentamiento -> aviso de oxidación")
        XCTAssertNotNil(try m.db.mastery(exerciseId: ex.id)?.oxidizedAt,
                        "queda marcado oxidado (vuelve a la rotación)")

        let saved = try m.db.attempts(exerciseId: ex.id)
        XCTAssertEqual(saved.count, 1)
        XCTAssertEqual(saved[0].mode, .warmup)
        XCTAssertFalse(saved[0].countsForStars, "el calentamiento NO mueve estrellas")
        XCTAssertEqual(saved[0].accuracy, 0.3, accuracy: 1e-9)

        // una toma sólida (3★) no dispara ningún aviso
        let msg2 = m.settleWarmupTake(exerciseId: ex.id, variantId: "base",
                                      score: 96, maxScore: 100, stars: 3)
        XCTAssertNil(msg2)
    }

    func testBootMontaTodoDesdeElRepo() throws {
        let dbURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("xflare-boot-\(UUID().uuidString).sqlite")
        defer { try? FileManager.default.removeItem(at: dbURL) }

        let m = AppModel.boot(content: RepoContentLoader(), databaseURL: dbURL)
        XCTAssertEqual(m.screen, .home)
        XCTAssertEqual(m.catalog.exercises.count, 18)
        XCTAssertEqual(m.home?.cells.count, 12)
        XCTAssertFalse(m.myTable().rows.isEmpty, "carga los perfiles de profiles/")
        XCTAssertNotNil(m.engine, "crea el motor de audio")
    }
}
