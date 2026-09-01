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
        XCTAssertEqual(c.exercises.count, 25)
        XCTAssertEqual(c.variants.count, 10)
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

    func testLaBaseNoTieneCondicionYLasDemasSi() throws {
        let c = try catalog()
        let base = try XCTUnwrap(c.variant(id: "base"))
        XCTAssertTrue(base.isBase)
        XCTAssertNil(base.requirement)

        let off50 = try XCTUnwrap(c.variant(id: "off50"))
        XCTAssertEqual(off50.requirement, .init(variant: "base", stars: 2))
        XCTAssertEqual(off50.difficulty, 1.25, accuracy: 1e-9)
    }

    func testLookups() throws {
        let c = try catalog()
        XCTAssertEqual(c.exercise(forScratch: "baby")?.id, "ex-l1-baby")
        XCTAssertEqual(c.exercise(id: "ex-l1-baby")?.scratchId, "baby")
        XCTAssertEqual(c.exercise(id: "ex-l1-baby")?.bpmLadder, [50, 60, 70, 80, 90])
    }
}
