// SPDX-License-Identifier: GPL-3.0-only
import XCTest
@testable import XFApp
import XFNotation
import XFPersistence

/// Miniatura del esquema simple TTM: UNA curva continua + un círculo ● en cada
/// corte (el fader cierra). Sin círculo al abrir, sin huecos.
final class TTMThumbnailTests: XCTestCase {

    private func library() throws -> ScratchLibrary {
        try CatalogLoader.load(from: RepoContentLoader()).library
    }

    func testBabyEsUnaCurvaContinuaSinCortes() throws {
        // el baby no toca el fader: una curva continua, sin círculos
        let baby = try XCTUnwrap(try library().scratch(id: "baby"))
        let thumb = TTMThumbnail.build(scratch: baby)

        XCTAssertTrue(thumb.cuts.isEmpty, "el baby no corta")
        let pts = thumb.curve
        XCTAssertGreaterThan(pts.count, 8)
        XCTAssertEqual(Double(try XCTUnwrap(pts.first?.x)), 0, accuracy: 1e-9)
        XCTAssertEqual(Double(try XCTUnwrap(pts.last?.x)), 1, accuracy: 0.05)
        for p in pts {
            XCTAssert((0...1).contains(p.x))
            XCTAssert((-1e-9...(1 + 1e-9)).contains(p.y))
        }
        // usa casi todo el eje y (el muestreo no cae justo en los extremos)
        XCTAssertLessThan(pts.map(\.y).min() ?? 1, 0.03)
        XCTAssertGreaterThan(pts.map(\.y).max() ?? 0, 0.97)
    }

    func testElFlareEsUnaCurvaContinuaConCortes() throws {
        // el flare cierra el fader: la curva NO se parte, y hay un ● por corte
        let flare = try XCTUnwrap(try library().scratch(id: "flare-1c"))
        let thumb = TTMThumbnail.build(scratch: flare)

        XCTAssertFalse(thumb.cuts.isEmpty, "el flare corta al menos una vez")
        // la curva es una sola polilínea continua (x monótona creciente)
        for (a, b) in zip(thumb.curve, thumb.curve.dropFirst()) {
            XCTAssertLessThanOrEqual(a.x, b.x + 1e-9)
        }
        for c in thumb.cuts {
            XCTAssert((0...1).contains(c.x) && (0...1).contains(c.y))
        }
    }

    func testElChirpTieneUnCorte() throws {
        // chirp: arranca con el fader cerrado (eso ya es un corte) y abre al
        // volver. La miniatura marca el corte, no la apertura.
        let chirp = try XCTUnwrap(try library().scratch(id: "chirp"))
        let t = TTMThumbnail.build(scratch: chirp)
        XCTAssertFalse(t.cuts.isEmpty, "el chirp corta")
        XCTAssertFalse(t.curve.isEmpty)
    }

    func testSeConstruyeParaTodaLaLibreria() throws {
        for s in try library().scratches {
            let thumb = TTMThumbnail.build(scratch: s)
            XCTAssertGreaterThan(thumb.curve.count, 2, "\(s.id) sin curva")
        }
    }

    func testHomeAssemblerPoneMiniaturaEnTodosLosEjerciciosDelCurriculo() throws {
        let catalog = try CatalogLoader.load(from: RepoContentLoader())
        let db = try XFDatabase.inMemory()
        let summary = try HomeAssembler.summary(catalog: catalog, db: db)

        // miniatura para TODO scratch que tenga ejercicio (L1..L6), no solo L1
        let expected = Set(catalog.exercises.map(\.scratchId))
        XCTAssertTrue(Set(summary.thumbnails.keys).isSuperset(of: expected))
        XCTAssertFalse(expected.isEmpty)
        // y tambien para cada familia (usa la miniatura de su primer miembro)
        for fam in catalog.families {
            XCTAssertNotNil(summary.thumbnails[fam.id], "familia \(fam.id) sin miniatura")
        }
        // p. ej. un scratch de L2
        if let l2 = catalog.levels.first(where: { $0.id == "L2" })?.scratches.first {
            XCTAssertNotNil(summary.thumbnails[l2])
        }
    }
}
