// SPDX-License-Identifier: GPL-3.0-only
import XCTest
@testable import XFTestKit

/// `RepoFiles`: localizar ficheros del repo desde un test subiendo hasta
/// `Package.swift`.
final class RepoFilesTests: XCTestCase {

    func testRootTieneElPackage() {
        let root = RepoFiles.root()
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: root.appendingPathComponent("Package.swift").path))
    }

    func testUrlYDataDeUnFicheroConocido() throws {
        // CLAUDE.md está en la raíz y siempre existe.
        let url = RepoFiles.url("CLAUDE.md")
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        let text = try RepoFiles.text("CLAUDE.md")
        XCTAssertTrue(text.contains("xFlare"))
    }

    func testFicheroInexistenteLanza() {
        XCTAssertThrowsError(try RepoFiles.data("no/existe/de/verdad.bin"))
    }
}
