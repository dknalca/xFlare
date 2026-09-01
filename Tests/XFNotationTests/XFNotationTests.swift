// SPDX-License-Identifier: GPL-3.0-only
import XCTest
@testable import XFNotation

final class XFNotationTests: XCTestCase {

    func testAPIVersion() {
        XCTAssertEqual(XFNotation.apiVersion, 1)
    }

    func testCurvasValoresConocidos() {
        XCTAssertEqual(Curve.lin.value(0.5), 0.5, accuracy: 1e-12)
        XCTAssertEqual(Curve.bell.value(0.5), 0.5, accuracy: 1e-12)   // 0.25*(3-1)=0.5
        XCTAssertEqual(Curve.acc.value(0.5), 0.25, accuracy: 1e-12)
        XCTAssertEqual(Curve.dec.value(0.5), 0.75, accuracy: 1e-12)
        XCTAssertEqual(Curve.hold.value(0.5), 0.0, accuracy: 1e-12)
        // extremos
        XCTAssertEqual(Curve.bell.value(0.0), 0.0, accuracy: 1e-12)
        XCTAssertEqual(Curve.bell.value(1.0), 1.0, accuracy: 1e-12)
    }

    func testDivisionATicks() {
        XCTAssertEqual(Division("1/4")!.unitTicks(ppq: 480), 480)
        XCTAssertEqual(Division("1/8")!.unitTicks(ppq: 480), 240)
        XCTAssertEqual(Division("1/16")!.unitTicks(ppq: 480), 120)
        XCTAssertNil(Division("bad"))
        XCTAssertNil(Division("1/0"))
    }
}
