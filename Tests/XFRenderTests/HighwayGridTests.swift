// SPDX-License-Identifier: GPL-3.0-only
import XCTest
import CoreGraphics
@testable import XFRender
import XFNotation

/// ADR-038 — rejilla de negras y compás en la autopista. Puro (sin SpriteKit).
/// El foco, como en el resto de `HighwayLayout`, es que **no rompe la
/// invariancia anti-deriva**: `frame(T)` y `frame(T + L)` dan la misma rejilla.
final class HighwayGridTests: XCTestCase {

    private let geo = HighwayGeometry(
        size: CGSize(width: 2000, height: 600),
        playheadFraction: 0.30, pixelsPerBeat: 120, laneHeight: 40,
        curveInset: 16, beatsPerBar: 4)

    private func scratch(_ id: String) throws -> Scratch {
        try XCTUnwrap(try RenderFixtures.library().scratch(id: id))
    }

    func testHayLineasDeNegraYDeCompas() throws {
        let layout = HighwayLayout(scratch: try scratch("baby"))
        let frame = layout.frame(atTick: 0, geometry: geo)

        XCTAssertFalse(frame.beatLines.isEmpty)
        XCTAssertFalse(frame.barLines.isEmpty)
        // ninguna x está en las dos listas
        XCTAssertTrue(Set(frame.beatLines).isDisjoint(with: Set(frame.barLines)))
    }

    func testLaSeparacionEsUnaNegra() throws {
        let layout = HighwayLayout(scratch: try scratch("baby"))
        let frame = layout.frame(atTick: 137, geometry: geo)

        let all = (frame.beatLines + frame.barLines).sorted()
        XCTAssertGreaterThan(all.count, 4)
        for (a, b) in zip(all, all.dropFirst()) {
            XCTAssertEqual(b - a, geo.pixelsPerBeat, accuracy: 1e-6)
        }
    }

    func testUnaDeCadaCuatroEsDeCompas() throws {
        // baby = 1920 ticks = 4 negras = 1 compás exacto
        let layout = HighwayLayout(scratch: try scratch("baby"))
        let frame = layout.frame(atTick: 500, geometry: geo)
        let total = frame.beatLines.count + frame.barLines.count
        // ~1 de cada 4
        XCTAssertEqual(Double(frame.barLines.count), Double(total) / 4.0, accuracy: 1.0)
    }

    func testInvarianciaTrasUnLoopEntero_patronDeCompasExacto() throws {
        let s = try scratch("baby")                        // 1920 = 1 compás
        let layout = HighwayLayout(scratch: s)
        let L = Double(s.lengthTicks)

        let a = layout.frame(atTick: 733, geometry: geo)
        let b = layout.frame(atTick: 733 + L, geometry: geo)
        XCTAssertEqual(a.beatLines, b.beatLines)
        XCTAssertEqual(a.barLines, b.barLines)
        // y tras 300 loops
        let c = layout.frame(atTick: 733 + 300 * L, geometry: geo)
        XCTAssertEqual(a.beatLines, c.beatLines)
        XCTAssertEqual(a.barLines, c.barLines)
    }

    func testInvarianciaTrasUnLoopEntero_patronQueNoEsCompasExacto() throws {
        // flare-3c = 1440 ticks = 3 negras: NO es múltiplo de 4 negras. La
        // clasificación negra/compás es relativa al patrón, así que aún así
        // frame(T) == frame(T+L).
        let s = try scratch("flare-3c")
        let layout = HighwayLayout(scratch: s)
        let L = Double(s.lengthTicks)

        let a = layout.frame(atTick: 401, geometry: geo)
        let b = layout.frame(atTick: 401 + L, geometry: geo)
        XCTAssertEqual(a.beatLines, b.beatLines)
        XCTAssertEqual(a.barLines, b.barLines)
        XCTAssertEqual(a, b)   // el fotograma entero, no solo la rejilla
    }

    func testBeatsPerBarCambiaLaClasificacion() throws {
        let layout = HighwayLayout(scratch: try scratch("baby"))
        let geo3 = HighwayGeometry(size: geo.size, playheadFraction: 0.30,
                                   pixelsPerBeat: 120, laneHeight: 40,
                                   curveInset: 16, beatsPerBar: 3)
        let f4 = layout.frame(atTick: 0, geometry: geo)
        let f3 = layout.frame(atTick: 0, geometry: geo3)

        // mismo total de líneas, distinto reparto
        XCTAssertEqual(f4.beatLines.count + f4.barLines.count,
                       f3.beatLines.count + f3.barLines.count)
        XCTAssertNotEqual(f4.barLines, f3.barLines)
    }

    func testLasLineasCaenDentroDelLienzo() throws {
        let layout = HighwayLayout(scratch: try scratch("tear-flare-1c"))
        let frame = layout.frame(atTick: 999, geometry: geo)
        for x in frame.beatLines + frame.barLines {
            XCTAssert(x >= -0.5 && x <= geo.size.width + 0.5, "x fuera del lienzo: \(x)")
        }
    }
}
