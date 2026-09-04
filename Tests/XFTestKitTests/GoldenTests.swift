// SPDX-License-Identifier: GPL-3.0-only
import XCTest
@testable import XFTestKit

/// `Golden`: la comparación de goldens tolerante a la arquitectura (ADR-028).
/// Se usa en todos los golden tests del proyecto pero no tenía tests propios.
final class GoldenTests: XCTestCase {

    func testRound4RedondeaA4Decimales() {
        XCTAssertEqual(Golden.round4(1.23456789), 1.2346, accuracy: 1e-12)
        XCTAssertEqual(Golden.round4(-1.23456789), -1.2346, accuracy: 1e-12)
        XCTAssertEqual(Golden.round4(0), 0)
        XCTAssertEqual(Golden.round4(2.5), 2.5, accuracy: 1e-12, "lo que ya cabe en 4 dp no cambia")
        // idempotente y simétrico (lo que importa para que un golden sea estable)
        let x = 3.14159265358979
        XCTAssertEqual(Golden.round4(Golden.round4(x)), Golden.round4(x), accuracy: 1e-12)
        XCTAssertEqual(Golden.round4(-x), -Golden.round4(x), accuracy: 1e-12)
    }

    func testApproxEqual() {
        XCTAssertTrue(Golden.approxEqual(1.0, 1.0 + 5e-10))
        XCTAssertFalse(Golden.approxEqual(1.0, 1.0 + 5e-9))
        XCTAssertTrue(Golden.approxEqual(0.0, -0.0))
        XCTAssertTrue(Golden.approxEqual(.infinity, .infinity))
        XCTAssertFalse(Golden.approxEqual(.infinity, -.infinity))
        // NaN nunca es aproximadamente igual a nada, ni a otro NaN
        XCTAssertFalse(Golden.approxEqual(.nan, .nan))
        XCTAssertFalse(Golden.approxEqual(.nan, 1.0))
    }

    func testFirstMismatch() {
        XCTAssertNil(Golden.firstMismatch([1, 2, 3], [1, 2, 3 + 1e-10]))
        XCTAssertEqual(Golden.firstMismatch([1, 2, 3], [1, 2.5, 3]), 1)
        // longitudes distintas -> el primer índice que "sobra"
        XCTAssertEqual(Golden.firstMismatch([1, 2], [1, 2, 3]), 2)
        XCTAssertEqual(Golden.firstMismatch([], []), nil)
    }

    func testCustomTolerance() {
        XCTAssertTrue(Golden.approxEqual(1.0, 1.01, tolerance: 0.1))
        XCTAssertNil(Golden.firstMismatch([1.0], [1.05], tolerance: 0.1))
    }
}
