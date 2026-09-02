// SPDX-License-Identifier: GPL-3.0-only
import XCTest
@testable import XFApp
import XFPersistence

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
        XCTAssertEqual(m.home?.cells.count, 25)
    }

    func testNavegacion() throws {
        let m = try model()
        m.openLibrary()
        XCTAssertEqual(m.screen, .library)
        XCTAssertNotNil(m.library)

        m.openMyTable();   XCTAssertEqual(m.screen, .myTable)
        m.openSettings();  XCTAssertEqual(m.screen, .settings)
        m.openCalibration(); XCTAssertEqual(m.screen, .calibration)
        m.goHome();        XCTAssertEqual(m.screen, .home)
    }

    func testSeleccionarUnScratchAbreLaFichaNoLaPractica() throws {
        let m = try model()
        m.selectScratch("baby")
        XCTAssertEqual(m.screen, .exerciseDetail(scratchId: "baby"))
        // la ficha trae dibujo + descripción + variantes
        let d = try XCTUnwrap(m.exerciseDetail(scratchId: "baby"))
        XCTAssertEqual(d.exerciseId, "ex-l1-baby")
        XCTAssertFalse(d.variants.isEmpty)
        // y desde ahí se lanza la práctica
        m.startPractice(exerciseId: "ex-l1-baby")
        XCTAssertEqual(m.screen, .practice(exerciseId: "ex-l1-baby", variantId: "base"))
        XCTAssertEqual(m.continueExerciseId, "ex-l1-baby")
    }

    func testSeleccionarUnScratchInexistenteNoHaceNada() throws {
        let m = try model()
        m.selectScratch("no-existe")
        XCTAssertEqual(m.screen, .home)
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
        let opts = m.variantOptions(exerciseId: "ex-l1-baby")
        XCTAssertEqual(opts.count, 10)
        XCTAssertTrue(opts.first { $0.variantId == "base" }?.isUnlocked ?? false)
        XCTAssertFalse(opts.first { $0.variantId == "off50" }?.isUnlocked ?? true)
    }

    func testFailedDaUnModeloEnError() {
        let m = AppModel.failed("boom")
        XCTAssertEqual(m.screen, .error("boom"))
        XCTAssertEqual(m.catalog.exercises.count, 0)
    }

    func testBootMontaTodoDesdeElRepo() throws {
        let dbURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("xflare-boot-\(UUID().uuidString).sqlite")
        defer { try? FileManager.default.removeItem(at: dbURL) }

        let m = AppModel.boot(content: RepoContentLoader(), databaseURL: dbURL)
        XCTAssertEqual(m.screen, .home)
        XCTAssertEqual(m.catalog.exercises.count, 25)
        XCTAssertEqual(m.home?.cells.count, 25)
        XCTAssertFalse(m.myTable().rows.isEmpty, "carga los perfiles de profiles/")
        XCTAssertNotNil(m.engine, "crea el motor de audio")
    }
}
