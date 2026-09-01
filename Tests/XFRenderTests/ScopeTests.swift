// SPDX-License-Identifier: GPL-3.0-only
import XCTest
import CoreGraphics
@testable import XFRender

/// B7.5 — scope circular del plato (`ScopeLayout`). Puro, sin SpriteKit.
final class ScopeTests: XCTestCase {

    private let geo = ScopeGeometry(size: CGSize(width: 200, height: 200), padding: 20)
    private let layout = ScopeLayout()

    private func dist(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
        hypot(a.x - b.x, a.y - b.y)
    }

    func testGeometriaDerivada() {
        XCTAssertEqual(geo.center, CGPoint(x: 100, y: 100))
        XCTAssertEqual(geo.referenceRadius, 80)   // 200/2 - 20
    }

    func testSenalLimpiaPoneElPuntoEnLaCircunferencia() {
        let f = layout.figure(readings: [ScopeReading(position: 0.1, velocity: 1, confidence: 1.0)],
                              geometry: geo)
        XCTAssertEqual(dist(f.dot, f.center), f.referenceRadius, accuracy: 1e-6)
        XCTAssertEqual(f.dotRadiusFraction, 1, accuracy: 1e-9)
        XCTAssertFalse(f.isDegraded)
    }

    func testSenalSuciaHundeElPuntoYMarcaDegradado() {
        let f = layout.figure(readings: [ScopeReading(position: 0.1, velocity: 0.2, confidence: 0.15)],
                              geometry: geo)
        XCTAssertEqual(dist(f.dot, f.center), f.referenceRadius * 0.15, accuracy: 1e-6)
        XCTAssertTrue(f.isDegraded)
    }

    func testLaPosicionMapeaAlAngulo() {
        // position 0 -> ángulo 0 -> (centro.x + R, centro.y)
        let a = layout.figure(readings: [ScopeReading(position: 0, velocity: 1, confidence: 1)], geometry: geo)
        XCTAssertEqual(a.dot.x, geo.center.x + geo.referenceRadius, accuracy: 1e-6)
        XCTAssertEqual(a.dot.y, geo.center.y, accuracy: 1e-6)

        // position 0.25 -> ángulo π/2 -> (centro.x, centro.y + R)
        let b = layout.figure(readings: [ScopeReading(position: 0.25, velocity: 1, confidence: 1)], geometry: geo)
        XCTAssertEqual(b.dot.x, geo.center.x, accuracy: 1e-6)
        XCTAssertEqual(b.dot.y, geo.center.y + geo.referenceRadius, accuracy: 1e-6)
    }

    func testElAnguloSeNormalizaAUnaVuelta() {
        // 2.25 vueltas -> mismo ángulo que 0.25
        let f = layout.figure(readings: [ScopeReading(position: 2.25, velocity: 1, confidence: 1)], geometry: geo)
        XCTAssertEqual(f.angleRadians, .pi / 2, accuracy: 1e-6)
    }

    func testElRastroTieneUnPuntoPorLecturaYAcabaEnElDot() {
        let readings = (0..<10).map {
            ScopeReading(position: Double($0) * 0.05, velocity: 1, confidence: 1)
        }
        let f = layout.figure(readings: readings, geometry: geo)
        XCTAssertEqual(f.trail.count, 10)
        XCTAssertEqual(f.trail.last!, f.dot)
    }

    func testHaciaAtrasElRastroGiraAlReves() {
        let fwd = layout.figure(readings: [
            ScopeReading(position: 0.00, velocity: 1, confidence: 1),
            ScopeReading(position: 0.10, velocity: 1, confidence: 1),
        ], geometry: geo)
        let rev = layout.figure(readings: [
            ScopeReading(position: 0.00, velocity: -1, confidence: 1),
            ScopeReading(position: -0.10, velocity: -1, confidence: 1),
        ], geometry: geo)
        // adelante: y sube (sin de un ángulo creciente); atrás: y baja
        XCTAssertGreaterThan(fwd.trail.last!.y, fwd.trail.first!.y)
        XCTAssertLessThan(rev.trail.last!.y, rev.trail.first!.y)
    }

    func testMasVelocidadSeparaMasLosPuntosDelRastro() {
        let lento = layout.figure(readings: [
            ScopeReading(position: 0.00, velocity: 0.2, confidence: 1),
            ScopeReading(position: 0.01, velocity: 0.2, confidence: 1),
        ], geometry: geo)
        let rapido = layout.figure(readings: [
            ScopeReading(position: 0.00, velocity: 2.0, confidence: 1),
            ScopeReading(position: 0.20, velocity: 2.0, confidence: 1),
        ], geometry: geo)
        XCTAssertLessThan(dist(lento.trail[0], lento.trail[1]),
                          dist(rapido.trail[0], rapido.trail[1]))
    }

    func testSinLecturasNoRevienta() {
        let f = layout.figure(readings: [], geometry: geo)
        XCTAssertEqual(f.dot, f.center)
        XCTAssertTrue(f.isDegraded)
        XCTAssertTrue(f.trail.isEmpty)
    }

    func testConfianzaSeRecorta() {
        let f = layout.figure(readings: [ScopeReading(position: 0, velocity: 1, confidence: 1.9)], geometry: geo)
        XCTAssertEqual(f.dotRadiusFraction, 1, accuracy: 1e-9, "no pasa de la circunferencia")
    }
}
