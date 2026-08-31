// SPDX-License-Identifier: GPL-3.0-only
import XCTest
import CXFTimecode
import XFTestKit

// Andamiaje (B0.1): verifica el cableado CXFTimecode -> CXFAudioCore y que
// XFTestKit se enlaza. La logica del wrapper de xwax llega en el bloque B5.
final class CXFTimecodeTests: XCTestCase {
    func testScaffoldingLinks() {
        XCTAssertEqual(xf_timecode_scaffolding_version(), 0)
        XCTAssertEqual(XFTestKit.scaffoldingVersion, 0)
    }
}
