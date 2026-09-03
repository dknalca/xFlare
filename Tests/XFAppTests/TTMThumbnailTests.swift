// SPDX-License-Identifier: GPL-3.0-only
import XCTest
@testable import XFApp
import XFNotation
import XFPersistence

/// Miniatura del esquema simple TTM: la curva del disco **entera**, partida en
/// tramos coloreados por el estado del fader (suena / cortado). Sin puntos.
final class TTMThumbnailTests: XCTestCase {

    private func library() throws -> ScratchLibrary {
        try CatalogLoader.load(from: RepoContentLoader()).library
    }

    func testBabyEsUnaCurvaEnteraQueSuena() throws {
        // el baby no toca el fader: un solo tramo, y suena
        let baby = try XCTUnwrap(try library().scratch(id: "baby"))
        let t = TTMThumbnail.build(scratch: baby)

        XCTAssertEqual(t.segments.count, 1, "fader siempre abierto -> un tramo")
        XCTAssertTrue(t.segments.allSatisfy { $0.sounding }, "todo suena")

        let pts = t.allPoints
        XCTAssertGreaterThan(pts.count, 8)
        XCTAssertEqual(Double(try XCTUnwrap(pts.first?.x)), 0, accuracy: 0.02)
        XCTAssertEqual(Double(try XCTUnwrap(pts.last?.x)), 1, accuracy: 0.05)
        // dentro del cuadro, con el margen del 8 %
        for p in pts {
            XCTAssert((0...1).contains(p.x))
            XCTAssert((0.07...0.93).contains(p.y), "y=\(p.y) fuera de margen")
        }
        // la curva llega arriba (vértice) y abajo dentro del margen
        XCTAssertGreaterThan(pts.map(\.y).max() ?? 0, 0.88, "el vértice se ve arriba")
        XCTAssertLessThan(pts.map(\.y).min() ?? 1, 0.12)
    }

    func testLaCurvaEsContiguaEnLosCambiosDeFader() throws {
        // el punto del cambio está en los dos tramos: sin saltos
        let fc = try XCTUnwrap(try library().scratch(id: "forward-cut"))
        let t = TTMThumbnail.build(scratch: fc)
        XCTAssertGreaterThanOrEqual(t.segments.count, 2)
        for (a, b) in zip(t.segments, t.segments.dropFirst()) {
            let end = try XCTUnwrap(a.points.last)
            let start = try XCTUnwrap(b.points.first)
            XCTAssertEqual(Double(end.x), Double(start.x), accuracy: 1e-6)
            XCTAssertEqual(Double(end.y), Double(start.y), accuracy: 1e-6)
            XCTAssertNotEqual(a.sounding, b.sounding, "tramos consecutivos alternan estado")
        }
    }

    func testElForwardCutDibujaLaVueltaComoCorte() throws {
        // "solo suena la ida": ahora la vuelta SÍ se dibuja, pero como tramo
        // cortado (gris), no como hueco.
        let fc = try XCTUnwrap(try library().scratch(id: "forward-cut"))
        let t = TTMThumbnail.build(scratch: fc)
        XCTAssertTrue(t.segments.contains { $0.sounding }, "algo suena")
        XCTAssertTrue(t.segments.contains { !$0.sounding }, "y algo está cortado")
        // la curva cubre todo el eje x (no hay huecos)
        let xs = t.allPoints.map(\.x)
        XCTAssertEqual(Double(xs.min() ?? 1), 0, accuracy: 0.02)
        XCTAssertEqual(Double(xs.max() ?? 0), 1, accuracy: 0.05)
    }

    func testElFlareAlternaTramosQueSuenanYCortados() throws {
        // flare-2c: fader open con cierres momentáneos -> la curva alterna
        // sounding / cortado varias veces.
        let flare = try XCTUnwrap(try library().scratch(id: "flare-2c"))
        let t = TTMThumbnail.build(scratch: flare)
        let cortes = t.segments.filter { !$0.sounding }.count
        XCTAssertGreaterThanOrEqual(cortes, 2, "un flare de 2 clicks corta varias veces")
        XCTAssertTrue(t.segments.contains { $0.sounding }, "y también suena")
        // nada se sale del cuadro
        for p in t.allPoints { XCTAssert((0...1).contains(p.x) && (0.05...0.95).contains(p.y)) }
    }

    func testTearFlareYCrabNoSeSalenDelCuadro() throws {
        // el bug anterior: los ● de tear-flare-1c y crab caían fuera de la curva.
        // Ahora no hay ●: solo la curva, siempre dentro.
        for id in ["tear-flare-1c", "crab"] {
            let s = try XCTUnwrap(try library().scratch(id: id))
            let t = TTMThumbnail.build(scratch: s)
            XCTAssertFalse(t.segments.isEmpty, "\(id) sin tramos")
            for p in t.allPoints {
                XCTAssert((0...1).contains(p.x), "\(id): x=\(p.x) fuera")
                XCTAssert((0.05...0.95).contains(p.y), "\(id): y=\(p.y) fuera")
            }
        }
    }

    func testSeConstruyeParaTodaLaLibreria() throws {
        for s in try library().scratches {
            let t = TTMThumbnail.build(scratch: s)
            XCTAssertFalse(t.segments.isEmpty, "\(s.id) sin curva")
            // todos los tramos con al menos 2 puntos (dibujables)
            XCTAssertTrue(t.segments.allSatisfy { $0.points.count >= 2 }, "\(s.id) con tramo vacío")
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
