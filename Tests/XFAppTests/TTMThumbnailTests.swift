// SPDX-License-Identifier: GPL-3.0-only
import XCTest
@testable import XFApp
import XFNotation
import XFPersistence

/// La miniatura TTM de la celda de la matriz: curva normalizada + tramos de
/// fader cerrado. Se calcula de `Scratch` con `PositionSampler`.
final class TTMThumbnailTests: XCTestCase {

    private func library() throws -> ScratchLibrary {
        try CatalogLoader.load(from: RepoContentLoader()).library
    }

    func testCurvaNormalizadaAlCuadradoUnidad() throws {
        let baby = try XCTUnwrap(try library().scratch(id: "baby"))
        let thumb = TTMThumbnail.build(scratch: baby, samples: 40)

        XCTAssertEqual(thumb.curve.count, 41)
        XCTAssertEqual(Double(try XCTUnwrap(thumb.curve.first?.x)), 0, accuracy: 1e-9)
        XCTAssertEqual(Double(try XCTUnwrap(thumb.curve.last?.x)), 1, accuracy: 1e-9)
        for p in thumb.curve {
            XCTAssert((0...1).contains(p.x), "x fuera de rango: \(p.x)")
            XCTAssert((-1e-9...(1 + 1e-9)).contains(p.y), "y fuera de rango: \(p.y)")
        }
        // una curva de scratch no es plana: usa las dos mitades del eje y
        XCTAssertEqual(thumb.curve.map(\.y).min() ?? -1, 0, accuracy: 1e-6)
        XCTAssertEqual(thumb.curve.map(\.y).max() ?? -1, 1, accuracy: 1e-6)
    }

    func testFlareTieneTramosDeFaderCerrado() throws {
        // un flare cierra el fader 1+ veces por movimiento
        let flare = try XCTUnwrap(try library().scratch(id: "flare-1c"))
        let thumb = TTMThumbnail.build(scratch: flare)

        XCTAssertFalse(thumb.faderClosed.isEmpty, "el flare cierra el fader")
        for r in thumb.faderClosed {
            XCTAssert(r.lowerBound >= 0 && r.upperBound <= 1)
            XCTAssert(r.upperBound > r.lowerBound)
        }
    }

    func testBabySinEventosDeFaderNoTieneTramosCerrados() throws {
        // el baby es adelante-atras sin fader
        let baby = try XCTUnwrap(try library().scratch(id: "baby"))
        let thumb = TTMThumbnail.build(scratch: baby)
        XCTAssertTrue(thumb.faderClosed.isEmpty)
    }

    func testSeConstruyeParaTodaLaLibreria() throws {
        for s in try library().scratches {
            let thumb = TTMThumbnail.build(scratch: s)
            XCTAssertGreaterThanOrEqual(thumb.curve.count, 3)
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
