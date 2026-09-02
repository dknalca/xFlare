// SPDX-License-Identifier: GPL-3.0-only
import XCTest
@testable import XFApp
import XFPersistence
import XFProfiles

/// Ensamblaje: `Catalog` + `XFDatabase` -> entradas de los view-models.
final class AssemblerTests: XCTestCase {

    private func catalog() throws -> Catalog {
        try CatalogLoader.load(from: RepoContentLoader())
    }

    private func setStars(_ db: XFDatabase, exercise: String, variant: String, stars: Int) throws {
        try db.saveAttempt(Attempt(
            id: "\(exercise)-\(variant)-\(stars)-\(UUID().uuidString)",
            exerciseId: exercise, variantId: variant, mode: .ghost, bpm: 80,
            startedAt: Date(), durationMs: 1000, score: 3000, maxScore: 3600,
            accuracy: 0.83, stars: stars))
        try db.recomputeProgress(exerciseId: exercise, variantId: variant)
    }

    // MARK: - LevelGate

    func testL1SiempreAbiertoYLosDemasTrasCompletarElAnterior() throws {
        let c = try catalog()
        var stars: [String: Int] = [:]

        var open = LevelGate.unlockedLevels(catalog: c) { stars[$0] ?? 0 }
        XCTAssertEqual(open, ["L1"])

        // 1 estrella en TODOS los ejercicios de L1 -> se abre L2
        for ex in c.exercises where ex.level == "L1" { stars[ex.id] = 1 }
        open = LevelGate.unlockedLevels(catalog: c) { stars[$0] ?? 0 }
        XCTAssertTrue(open.contains("L1") && open.contains("L2"))
        XCTAssertFalse(open.contains("L3"))
    }

    // MARK: - Home

    func testHomeMarcaBloqueadoDisponiblePracticadoYDominado() throws {
        let c = try catalog()
        let db = try XFDatabase.inMemory()

        // baby (L1): 2 estrellas -> practicado
        try setStars(db, exercise: "ex-l1-baby", variant: "base", stars: 2)

        let s = try HomeAssembler.summary(catalog: c, db: db)
        let byScratch = Dictionary(uniqueKeysWithValues: s.cells.map { ($0.scratchId, $0) })

        XCTAssertEqual(byScratch["baby"]?.state, .practiced(stars: 2))
        // los flares colapsan a UNA celda de familia (Flare, Transformer)
        XCTAssertEqual(byScratch["flare"]?.isFamily, true)
        XCTAssertNil(byScratch["flare-2c"], "el 2-click no sale suelto: esta dentro de Flare")
        // la familia Flare (L3) sin L1..L2 completo -> bloqueada
        XCTAssertEqual(byScratch["flare"]?.state, .locked)
        // 21 ejercicios, 8 de ellos miembros de familia -> 21 - 8 + 2 = 15 celdas
        XCTAssertEqual(s.cells.count, 15)
    }

    func testHomeContinueTarget() throws {
        let c = try catalog()
        let db = try XFDatabase.inMemory()
        let s = try HomeAssembler.summary(catalog: c, db: db, continueExerciseId: "ex-l1-baby")
        XCTAssertEqual(s.continueTarget?.scratchId, "baby")
        XCTAssertEqual(s.continueTarget?.bpm, 50, "sin 3 estrellas, el BPM de arranque del ejercicio")
    }

    // MARK: - Libreria

    func testLibreriaMarcaLosDisponibles() throws {
        let c = try catalog()
        let db = try XFDatabase.inMemory()
        let b = try LibraryAssembler.browser(catalog: c, db: db)
        // 25 - 4 ocultas - 8 miembros de familia + 2 entradas de familia = 15
        XCTAssertEqual(b.entries.count, 15)
        for hidden in LibraryAssembler.hiddenInLibrary {
            XCTAssertNil(b.entries.first { $0.scratchId == hidden }, "\(hidden) no se lista")
        }
        // los flares no salen sueltos: en su lugar, la familia
        XCTAssertNil(b.entries.first { $0.scratchId == "flare-1c" })
        XCTAssertNotNil(b.entries.first { $0.scratchId == "flare" })
        XCTAssertNotNil(b.entries.first { $0.scratchId == "transformer" })
        // L1 disponible desde el principio
        XCTAssertEqual(b.entries.first { $0.scratchId == "baby" }?.isUnlocked, true)
        // algo de un nivel alto, bloqueado
        XCTAssertEqual(b.entries.first { $0.scratchId == "crab" }?.isUnlocked, false)
    }

    // MARK: - Variantes

    func testVariantesConSuCondicion() throws {
        let c = try catalog()
        let db = try XFDatabase.inMemory()

        var opts = try VariantAssembler.options(catalog: c, exerciseId: "ex-l1-baby", db: db)
        let off50 = try XCTUnwrap(opts.first { $0.variantId == "off50" })
        XCTAssertEqual(off50.lock, .locked(condition: "★★ en Base"))

        // 2 estrellas en la base -> off50 se desbloquea
        try setStars(db, exercise: "ex-l1-baby", variant: "base", stars: 2)
        opts = try VariantAssembler.options(catalog: c, exerciseId: "ex-l1-baby", db: db)
        XCTAssertTrue(try XCTUnwrap(opts.first { $0.variantId == "off50" }).isUnlocked)
        XCTAssertTrue(try XCTUnwrap(opts.first { $0.variantId == "base" }).isUnlocked)
    }

    // MARK: - Mi mesa

    func testMiMesaJuntaPerfilesYCalibraciones() throws {
        let ini = try INIDocument(text: """
        [profile]
        id = rane-seventy-two
        name = Rane Seventy-Two
        vendor = Rane
        schema = 1
        revision = 1
        verified = false
        [crossfader]
        method = audio_return
        pilot.frequency = 19500
        pilot.level_db = -40
        cut_in.left = 0.05
        cut_in.right = 0.95
        """)
        let profile = try DeviceProfile.parse(resolved: ini)
        let cal = DeviceCalibration(deviceKey: "dev", profileId: "rane-seventy-two",
                                    faderCutIn: 0.4, faderHysteresis: 0.05,
                                    latencyMs: 9.1, updatedAt: Date())
        let t = MyTableAssembler.table(
            profiles: [(profile, false)], calibrations: [cal],
            activeProfileId: "rane-seventy-two")

        XCTAssertEqual(t.rows.count, 1)
        XCTAssertEqual(t.active?.name, "Rane Seventy-Two")
        XCTAssertFalse(t.rows[0].verified)
        XCTAssertTrue(t.rows[0].hasCalibration)
        XCTAssertEqual(t.rows[0].latencyMs, 9.1)
    }

    // MARK: - AttemptRecorder

    func testGrabarUnaTomaAsientaProgresoDominadoYDesbloqueos() throws {
        let c = try catalog()
        let db = try XFDatabase.inMemory()

        func take(_ variant: String, stars: Int, bpm: Double = 80) -> Attempt {
            Attempt(id: UUID().uuidString, exerciseId: "ex-l4-flare-2c", variantId: variant,
                    mode: .ghost, bpm: bpm, startedAt: Date(), durationMs: 12_000,
                    score: 3400, maxScore: 3600, accuracy: 0.94, stars: stars)
        }

        // 3★ en base -> se desbloquean mirror y div16 (3★ en base)
        let unlocked = try AttemptRecorder.record(take("base", stars: 3), db: db, catalog: c)
        XCTAssertTrue(Set(unlocked).isSuperset(of: ["off25", "off50", "amp50", "amp150", "mirror", "div16"]))
        XCTAssertEqual(try db.progress(exerciseId: "ex-l4-flare-2c", variantId: "base")?.stars, 3)

        // 2★ en tres variantes -> dominado -> entra en repaso
        for v in ["off25", "off50", "amp50"] {
            _ = try AttemptRecorder.record(take(v, stars: 2), db: db, catalog: c)
        }
        XCTAssertTrue(try db.isMastered(exerciseId: "ex-l4-flare-2c"))
        XCTAssertNotNil(try db.reviewItem(exerciseId: "ex-l4-flare-2c", variantId: "base"))
    }

    // MARK: - Ventana de detalle del truco

    func testDetalleDeUnTrucoTraeDibujoDescripcionVariantesYMarca() throws {
        let c = try catalog()
        let db = try XFDatabase.inMemory()
        // una marca en la base del flare 2C
        try setStars(db, exercise: "ex-l4-flare-2c", variant: "base", stars: 2)

        let d = try XCTUnwrap(try ExerciseDetailAssembler.display(
            catalog: c, db: db, scratchId: "flare-2c"))

        XCTAssertEqual(d.name, "2-Click Flare")
        XCTAssertEqual(d.exerciseId, "ex-l4-flare-2c")
        XCTAssertEqual(d.level, 4, "nivel del curriculo, no el del scratch")
        XCTAssertNotNil(d.thumbnail)
        XCTAssertFalse(d.description.isEmpty)
        XCTAssertNotNil(d.history, "el flare tiene nota de historia")

        // la base va primero, desbloqueada, con 2 estrellas y su mejor marca
        let base = try XCTUnwrap(d.variants.first { $0.option.variantId == "base" })
        XCTAssertTrue(base.option.isUnlocked)
        XCTAssertEqual(base.stars, 2)
        XCTAssertNotEqual(base.bestScore, "—")

        // una variante que pide estrellas sigue bloqueada
        XCTAssertTrue(d.variants.contains { if case .locked = $0.option.lock { return true }; return false })
    }

    func testLaFichaDeUnaFamiliaTraeLosMiembrosConSusVariantes() throws {
        let c = try catalog()
        let db = try XFDatabase.inMemory()
        try setStars(db, exercise: "ex-l4-flare-2c", variant: "base", stars: 2)

        let d = try XCTUnwrap(try ExerciseDetailAssembler.display(
            catalog: c, db: db, scratchId: "flare"))

        XCTAssertEqual(d.name, "Flare")
        XCTAssertNil(d.exerciseId, "en una familia se practica por miembro")
        XCTAssertTrue(d.variants.isEmpty)
        XCTAssertEqual(d.members.map(\.scratchId),
                       ["flare-1c", "flare-2c", "flare-3c", "orbit-1c", "orbit-2c"])

        let m2c = try XCTUnwrap(d.members.first { $0.scratchId == "flare-2c" })
        XCTAssertEqual(m2c.exerciseId, "ex-l4-flare-2c")
        XCTAssertNotNil(m2c.thumbnail)
        XCTAssertFalse(m2c.variants.isEmpty)
        XCTAssertEqual(m2c.variants.first { $0.option.variantId == "base" }?.stars, 2)
    }

    func testLosFlaresColapsanAUnaCeldaDeFamiliaEnElHome() throws {
        let c = try catalog()
        let db = try XFDatabase.inMemory()
        let s = try HomeAssembler.summary(catalog: c, db: db, allUnlocked: true)
        let flare = try XCTUnwrap(s.cells.first { $0.scratchId == "flare" })
        XCTAssertTrue(flare.isFamily)
        XCTAssertEqual(flare.name, "Flare")
        XCTAssertEqual(flare.level, "L3")
        // ningun miembro suelto
        for m in ["flare-1c", "flare-2c", "orbit-1c", "transformer-3"] {
            XCTAssertNil(s.cells.first { $0.scratchId == m })
        }
        // miniatura de familia (la del primer miembro)
        XCTAssertNotNil(s.thumbnails["flare"])
    }

    func testAllUnlockedAbreNivelesYVariantes() throws {
        let c = try catalog()
        let db = try XFDatabase.inMemory()

        // niveles
        let open = LevelGate.unlockedLevels(catalog: c, allUnlocked: true) { _ in 0 }
        XCTAssertEqual(open, Set(c.levels.map(\.id)))

        // libreria: hasta el crab (nivel alto) sale desbloqueado
        let b = try LibraryAssembler.browser(catalog: c, db: db, allUnlocked: true)
        XCTAssertEqual(b.entries.first { $0.scratchId == "crab" }?.isUnlocked, true)

        // variantes: todas abiertas
        let opts = try VariantAssembler.options(
            catalog: c, exerciseId: "ex-l1-baby", db: db, allUnlocked: true)
        XCTAssertTrue(opts.allSatisfy { $0.isUnlocked })

        // ficha: idem
        let d = try XCTUnwrap(try ExerciseDetailAssembler.display(
            catalog: c, db: db, scratchId: "flare-2c", allUnlocked: true))
        XCTAssertTrue(d.variants.allSatisfy { $0.option.isUnlocked })
    }

    func testDetalleDeUnScratchInexistenteEsNil() throws {
        let c = try catalog()
        let db = try XFDatabase.inMemory()
        XCTAssertNil(try ExerciseDetailAssembler.display(catalog: c, db: db, scratchId: "no-existe"))
    }

    func testDescripcionSinteticaMencionaLosClicks() throws {
        let c = try catalog()
        let db = try XFDatabase.inMemory()
        let d = try XCTUnwrap(try ExerciseDetailAssembler.display(
            catalog: c, db: db, scratchId: "flare-3c"))
        XCTAssertTrue(d.description.contains("clicks de fader"), d.description)
    }
}
