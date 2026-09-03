// SPDX-License-Identifier: GPL-3.0-only
import XCTest
@testable import XFApp
import XFNotation
import XFPersistence

/// Miniatura del esquema simple TTM: la curva del disco **solo donde suena**
/// (tramos con el fader abierto) + un ● por corte, alineados en una fila arriba.
final class TTMThumbnailTests: XCTestCase {

    private func library() throws -> ScratchLibrary {
        try CatalogLoader.load(from: RepoContentLoader()).library
    }

    private func allPoints(_ t: TTMThumbnail) -> [CGPoint] { t.segments.flatMap { $0 } }

    func testBabyEsUnTramoUnicoSinCortes() throws {
        // el baby no toca el fader: un solo tramo, sin círculos
        let baby = try XCTUnwrap(try library().scratch(id: "baby"))
        let thumb = TTMThumbnail.build(scratch: baby)

        XCTAssertTrue(thumb.cuts.isEmpty, "el baby no corta")
        XCTAssertEqual(thumb.segments.count, 1, "fader siempre abierto -> un tramo")
        let pts = allPoints(thumb)
        XCTAssertGreaterThan(pts.count, 8)
        XCTAssertEqual(Double(try XCTUnwrap(pts.first?.x)), 0, accuracy: 0.02)
        XCTAssertEqual(Double(try XCTUnwrap(pts.last?.x)), 1, accuracy: 0.05)
        for p in pts {
            XCTAssert((0...1).contains(p.x))
            XCTAssert((-1e-9...(1 + 1e-9)).contains(p.y))
        }
        XCTAssertLessThan(pts.map(\.y).min() ?? 1, 0.03)
        XCTAssertGreaterThan(pts.map(\.y).max() ?? 0, 0.97)
    }

    func testElForwardCutNoDibujaLaVueltaMuda() throws {
        // "solo suena la ida": debe haber tramo que suena y NO cubrir todo el
        // eje x (la parte muda no se pinta) + un corte.
        let fc = try XCTUnwrap(try library().scratch(id: "forward-cut"))
        let t = TTMThumbnail.build(scratch: fc)
        XCTAssertFalse(t.cuts.isEmpty, "forward cut corta")
        let xs = allPoints(t).map(\.x)
        XCTAssertLessThan((xs.max() ?? 0) - (xs.min() ?? 1), 0.9,
                          "la vuelta silenciosa no se dibuja")
    }

    func testLosCortesDelFlareVanEnUnaHorizontalYSonSimetricos() throws {
        // flare-2c: fader open, 2 clicks por trazo -> los ● se alinean en una
        // misma horizontal y se reparten simétricos respecto al centro.
        let flare = try XCTUnwrap(try library().scratch(id: "flare-2c"))
        let t = TTMThumbnail.build(scratch: flare)
        let cuts = t.cuts

        XCTAssertGreaterThanOrEqual(cuts.count, 2)
        XCTAssertEqual(cuts.count % 2, 0, "pares espejo")
        // ninguno se sale del cuadro, y con margen de sobra respecto al borde
        for c in cuts { XCTAssert((0.05...0.95).contains(c.x) && (0.1...0.9).contains(c.y)) }
        // todos a la MISMA altura
        let ys = cuts.map { Double($0.y) }
        XCTAssertEqual(ys.max()! - ys.min()!, 0, accuracy: 1e-9, "una sola horizontal")
        // ordenados por x y simétricos respecto al centro (x_i + x_{n-1-i} ≈ 1)
        for (a, b) in zip(cuts, cuts.dropFirst()) { XCTAssertLessThan(a.x, b.x) }
        for i in 0..<(cuts.count / 2) {
            let a = cuts[i], b = cuts[cuts.count - 1 - i]
            XCTAssertEqual(Double(a.x + b.x), 1.0, accuracy: 0.02, "x simétrica")
        }
    }

    func testElChirpPoneUnPuntoEnElVertice() throws {
        // chirp: un único ● y cae en el vértice del movimiento (arriba del todo).
        let chirp = try XCTUnwrap(try library().scratch(id: "chirp"))
        let t = TTMThumbnail.build(scratch: chirp)
        XCTAssertEqual(t.cuts.count, 1, "un solo corte visible")
        let c = try XCTUnwrap(t.cuts.first)
        XCTAssertGreaterThan(Double(c.y), 0.75, "cerca del punto más alto de la curva")
    }

    func testElChirpTieneUnCorteYAlgoQueSuena() throws {
        let chirp = try XCTUnwrap(try library().scratch(id: "chirp"))
        let t = TTMThumbnail.build(scratch: chirp)
        XCTAssertFalse(t.cuts.isEmpty, "el chirp corta")
        XCTAssertFalse(t.segments.isEmpty, "y algo suena")
    }

    func testSeConstruyeParaTodaLaLibreria() throws {
        for s in try library().scratches {
            let thumb = TTMThumbnail.build(scratch: s)
            XCTAssertFalse(thumb.segments.isEmpty, "\(s.id) sin tramos que suenen")
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
