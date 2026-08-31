// SPDX-License-Identifier: GPL-3.0-only
import XCTest
@testable import XFProfiles

// Andamiaje (B0.1): solo verifica que el modulo compila y enlaza.
final class XFProfilesTests: XCTestCase {
    func testScaffoldingLinks() {
        XCTAssertEqual(XFProfiles.scaffoldingVersion, 0)
    }
}
