// SPDX-License-Identifier: GPL-3.0-only
import XCTest
@testable import XFTestKit
import XFPrimitives
import XFCapture

/// `FakeMotionSource` / `FakeFaderSource`: implementaciones de mentira de los
/// protocolos de `XFCapture` para tests sin hardware.
final class FakeSourceTests: XCTestCase {

    private struct BoomError: Error {}

    private func motion(_ v: Double) -> MotionSample {
        MotionSample(hostTime: 0, position: 0, velocity: v, confidence: 1)
    }
    private func fader(_ open: Bool) -> FaderSample {
        FaderSample(hostTime: 0, value: open ? 1 : 0, isOpen: open)
    }

    func testCicloDeVidaYConexion() throws {
        let s = FakeMotionSource(fixed: motion(0))
        XCTAssertFalse(s.isConnected)
        XCTAssertNil(s.latest(), "antes de start() no hay muestra")

        try s.start()
        XCTAssertTrue(s.isConnected)
        XCTAssertEqual(s.startCount, 1)
        XCTAssertEqual(s.latest()?.velocity, 0)

        s.stop()
        XCTAssertFalse(s.isConnected)
        XCTAssertEqual(s.stopCount, 1)
        XCTAssertNil(s.latest())
    }

    func testStartErrorSePropaga() {
        let s = FakeFaderSource()
        s.startError = BoomError()
        XCTAssertThrowsError(try s.start())
        XCTAssertEqual(s.startCount, 0, "un start() fallido no cuenta como conectado")
        XCTAssertFalse(s.isConnected)
    }

    func testScriptAvanzaYRepiteLaUltima() throws {
        let s = FakeMotionSource(script: [motion(1), motion(2), motion(3)])
        try s.start()
        XCTAssertEqual(s.latest()?.velocity, 1)
        XCTAssertEqual(s.latest()?.velocity, 2)
        XCTAssertEqual(s.latest()?.velocity, 3)
        XCTAssertEqual(s.latest()?.velocity, 3, "al acabar el script repite la última")
        s.stop()
        try s.start()
        XCTAssertEqual(s.latest()?.velocity, 1, "stop() rebobina el script")
    }

    func testValorFijoReasignable() throws {
        let s = FakeFaderSource(fixed: fader(true))
        try s.start()
        XCTAssertEqual(s.latest()?.isOpen, true)
        s.fixed = fader(false)
        XCTAssertEqual(s.latest()?.isOpen, false)
    }

    /// Se pueden usar allí donde se pide el protocolo, sin conocer el tipo real.
    func testSirvenComoElProtocolo() throws {
        let m: MotionSource = FakeMotionSource(fixed: motion(0.5))
        let f: FaderSource = FakeFaderSource(fixed: fader(true))
        try m.start(); try f.start()
        XCTAssertEqual(m.latest()?.velocity, 0.5)
        XCTAssertEqual(f.latest()?.isOpen, true)
    }
}
