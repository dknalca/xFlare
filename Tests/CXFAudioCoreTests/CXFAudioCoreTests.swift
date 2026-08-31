// SPDX-License-Identifier: GPL-3.0-only
import XCTest
import CXFAudioCore

// Andamiaje (B0.1): solo verifica que el modulo C compila, genera modulemap
// y se enlaza desde Swift. La logica RT llega en el bloque B4.
final class CXFAudioCoreTests: XCTestCase {
    func testScaffoldingLinks() {
        XCTAssertEqual(xf_audio_core_scaffolding_version(), 0)
    }
}
