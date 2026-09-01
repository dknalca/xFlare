// SPDX-License-Identifier: GPL-3.0-only
import XCTest
@testable import XFCapture
import XFPrimitives

/// B6.1 — protocolos de frontera `MotionSource` / `FaderSource`.
final class XFCaptureTests: XCTestCase {

    func testAPIVersion() {
        XCTAssertEqual(XFCapture.apiVersion, 1)
    }

    /// Una fuente de mentira minima para comprobar que el protocolo se puede
    /// conformar y usar sin hardware.
    final class FakeMotionSource: MotionSource {
        var connected = false
        var sample: MotionSample?
        var isConnected: Bool { connected }
        func start() throws { connected = true }
        func stop() { connected = false }
        func latest() -> MotionSample? { sample }
    }

    func testSePuedeConformarYUsarUnaFuente() throws {
        let src: MotionSource = FakeMotionSource()
        XCTAssertFalse(src.isConnected)
        try src.start()
        XCTAssertTrue(src.isConnected)
        XCTAssertNil(src.latest())
        (src as! FakeMotionSource).sample = MotionSample(hostTime: 1, position: 0.5,
                                                        velocity: 1, confidence: 1)
        XCTAssertEqual(src.latest()?.position, 0.5)
        src.stop()
        XCTAssertFalse(src.isConnected)
    }
}
