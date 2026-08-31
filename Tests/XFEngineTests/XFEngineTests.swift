// SPDX-License-Identifier: GPL-3.0-only
import XCTest
@testable import XFEngine
import XFTestKit

// Andamiaje (B0.1): verifica que el modulo que orquesta la capa 1 compila y
// enlaza con todas sus dependencias.
final class XFEngineTests: XCTestCase {
    func testScaffoldingLinks() {
        XCTAssertEqual(XFEngine.scaffoldingVersion, 0)
        XCTAssertEqual(XFTestKit.scaffoldingVersion, 0)
    }
}
