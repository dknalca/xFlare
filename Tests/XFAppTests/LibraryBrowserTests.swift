// SPDX-License-Identifier: GPL-3.0-only
import XCTest
@testable import XFApp

/// B11.6 — navegador de la librería.
final class LibraryBrowserTests: XCTestCase {

    private func e(_ id: String, name: String, family: String, level: Int,
                   unlocked: Bool = true) -> LibraryEntry {
        LibraryEntry(scratchId: id, name: name, family: family, level: level,
                     technique: family, clickCount: 2, lengthTicks: 1920, isUnlocked: unlocked)
    }

    private var browser: LibraryBrowser {
        LibraryBrowser(entries: [
            e("baby", name: "Baby Scratch", family: "Baby", level: 1),
            e("flare-2c", name: "2-Click Flare", family: "Flare", level: 4),
            e("flare-1c", name: "1-Click Flare", family: "Flare", level: 3, unlocked: false),
            e("crab", name: "Crab", family: "Crab", level: 6, unlocked: false),
        ])
    }

    func testNivelesYFamiliasEnOrden() {
        XCTAssertEqual(browser.levels, [1, 3, 4, 6])
        XCTAssertEqual(browser.families, ["Baby", "Crab", "Flare"])
    }

    func testFiltroPorFamilia() {
        XCTAssertEqual(browser.filtered(family: "Flare").map(\.scratchId).sorted(),
                       ["flare-1c", "flare-2c"])
    }

    func testBusquedaIgnoraMayusculasYAcentos() {
        XCTAssertEqual(browser.filtered(query: "FLARE").count, 2)
        XCTAssertEqual(browser.filtered(query: "crab").map(\.scratchId), ["crab"])
        XCTAssertEqual(browser.filtered(query: "").count, 4, "query vacía no filtra")
    }

    func testSoloDesbloqueados() {
        XCTAssertEqual(browser.filtered(onlyUnlocked: true).map(\.scratchId).sorted(),
                       ["baby", "flare-2c"])
    }

    func testAgrupadoPorNivelRespetaLosOtrosFiltros() {
        let groups = browser.groupedByLevel(family: "Flare")
        XCTAssertEqual(groups.map(\.level), [3, 4])
        XCTAssertEqual(groups[0].entries.map(\.scratchId), ["flare-1c"])
    }

    func testFiltrosCombinados() {
        let r = browser.filtered(query: "flare", level: 4, family: "Flare", onlyUnlocked: true)
        XCTAssertEqual(r.map(\.scratchId), ["flare-2c"])
    }
}
