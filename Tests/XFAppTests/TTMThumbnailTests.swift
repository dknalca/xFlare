// SPDX-License-Identifier: GPL-3.0-only
import XCTest
@testable import XFApp
import XFNotation
import XFPersistence

/// Miniatura TTM de la celda: curva del disco partida donde el fader cierra
/// (ausencia = mute) + un círculo por transición de fader.
final class TTMThumbnailTests: XCTestCase {

    private func library() throws -> ScratchLibrary {
        try CatalogLoader.load(from: RepoContentLoader()).library
    }

    func testBabyEsUnSoloTramoSinCortes() throws {
        // el baby no toca el fader: una curva continua, sin círculos
        let baby = try XCTUnwrap(try library().scratch(id: "baby"))
        let thumb = TTMThumbnail.build(scratch: baby)

        XCTAssertEqual(thumb.segments.count, 1)
        XCTAssertTrue(thumb.cuts.isEmpty)
        let pts = thumb.segments[0]
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

    func testFlareSePARTEEnTramosYTieneCirculos() throws {
        // el flare cierra el fader varias veces: varios tramos + un círculo por corte
        let flare = try XCTUnwrap(try library().scratch(id: "flare-1c"))
        let thumb = TTMThumbnail.build(scratch: flare)

        XCTAssertGreaterThan(thumb.segments.count, 1, "la curva se corta en los mutes")
        XCTAssertFalse(thumb.cuts.isEmpty)
        // hueco entre tramos: el último x de un tramo < primer x del siguiente
        for (a, b) in zip(thumb.segments, thumb.segments.dropFirst()) {
            XCTAssertLessThan(a.last!.x, b.first!.x)
        }
        for c in thumb.cuts { XCTAssert((0...1).contains(c.x) && (0...1).contains(c.y)) }
    }

    func testSeConstruyeParaTodaLaLibreria() throws {
        for s in try library().scratches {
            let thumb = TTMThumbnail.build(scratch: s)
            XCTAssertFalse(thumb.segments.isEmpty)
        }
    }

    func testHomeAssemblerPoneMiniaturaSoloEnLosDosPrimerosDelNivel1() throws {
        let catalog = try CatalogLoader.load(from: RepoContentLoader())
        let db = try XFDatabase.inMemory()
        let summary = try HomeAssembler.summary(catalog: catalog, db: db)

        let firstLevel = try XCTUnwrap(catalog.levels.sorted { $0.id < $1.id }.first)
        let expected = Array(firstLevel.scratches.prefix(2))

        XCTAssertEqual(Set(summary.thumbnails.keys), Set(expected))
        XCTAssertEqual(summary.thumbnails.count, 2)
    }
}
