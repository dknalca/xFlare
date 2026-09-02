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

    func testPatternFillDejaHuecoArribaYExtrapolaLaTraza() throws {
        let s = try scratch("baby")
        // patternFill 2/3: el patron ocupa los 2/3 de abajo de la banda
        let g = HighwayGeometry(size: CGSize(width: 2000, height: 600),
                                playheadFraction: 0.30, pixelsPerBeat: 120,
                                laneHeight: 40, curveInset: 16, patternFill: 2.0/3.0)
        let layout = HighwayLayout(scratch: s)
        let band = g.curveBand
        let bandH = band.top - band.bottom
        let range = layout.positionRange

        // el pico del fantasma (posicion maxima) cae a 2/3 de la banda, no arriba
        let f = layout.frame(atTick: 0, geometry: g)
        let ghostTopY = f.discCurve.map(\.y).max() ?? 0
        XCTAssertEqual(Double(ghostTopY - band.bottom), Double(bandH * 2.0/3.0), accuracy: 2)
        XCTAssertLessThan(ghostTopY, band.top - 1, "queda hueco arriba")

        // una traza del usuario pasada del pico se extrapola hacia ese hueco:
        // posicion = upper + 0.5*span  ->  y ~ tope de la banda
        let over = range.upperBound + 0.5 * (range.upperBound - range.lowerBound)
        let f2 = layout.frame(atTick: 0, geometry: g,
                              userTrace: [TracePoint(tick: 0, position: over, level: nil),
                                          TracePoint(tick: 100, position: over, level: nil)])
        let userY = f2.userSegments.flatMap { $0.points.map(\.y) }.max() ?? 0
        XCTAssertEqual(Double(userY - band.bottom), Double(bandH), accuracy: 3)
    }

    func testTodosLosScratchesProducenAlMenosUnTramo() throws {
        for sc in try RenderFixtures.library().scratches {
            let f = HighwayLayout(scratch: sc).frame(atTick: 250, geometry: geo)
            XCTAssertFalse(f.discSegments.isEmpty, "\(sc.id)")
        }
    }

    // ADR-044 — phantom clicks: el baby (fader abierto, ida y vuelta) tiene un
    // cambio de sentido por medio ciclo; ahí va una marca phantom.
    func testBabyTienePhantomClicksEnLosCambiosDeSentido() throws {
        let s = try scratch("baby")
        let f = HighwayLayout(scratch: s).frame(atTick: 0, geometry: geo)
        XCTAssertFalse(f.phantomMarks.isEmpty, "el baby cambia de sentido y eso corta el sonido")
        // caen sobre la curva del fantasma (misma banda vertical)
        let ys = f.discCurve.map(\.y)
        for m in f.phantomMarks {
            XCTAssertGreaterThanOrEqual(m.y, (ys.min() ?? 0) - 1)
            XCTAssertLessThanOrEqual(m.y, (ys.max() ?? 0) + 1)
        }
    }

    func testForwardCutNoTienePhantomsDondeElFaderEstaCerrado() throws {
        // en el forward cut la vuelta va con el fader cerrado: el cambio de
        // sentido de vuelta->ida ocurre en mute, no cuenta como phantom.
        let s = try scratch("forward-cut")
        let f = HighwayLayout(scratch: s).frame(atTick: 0, geometry: geo)
        // hay menos phantoms que cambios de sentido totales
        let reversals = zip(s.record, s.record.dropFirst()).filter {
            ($0.0.dir == .fwd && $0.1.dir == .rev) || ($0.0.dir == .rev && $0.1.dir == .fwd)
        }.count
        XCTAssertLessThan(f.phantomMarks.count, reversals * 3, "algunos caen en mute y se descartan")
    }

    func testPhantomMarksInvarianteTrasUnLoop() throws {
        let s = try scratch("baby")
        let layout = HighwayLayout(scratch: s)
        let L = Double(s.lengthTicks)
        XCTAssertEqual(layout.frame(atTick: 133, geometry: geo).phantomMarks,
                       layout.frame(atTick: 133 + L, geometry: geo).phantomMarks)
    }
}
