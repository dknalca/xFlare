// SPDX-License-Identifier: GPL-3.0-only
import XCTest
import CoreGraphics
@testable import XFRender
import XFDesign
import XFNotation

/// B7.4 — capa de usuario sobre el fantasma y teñido por tolerancia.
final class HighwayUserLayerTests: XCTestCase {

    private let geo = HighwayGeometry(
        size: CGSize(width: 2000, height: 600),
        playheadFraction: 0.30, pixelsPerBeat: 120, laneHeight: 40, curveInset: 16)

    private func layout() throws -> HighwayLayout {
        HighwayLayout(scratch: try RenderFixtures.forwardCut())
    }

    /// Traza que sigue la posición del patrón entre dos ticks, con un nivel dado.
    private func trace(_ layout: HighwayLayout, from t0: Double, to t1: Double,
                       step: Double = 60, level: HitLevel? = nil) -> [TracePoint] {
        stride(from: t0, through: t1, by: step).map { t in
            let wrapped = Int(t.truncatingRemainder(dividingBy: Double(layout.scratch.lengthTicks))
                              .magnitude)
            return TracePoint(tick: t,
                              position: PositionSampler.position(of: layout.scratch, atTick: wrapped),
                              level: level)
        }
    }

    // MARK: - capa de usuario

    func testSinTrazaNoHayCapaDeUsuario() throws {
        let f = try layout().frame(atTick: 1000, geometry: geo)
        XCTAssertTrue(f.userSegments.isEmpty)
        XCTAssertTrue(f.hitMarks.isEmpty)
    }

    func testTrazaLimpiaEsUnSoloTramoDeAcento() throws {
        let l = try layout()
        let f = l.frame(atTick: 1000, geometry: geo,
                        userTrace: trace(l, from: -1200, to: 6400, level: nil))
        XCTAssertEqual(f.userSegments.count, 1)
        XCTAssertNil(f.userSegments[0].level, "dentro de tolerancia → acento")
        XCTAssertGreaterThan(f.userSegments[0].points.count, 50)
    }

    func testPerfectYNilNoParten() throws {
        let l = try layout()
        var pts = trace(l, from: 0, to: 4000, step: 100, level: nil)
        for i in stride(from: 0, to: pts.count, by: 2) { pts[i].level = .perfect }
        let f = l.frame(atTick: 1500, geometry: geo, userTrace: pts)
        XCTAssertEqual(f.userSegments.count, 1, "perfect y nil se dibujan igual")
    }

    func testUnTramoFueraDeToleranciaParteLaCurva() throws {
        let l = try layout()
        let a = trace(l, from: 0,    to: 1900, step: 100, level: nil)
        let b = trace(l, from: 2000, to: 3900, step: 100, level: .miss)
        let c = trace(l, from: 4000, to: 5900, step: 100, level: nil)
        let f = l.frame(atTick: 2500, geometry: geo, userTrace: a + b + c)

        XCTAssertEqual(f.userSegments.map(\.level), [nil, .miss, nil])
        // los tramos comparten el punto de corte (sin hueco visible)
        XCTAssertEqual(f.userSegments[0].points.last, f.userSegments[1].points.first)
        XCTAssertEqual(f.userSegments[1].points.last, f.userSegments[2].points.first)
    }

    func testLaCurvaDeUsuarioUsaElMismoEjeQueElFantasma() throws {
        let l = try layout()
        let lo = l.positionRange.lowerBound
        let hi = l.positionRange.upperBound
        let pts = [
            TracePoint(tick: 800, position: lo, level: nil),
            TracePoint(tick: 900, position: hi, level: nil),
        ]
        let f = l.frame(atTick: 850, geometry: geo, userTrace: pts)
        let ys = f.userSegments.flatMap { $0.points.map(\.y) }
        XCTAssertEqual(ys.min()!, geo.curveBand.bottom, accuracy: 1e-6, "posición mínima → borde inferior de la banda")
        XCTAssertEqual(ys.max()!, geo.curveBand.top, accuracy: 1e-6, "posición máxima → borde superior")
    }

    func testUnMismoValorDePosicionDaLaMismaYSeaCualSeaElTick() throws {
        let l = try layout()
        let p = (l.positionRange.lowerBound + l.positionRange.upperBound) / 2
        let f = l.frame(atTick: 1000, geometry: geo, userTrace: [
            TracePoint(tick: 500, position: p), TracePoint(tick: 600, position: p),
            TracePoint(tick: 700, position: p),
        ])
        let ys = Set(f.userSegments.flatMap { $0.points.map { ($0.y * 1e6).rounded() } })
        XCTAssertEqual(ys.count, 1, "la Y solo depende de la posición, no del tick")
    }

    // MARK: - marcas de click teñidas

    func testLasMarcasSeClasificanPorElDesfase() throws {
        let l = try layout()
        let tick = l.scratch.faderEvents.first { $0.state == .closed }!.t
        let f = l.frame(atTick: Double(tick), geometry: geo, clickHits: [
            ClickHit(patternTick: tick, offsetMs: 5),
            ClickHit(patternTick: tick, offsetMs: 45),
            ClickHit(patternTick: tick, offsetMs: -130),
        ])
        XCTAssertEqual(f.hitMarks.map(\.level), [.perfect, .good, .miss])
    }

    func testLaMarcaCaeEnLaCopiaMasCercanaAAhora() throws {
        let l = try layout()
        let L = Double(l.scratch.lengthTicks)
        let event = l.scratch.faderEvents.first!
        let pxPerTick = geo.pixelsPerTick(ppq: l.scratch.ppq)

        // "ahora" en la 3ª copia: la marca de ese click va a su instancia más
        // cercana a "ahora" y con el mismo mapeo tiempo→X que el resto.
        let now = 3 * L + L / 3
        let nearestCopy = ((now - Double(event.t)) / L).rounded()
        let expectedX = geo.playheadX
            + CGFloat(Double(event.t) + nearestCopy * L - now) * pxPerTick

        let f = l.frame(atTick: now, geometry: geo,
                        clickHits: [ClickHit(patternTick: event.t, offsetMs: 0)])
        XCTAssertEqual(f.hitMarks.count, 1)
        XCTAssertEqual(f.hitMarks[0].point.x, expectedX, accuracy: 1e-6)
        XCTAssertEqual(nearestCopy, 3, "la 3ª copia es la más cercana a 'ahora'")
        XCTAssertEqual(f.hitMarks[0].closes, event.state == .closed)
    }
}
