// SPDX-License-Identifier: GPL-3.0-only
import XCTest
@testable import XFCapture
import XFTestKit

// Andamiaje (B0.1): solo verifica que el modulo compila y enlaza con XFTestKit.
final class XFCaptureTests: XCTestCase {
    func testScaffoldingLinks() {
        XCTAssertEqual(XFCapture.scaffoldingVersion, 0)
        XCTAssertEqual(XFTestKit.scaffoldingVersion, 0)
    }
}
