// SPDX-License-Identifier: GPL-3.0-only
import XCTest
@testable import XFDesign

// Andamiaje (B0.1): solo verifica que el modulo compila y enlaza.
final class XFDesignTests: XCTestCase {
    func testScaffoldingLinks() {
        XCTAssertEqual(XFDesign.scaffoldingVersion, 0)
    }
}
