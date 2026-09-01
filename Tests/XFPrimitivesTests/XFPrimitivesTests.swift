// SPDX-License-Identifier: GPL-3.0-only
import XCTest
@testable import XFPrimitives

final class XFPrimitivesTests: XCTestCase {

    func testAPIVersion() {
        XCTAssertEqual(XFPrimitives.apiVersion, 1)
    }

    func testMotionSampleEsValueTypeYEquatable() {
        let a = MotionSample(hostTime: 1_000, position: 2.5, velocity: 1.0, confidence: 0.9)
        let b = MotionSample(hostTime: 1_000, position: 2.5, velocity: 1.0, confidence: 0.9)
        let c = MotionSample(hostTime: 1_000, position: 2.5, velocity: -1.0, confidence: 0.9)
        XCTAssertEqual(a, b)
        XCTAssertNotEqual(a, c)
        XCTAssertEqual(a.position, 2.5)
        XCTAssertLessThan(c.velocity, 0)   // hacia atras
    }

    func testFaderSample() {
        let s = FaderSample(hostTime: 42, value: 0.03, isOpen: false)
        XCTAssertEqual(s.hostTime, 42)
        XCTAssertFalse(s.isOpen)
        XCTAssertEqual(FaderSample(hostTime: 42, value: 0.03, isOpen: false), s)
    }

    func testSendable() {
        // Compila => conforman Sendable. Comprobacion en tiempo de compilacion.
        func requireSendable<T: Sendable>(_ t: T) {}
        requireSendable(MotionSample(hostTime: 0, position: 0, velocity: 0, confidence: 1))
        requireSendable(FaderSample(hostTime: 0, value: 0, isOpen: true))
    }
}
