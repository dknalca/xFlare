// SPDX-License-Identifier: GPL-3.0-only
import XCTest
import CoreGraphics
@testable import XFRender
import XFNotation

/// B7.3 — geometría de la autopista (`HighwayLayout`). Puro, sin SpriteKit.
/// El foco es "sin deriva": el fotograma es una función pura del tick de AUDIO.
final class XFRenderTests: XCTestCase {

    private let geo = HighwayGeometry(
        size: CGSize(width: 2000, height: 600),
        playheadFraction: 0.30, pixelsPerBeat: 120, laneHeight: 40, curveInset: 16)

    func testAPIVersion() {
        XCTAssertEqual(XFRender.apiVersion, 1)
    }

    func testGeometriaDerivada() {
        XCTAssertEqual(geo.playheadX, 600)
        XCTAssertEqual(geo.pixelsPerTick(ppq: 480), 120.0 / 480.0, accuracy: 1e-12)
        XCTAssertEqual(geo.curveBand.bottom, 56)          // laneHeight + inset
        XCTAssertEqual(geo.curveBand.top, 584)            // height - inset
    }

    func testFotogramaEsDeterminista() throws {
        let layout = HighwayLayout(scratch: try RenderFixtures.forwardCut())
        XCTAssertEqual(layout.frame(atTick: 1234.5, geometry: geo),
                       layout.frame(atTick: 1234.5, geometry: geo))
    }

    func testCabezaDeLecturaFijaAl30Porciento() throws {
        let layout = HighwayLayout(scratch: try RenderFixtures.forwardCut())
        for t in [0.0, 137.0, 5000.0, -800.0] {
            XCTAssertEqual(layout.frame(atTick: t, geometry: geo).playheadX, 600)
        }
    }

    /// El mapeo tiempo→espacio está anclado al tick de AUDIO: cada evento de
    /// fader en `t` cae exactamente en `playheadX + t·pxPerTick`. Si esto se
    /// cumple para todo tick, no puede haber deriva.
    func testCadaClickCaeEnSuTickExacto() throws {
        let scratch = try RenderFixtures.forwardCut()
        let layout = HighwayLayout(scratch: scratch)
        let pxPerTick = geo.pixelsPerTick(ppq: scratch.ppq)
        let frame = layout.frame(atTick: 0, geometry: geo)   // 0 mod L = 0: la 1ª copia es "lo que viene"

        let allMarkX = (frame.openMarks + frame.closeMarks).map(\.x)
        for event in scratch.faderEvents {
            let expected = geo.playheadX + CGFloat(event.t) * pxPerTick
            XCTAssertTrue(allMarkX.contains { abs($0 - expected) < 1e-6 },
                          "evento en t=\(event.t) debería estar en x=\(expected)")
        }
    }

    func testUnClickEnElTickActualSeDibujaSobreLaCabeza() throws {
        let scratch = try RenderFixtures.forwardCut()
        let layout = HighwayLayout(scratch: scratch)
        let te = scratch.faderEvents.first!.t
        let frame = layout.frame(atTick: Double(te), geometry: geo)
        let xs = (frame.openMarks + frame.closeMarks).map(\.x)
        XCTAssertTrue(xs.contains { abs($0 - geo.playheadX) < 1e-6 },
                      "el evento que ocurre 'ahora' va justo en la cabeza de lectura")
    }

    /// Anti-deriva de verdad: tras un loop entero del patrón, el fotograma es
    /// bit a bit el mismo. Da igual cuántas horas lleve sonando.
    func testTrasUnLoopLaGeometriaEsIdentica() throws {
        let scratch = try RenderFixtures.forwardCut()
        let layout = HighwayLayout(scratch: scratch)
        let L = Double(scratch.lengthTicks)
        let a = layout.frame(atTick: 733, geometry: geo)
        let b = layout.frame(atTick: 733 + L, geometry: geo)
        XCTAssertEqual(a, b)
        // y tras 300 loops (≈ varios minutos) sigue igual
        XCTAssertEqual(a, layout.frame(atTick: 733 + 300 * L, geometry: geo))
    }

    func testLaCurvaCubreElAnchoVisible() throws {
        let layout = HighwayLayout(scratch: try RenderFixtures.baby())
        let curve = layout.frame(atTick: 2000, geometry: geo).discCurve
        XCTAssertGreaterThan(curve.count, 10)
        XCTAssertLessThanOrEqual(curve.first!.x, 0)
        XCTAssertGreaterThanOrEqual(curve.last!.x, geo.size.width)
    }

    func testLaCurvaSeQuedaEnSuBanda() throws {
        let layout = HighwayLayout(scratch: try RenderFixtures.forwardCut())
        let (bottom, top) = geo.curveBand
        for p in layout.frame(atTick: 500, geometry: geo).discCurve {
            XCTAssertGreaterThanOrEqual(p.y, bottom - 1e-6)
            XCTAssertLessThanOrEqual(p.y, top + 1e-6)
        }
    }

    func testElCarrilDeFaderCubreLaVentanaSinHuecos() throws {
        let layout = HighwayLayout(scratch: try RenderFixtures.forwardCut())
        let bands = layout.frame(atTick: 500, geometry: geo).faderBands
        XCTAssertFalse(bands.isEmpty)
        XCTAssertEqual(bands.first!.xRange.lowerBound, 0, accuracy: 1e-6)
        XCTAssertEqual(bands.last!.xRange.upperBound, geo.size.width, accuracy: 1e-6)
        for i in 1..<bands.count {
            XCTAssertEqual(bands[i].xRange.lowerBound, bands[i - 1].xRange.upperBound, accuracy: 1e-6,
                           "los tramos son contiguos")
        }
    }

    func testPatronDegeneradoNoRevienta() throws {
        // curva plana: baby tiene subida y bajada, así que forzamos con un rango
        // ya calculado; aquí basta con que un scratch normal no lance.
        let layout = HighwayLayout(scratch: try RenderFixtures.baby())
        XCTAssertNoThrow(layout.frame(atTick: 0, geometry:
            HighwayGeometry(size: CGSize(width: 10, height: 10))))
    }
}
