// SPDX-License-Identifier: GPL-3.0-only
import XCTest
@testable import XFApp

/// Carga del contenido de solo lectura (`data/`) desde el repo.
final class CatalogLoaderTests: XCTestCase {

    private func catalog() throws -> Catalog {
        try CatalogLoader.load(from: RepoContentLoader())
    }

    func testCargaLaLibreriaYElCurriculo() throws {
        let c = try catalog()
        XCTAssertGreaterThanOrEqual(c.library.scratches.count, 25)
        XCTAssertEqual(c.levels.map(\.id), ["L1", "L2", "L3", "L4", "L5", "L6"])
        XCTAssertEqual(c.exercises.count, 18)   // 21 - 3 (scribble, hydroplane, twiddle: retirados 2026-09-03)
        XCTAssertEqual(c.variants.map(\.id), ["base"])   // variantes desactivadas de momento
    }

    func testCargaLasFamilias() throws {
        let c = try catalog()
        XCTAssertEqual(Set(c.families.map(\.id)), ["flare", "transformer"])

        let flare = try XCTUnwrap(c.family(id: "flare"))
        XCTAssertEqual(flare.members, ["flare-1c", "flare-2c", "flare-3c", "orbit-1c", "orbit-2c"])
        XCTAssertFalse(flare.blurb.isEmpty)
        XCTAssertNotNil(flare.history)

        // todo miembro es un scratch real y tiene ejercicio
        for m in c.families.flatMap(\.members) {
            XCTAssertNotNil(c.library.scratch(id: m), "\(m) no esta en la libreria")
            XCTAssertNotNil(c.exercise(forScratch: m), "\(m) no tiene ejercicio")
        }
        // y la busqueda inversa
        XCTAssertEqual(c.family(containingScratch: "orbit-2c")?.id, "flare")
        XCTAssertEqual(c.family(containingScratch: "transformer-3")?.id, "transformer")
        XCTAssertNil(c.family(containingScratch: "baby"))
    }

    func testCadaEjercicioApuntaAUnScratchReal() throws {
        let c = try catalog()
        for ex in c.exercises {
            XCTAssertNotNil(c.library.scratch(id: ex.scratchId),
                            "\(ex.id) apunta a \(ex.scratchId), que no esta en la libreria")
        }
    }

    func testCadaScratchDeUnNivelTieneEjercicio() throws {
        let c = try catalog()
        let scratchIdsConEjercicio = Set(c.exercises.map(\.scratchId))
        for level in c.levels {
            for s in level.scratches {
                XCTAssertTrue(scratchIdsConEjercicio.contains(s), "\(s) (nivel \(level.id)) sin ejercicio")
            }
        }
    }

    func testLaBaseNoTieneCondicion() throws {
        let c = try catalog()
        let base = try XCTUnwrap(c.variant(id: "base"))
        XCTAssertTrue(base.isBase)
        XCTAssertNil(base.requirement)
        XCTAssertEqual(base.difficulty, 1.0, accuracy: 1e-9)
    }

    func testLookups() throws {
        let c = try catalog()
        XCTAssertEqual(c.exercise(forScratch: "baby")?.id, "ex-l1-baby")
        XCTAssertEqual(c.exercise(id: "ex-l1-baby")?.scratchId, "baby")
        XCTAssertEqual(c.exercise(id: "ex-l1-baby")?.bpmLadder, [50, 60, 70, 80, 90])
    }
}
