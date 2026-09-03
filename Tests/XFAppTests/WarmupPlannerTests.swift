// SPDX-License-Identifier: GPL-3.0-only
import XCTest
@testable import XFApp
import XFPersistence

/// F.0 / ADR-027 — el planificador del calentamiento (`docs/WARMUP.md`). Lógica
/// pura: se le dan candidatos y devuelve el plan.
final class WarmupPlannerTests: XCTestCase {

    /// LCG determinista, mismos números en cada corrida y arquitectura.
    struct SeededRNG: RandomNumberGenerator {
        var state: UInt64
        mutating func next() -> UInt64 {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return state
        }
    }

    private func candidate(_ id: String, family: String? = nil,
                           days: Double = 3, avg: Double? = 0.9, ceiling: Double? = 0.95,
                           masteryAge: Double = 30,
                           variants: [String] = ["base"], last: String? = nil)
    -> WarmupPlanner.Candidate {
        WarmupPlanner.Candidate(exerciseId: id, name: id, familyId: family,
                                daysSinceReview: days, recentAverage: avg, ceiling: ceiling,
                                masteryAgeDays: masteryAge, unlockedVariants: variants,
                                lastWarmupVariant: last)
    }

    func testSinCandidatosPlanVacio() {
        var rng = SeededRNG(state: 1)
        XCTAssertTrue(WarmupPlanner.plan([], rng: &rng).isEmpty)
    }

    func testConMenosDelMinimoLosCogeTodos() {
        var rng = SeededRNG(state: 1)
        let plan = WarmupPlanner.plan(
            [candidate("a"), candidate("b"), candidate("c")], minCount: 4, maxCount: 6, rng: &rng)
        XCTAssertEqual(plan.count, 3)
    }

    func testRespetaElMaximo() {
        var rng = SeededRNG(state: 1)
        let cs = (0..<10).map { candidate("e\($0)") }
        XCTAssertEqual(WarmupPlanner.plan(cs, minCount: 4, maxCount: 6, rng: &rng).count, 6)
    }

    func testLoUrgenteAntesQueLoFresco() {
        var rng = SeededRNG(state: 42)
        let cs = [
            candidate("fresco", days: 0, avg: 0.95, ceiling: 0.95),        // nada urgente
            candidate("olvidado", days: 21, avg: 0.9, ceiling: 0.92),      // hace mucho
            candidate("cayendose", days: 4, avg: 0.72, ceiling: 0.95),     // media << techo
        ]
        let plan = WarmupPlanner.plan(cs, minCount: 3, maxCount: 3, rng: &rng)
        // los dos urgentes van delante; el fresco, el último. Cuál de los dos es
        // el 1º es cuestión de afinar pesos (como B8.4), no se fija aquí.
        XCTAssertEqual(plan.last?.exerciseId, "fresco")
        XCTAssertEqual(Set(plan.prefix(2).map(\.exerciseId)), ["cayendose", "olvidado"])
        // el motivo del que se cae menciona la media y el techo
        let cae = plan.first { $0.exerciseId == "cayendose" }
        XCTAssertTrue(cae?.reason.contains("techo") ?? false)
    }

    func testVariedadDeFamilia() {
        var rng = SeededRNG(state: 7)
        // 4 flares y 2 transformers, todos con la misma urgencia
        let cs = (0..<4).map { candidate("flare\($0)", family: "flare") }
               + (0..<2).map { candidate("tf\($0)", family: "transformer") }
        let plan = WarmupPlanner.plan(cs, minCount: 6, maxCount: 6, rng: &rng)
        XCTAssertEqual(plan.count, 6)
        // no salen los 4 flares antes que ningún transformer
        let firstTransformerAt = plan.firstIndex { $0.exerciseId.hasPrefix("tf") } ?? 99
        XCTAssertLessThan(firstTransformerAt, 4, "un transformer debe colarse antes del 4º flare")
    }

    func testVarianteDistintaALaDeLaVezAnterior() {
        let c = candidate("orbit", variants: ["base", "div16", "mirror"], last: "div16")
        // 20 tiradas con semillas distintas: nunca repite la del último calentamiento
        for seed in 1...20 {
            var r = SeededRNG(state: UInt64(seed))
            let plan = WarmupPlanner.plan([c], minCount: 1, maxCount: 1, rng: &r)
            XCTAssertNotEqual(plan.first?.variantId, "div16")
            XCTAssertTrue(["base", "mirror"].contains(plan.first?.variantId ?? ""))
        }
    }

    func testUnaSolaVarianteUsaEsa() {
        var rng = SeededRNG(state: 1)
        let c = candidate("x", variants: ["base"], last: "base")
        let plan = WarmupPlanner.plan([c], minCount: 1, maxCount: 1, rng: &rng)
        XCTAssertEqual(plan.first?.variantId, "base")
    }

    // MARK: - oxidación

    func testDosEstrellasOMasNoEsOxidacion() {
        let r = WarmupOxidation.check(exerciseName: "crab", starsInWarmup: 2,
                                      accuracy: 0.86, priorAverage: 0.94)
        XCTAssertFalse(r.oxidized)
        XCTAssertNil(r.message)
    }

    func testBajarDeDosEstrellasConMediaAltaAvisaDeCaida() {
        let r = WarmupOxidation.check(exerciseName: "crab", starsInWarmup: 1,
                                      accuracy: 0.78, priorAverage: 0.94)
        XCTAssertTrue(r.oxidized)
        XCTAssertEqual(r.message,
            "El crab se te está cayendo: hoy 78 %, tu media era 94 %. "
            + "Lo meto de vuelta en la rotación esta semana.")
    }

    func testBajarDeDosEstrellasSinHistorialTambienOxida() {
        let r = WarmupOxidation.check(exerciseName: "flare", starsInWarmup: 0,
                                      accuracy: 0.55, priorAverage: nil)
        XCTAssertTrue(r.oxidized)
        XCTAssertTrue(r.message?.contains("55 %") ?? false)
    }

    // MARK: - assembler (plan -> filas de pantalla)

    func testAssemblerResuelveNombresContraElCatalogo() throws {
        let cat = try CatalogLoader.load(from: RepoContentLoader())
        let ex = try XCTUnwrap(cat.exercises.first)
        let plan = [WarmupPlanner.PlannedItem(exerciseId: ex.id, variantId: "base",
                                              reason: "hace 5 días")]
        let rows = WarmupAssembler.rows(from: plan, catalog: cat)
        XCTAssertEqual(rows.count, 1)
        XCTAssertFalse(rows[0].name.isEmpty)
        XCTAssertEqual(rows[0].variantName, "")            // base -> sin nombre de variante
        XCTAssertEqual(rows[0].reason, "hace 5 días")
        XCTAssertEqual(rows[0].id, ex.id + "/base")
    }

    func testAssemblerDescartaEjerciciosDesconocidos() throws {
        let cat = try CatalogLoader.load(from: RepoContentLoader())
        let plan = [WarmupPlanner.PlannedItem(exerciseId: "no-existe",
                                              variantId: "base", reason: "x")]
        XCTAssertTrue(WarmupAssembler.rows(from: plan, catalog: cat).isEmpty)
    }

    // MARK: - rutina de arranque (sin historial)

    func testRutinaDeArranqueEsForwardReverseChirpTransformer() throws {
        let cat = try CatalogLoader.load(from: RepoContentLoader())
        let plan = WarmupAssembler.starterPlan(catalog: cat)
        let scratchIds = plan.compactMap { cat.exercise(id: $0.exerciseId)?.scratchId }
        XCTAssertEqual(scratchIds, ["forward-cut", "reverse-cut", "chirp", "transformer-2"])
        // cada uno: base, 8 frases de 2 compases
        for item in plan {
            XCTAssertEqual(item.variantId, "base")
            XCTAssertEqual(item.phraseBars, 2)
            XCTAssertEqual(item.phraseCount, 8)
        }
        let rows = WarmupAssembler.rows(from: plan, catalog: cat)
        XCTAssertEqual(rows.first?.phraseSummary, "8 frases de 2 compases")
    }

    func testElPlanCaeALaRutinaDeArranqueSiNoHayNadaDominado() throws {
        let cat = try CatalogLoader.load(from: RepoContentLoader())
        let m = AppModel(catalog: cat, db: try .inMemory())   // BD vacía: nada dominado
        var rng = SeededRNG(state: 1)
        let plan = m.warmupPlan(rng: &rng)
        XCTAssertEqual(plan.count, 4)
        XCTAssertEqual(plan.map { cat.exercise(id: $0.exerciseId)?.scratchId },
                       ["forward-cut", "reverse-cut", "chirp", "transformer-2"])
    }
}
