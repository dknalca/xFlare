// SPDX-License-Identifier: GPL-3.0-only
import XCTest
@testable import XFClock

/// Comprobaciones del espacio de nombres y las constantes del dominio musical.
final class XFClockTests: XCTestCase {

    func testPPQEs480() {
        // ADR-016. Hay datos serializados con este valor; no se cambia sin ADR.
        XCTAssertEqual(XFClock.ppq, 480)
    }

    func testAPIVersionEsEstable() {
        XCTAssertEqual(XFClock.apiVersion, 1)
    }
}
