// SPDX-License-Identifier: GPL-3.0-only
import XCTest
@testable import XFApp

/// B11.8 — accesibilidad (`docs/UI_DESIGN.md` §4).
final class A11yTests: XCTestCase {

    func testAltoContrasteSubeGhostYEngrosaTrazos() {
        let std = A11y.Palette.active(highContrast: false)
        let hc = A11y.Palette.active(highContrast: true)
        XCTAssertEqual(std.ghostOpacity, 0.35)
        XCTAssertEqual(hc.ghostOpacity, 0.60, "ghost al 60 % en alto contraste")
        XCTAssertGreaterThan(hc.strokeWidth, std.strokeWidth)
        XCTAssertGreaterThan(hc.userStrokeWidth, std.userStrokeWidth)
    }

    func testDescripcionDeResultadosParaVoiceOver() {
        let s = ResultsSummary.build(
            score: 3840, maxScore: 4800, starCount: 2,
            starReasons: ["★★★ Solido: necesitas 95% (tienes 80%)."],
            diagnostics: ["Tu segundo click va 35 ms tarde."],
            isBestScore: true)
        let text = A11y.resultsDescription(s)
        XCTAssertTrue(text.contains("2 de 3 estrellas"))
        XCTAssertTrue(text.contains("80 por ciento"))
        XCTAssertTrue(text.contains("Tu mejor marca"))
        XCTAssertTrue(text.contains("Falta"))
        XCTAssertTrue(text.contains("Tu segundo click va 35 ms tarde."))
        XCTAssertFalse(text.contains("/"), "no lee la barra, dice 'de'")
    }

    func testAnuncioDeLaAutopistaComoRegionEnVivo() {
        XCTAssertEqual(A11y.highwayLiveAnnouncement(bar: 2, ofBars: 4, accuracyPercent: 91),
                       "Compás 2 de 4. 91 por ciento.")
        XCTAssertEqual(A11y.highwayLiveAnnouncement(bar: 1, ofBars: 4, accuracyPercent: nil),
                       "Compás 1 de 4.")
    }

    func testTodasLasEstrellasEncendidasNoDiceFalta() {
        let s = ResultsSummary.build(score: 10, maxScore: 10, starCount: 3,
                                     starReasons: [], diagnostics: [], isBestScore: false)
        XCTAssertFalse(A11y.resultsDescription(s).contains("Falta"))
    }
}
