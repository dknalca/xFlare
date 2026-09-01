// SPDX-License-Identifier: GPL-3.0-only
import XCTest
import CoreGraphics
@testable import XFRender
import XFNotation

/// ADR-040 — la sombra (curva del disco) se parte donde el fader está cerrado:
/// el tramo mudo no se dibuja, el corte lo marcan los círculos ○/●.
final class HighwayGhostSegmentsTests: XCTestCase {

    private let geo = HighwayGeometry(
        size: CGSize(width: 2000, height: 600),
        playheadFraction: 0.30, pixelsPerBeat: 120, laneHeight: 40, curveInset: 16)

    private func scratch(_ id: String) throws -> Scratch {
        try XCTUnwrap(try RenderFixtures.library().scratch(id: id))
    }

    func testBabySinFaderEsUnSoloTramo() throws {
        let layout = HighwayLayout(scratch: try scratch("baby"))
        let f = layout.frame(atTick: 0, geometry: geo)
        XCTAssertEqual(f.discSegments.count, 1)
        // el tramo unico == la curva entera
        XCTAssertEqual(f.discSegments.first?.count, f.discCurve.count)
    }

    func testForwardCutSePARTEConHuecos() throws {
        let s = try scratch("forward-cut")
        let f = HighwayLayout(scratch: s).frame(atTick: 0, geometry: geo)

        XCTAssertGreaterThan(f.discSegments.count, 1, "la curva se corta en los mutes")
        // entre un tramo y el siguiente hay un hueco (x del final < x del inicio siguiente)
        for (a, b) in zip(f.discSegments, f.discSegments.dropFirst()) {
            XCTAssertLessThan(a.last!.x, b.first!.x)
        }
        // la suma de puntos de los tramos es menor que muestrear la curva entera:
        // se han quitado los tramos mudos
        let inSegs = f.discSegments.reduce(0) { $0 + $1.count }
        XCTAssertLessThan(inSegs, f.discCurve.count)
        // los circulos de corte siguen ahi
        XCTAssertFalse(f.openMarks.isEmpty)
        XCTAssertFalse(f.closeMarks.isEmpty)
    }

    func testInvarianciaTrasUnLoop() throws {
        let s = try scratch("forward-cut")
        let layout = HighwayLayout(scratch: s)
        let L = Double(s.lengthTicks)
        let a = layout.frame(atTick: 501, geometry: geo)
        let b = layout.frame(atTick: 501 + L, geometry: geo)
        XCTAssertEqual(a.discSegments, b.discSegments)
        XCTAssertEqual(a, b)
    }

    func testTodosLosScratchesProducenAlMenosUnTramo() throws {
        for sc in try RenderFixtures.library().scratches {
            let f = HighwayLayout(scratch: sc).frame(atTick: 250, geometry: geo)
            XCTAssertFalse(f.discSegments.isEmpty, "\(sc.id)")
        }
    }
}
