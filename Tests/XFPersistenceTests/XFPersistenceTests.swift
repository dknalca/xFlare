// SPDX-License-Identifier: GPL-3.0-only
import XCTest
@testable import XFPersistence

// Andamiaje (B0.1): verifica que el modulo compila y enlaza (incluida GRDB
// como dependencia transitiva del target).
final class XFPersistenceTests: XCTestCase {
    func testScaffoldingLinks() {
        XCTAssertEqual(XFPersistence.scaffoldingVersion, 0)
    }
}
