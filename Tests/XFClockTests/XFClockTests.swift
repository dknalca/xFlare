// SPDX-License-Identifier: GPL-3.0-only
import XCTest
@testable import XFClock

// Andamiaje (B0.1): solo verifica que el modulo compila y enlaza.
final class XFClockTests: XCTestCase {
    func testScaffoldingLinks() {
        XCTAssertEqual(XFClock.scaffoldingVersion, 0)
    }
}
