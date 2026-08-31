// SPDX-License-Identifier: GPL-3.0-only
import XCTest
@testable import XFNotation
import XFTestKit

// Andamiaje (B0.1): solo verifica que el modulo compila y enlaza con XFTestKit.
final class XFNotationTests: XCTestCase {
    func testScaffoldingLinks() {
        XCTAssertEqual(XFNotation.scaffoldingVersion, 0)
        XCTAssertEqual(XFTestKit.scaffoldingVersion, 0)
    }
}
