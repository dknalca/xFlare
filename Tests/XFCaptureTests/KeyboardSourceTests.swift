// SPDX-License-Identifier: GPL-3.0-only
import XCTest
@testable import XFCapture
import XFClock
import XFPrimitives

/// B6.2 — fuentes de teclado (modo sin mesa).
final class KeyboardSourceTests: XCTestCase {

    private let host = HostClock(numer: 1, denom: 1)   // 1 host tick = 1 ns

    private func ns(_ ms: Double) -> UInt64 { UInt64(ms * 1_000_000) }

    // MARK: - motion

    func testDiscoParadoSinTeclas() throws {
        let m = KeyboardMotionSource(host: host)
        try m.start()
        m.advance(toHostTime: HostClock.now() + ns(100))
        XCTAssertEqual(m.latest()?.velocity ?? -1, 0, accuracy: 1e-9)
    }

    func testFlechaAdelanteAceleraYAvanza() throws {
        let cfg = KeyboardMotionSource.Config(speed: 1.6, accel: 20)
        let m = KeyboardMotionSource(config: cfg, host: host)
        try m.start()
        let t0 = m.latest()!.hostTime

        m.press(.forward)
        m.advance(toHostTime: t0 + ns(200))     // 0,2 s a accel 20 -> alcanza el tope 1.6
        let v = m.latest()!.velocity
        XCTAssertEqual(v, 1.6, accuracy: 1e-6)
        XCTAssertGreaterThan(m.latest()!.position, 0)

        // soltar -> frena hacia 0
        m.release(.forward)
        m.advance(toHostTime: t0 + ns(400))
        XCTAssertEqual(m.latest()!.velocity, 0, accuracy: 1e-6)
    }

    func testFlechaAtrasVelocidadNegativa() throws {
        let m = KeyboardMotionSource(config: .init(speed: 1.0, accel: 50), host: host)
        try m.start()
        let t0 = m.latest()!.hostTime
        m.press(.back)
        m.advance(toHostTime: t0 + ns(100))
        XCTAssertLessThan(m.latest()!.velocity, 0)
        XCTAssertLessThan(m.latest()!.position, 0)
    }

    func testAmbasTeclasSeCancelan() throws {
        let m = KeyboardMotionSource(config: .init(speed: 1.0, accel: 50), host: host)
        try m.start()
        let t0 = m.latest()!.hostTime
        m.press(.forward); m.press(.back)
        m.advance(toHostTime: t0 + ns(100))
        XCTAssertEqual(m.latest()!.velocity, 0, accuracy: 1e-6)
    }

    func testBabyScratch_idaYVueltaVuelveCercaDelOrigen() throws {
        // adelante 100 ms, atrás 100 ms a la misma config -> posición ~ 0
        let m = KeyboardMotionSource(config: .init(speed: 2.0, accel: 60), host: host)
        try m.start()
        var t = m.latest()!.hostTime
        m.press(.forward)
        for _ in 0..<10 { t += ns(10); m.advance(toHostTime: t) }
        m.release(.forward); m.press(.back)
        for _ in 0..<20 { t += ns(10); m.advance(toHostTime: t) }
        m.release(.back); m.press(.forward)
        for _ in 0..<10 { t += ns(10); m.advance(toHostTime: t) }
        m.release(.forward)
        for _ in 0..<20 { t += ns(10); m.advance(toHostTime: t) }
        XCTAssertEqual(m.latest()!.position, 0, accuracy: 0.05)   // vuelve al origen
    }

    func testAdvanceNoRetrocede() throws {
        let m = KeyboardMotionSource(host: host)
        try m.start()
        let t0 = m.latest()!.hostTime
        m.press(.forward)
        m.advance(toHostTime: t0 + ns(100))
        let p = m.latest()!.position
        m.advance(toHostTime: t0 + ns(50))       // hacia atrás en el tiempo: ignorado
        XCTAssertEqual(m.latest()!.position, p)
    }

    // MARK: - fader

    func testFaderMomentaneo() throws {
        let f = KeyboardFaderSource()
        try f.start()
        XCTAssertNil(f.latest())
        f.keyDown(hostTime: 100)
        XCTAssertEqual(f.latest()?.isOpen, false)   // pulsado = cortado
        f.keyUp(hostTime: 200)
        XCTAssertEqual(f.latest()?.isOpen, true)    // suelto = abierto
        XCTAssertEqual(f.latest()?.hostTime, 200)
    }

    func testFaderIgnoraSinStart() {
        let f = KeyboardFaderSource()
        f.keyDown(hostTime: 1)
        XCTAssertNil(f.latest())
    }
}
