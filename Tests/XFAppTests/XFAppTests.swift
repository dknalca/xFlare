// SPDX-License-Identifier: GPL-3.0-only
import XCTest
@testable import XFApp

// Andamiaje (B0.1): verifica que el target de la app compila y enlaza toda
// la cadena de dependencias (XFEngine, XFRender, XFDesign).
final class XFAppTests: XCTestCase {
    func testScaffoldingLinks() {
        XCTAssertEqual(XFApp.scaffoldingVersion, 0)
    }
}
