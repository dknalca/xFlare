// SPDX-License-Identifier: GPL-3.0-only
import XCTest
@testable import XFApp

/// B11.7 — Ajustes (clave/valor tipado).
final class AppSettingsTests: XCTestCase {

    func testRawVacioDaLosDefaults() {
        XCTAssertEqual(AppSettings(raw: [:]), .defaults)
    }

    func testIdaYVuelta() {
        var s = AppSettings.defaults
        s.hamster = true
        s.bufferFrames = 128
        s.metronomeEnabled = false
        s.toleranceScale = 1.5
        s.highContrast = true
        XCTAssertEqual(AppSettings(raw: s.raw), s)
    }

    func testValoresIlegiblesCaenAlDefault() {
        let s = AppSettings(raw: [
            "audio.bufferFrames": "999",          // no es 64 ni 128
            "scoring.toleranceScale": "no-num",
            "hamster": "quizas",
        ])
        XCTAssertEqual(s.bufferFrames, 64)
        XCTAssertEqual(s.toleranceScale, 1.0)
        XCTAssertFalse(s.hamster)
    }

    func testToleranciaSeRecortaAlRango() {
        XCTAssertEqual(AppSettings(raw: ["scoring.toleranceScale": "5.0"]).toleranceScale, 2.0)
        XCTAssertEqual(AppSettings(raw: ["scoring.toleranceScale": "0.1"]).toleranceScale, 0.5)
    }

    func testAceptaTrueYUnoComoBooleano() {
        XCTAssertTrue(AppSettings(raw: ["hamster": "true"]).hamster)
        XCTAssertTrue(AppSettings(raw: ["hamster": "1"]).hamster)
        XCTAssertFalse(AppSettings(raw: ["hamster": "0"]).hamster)
    }
}
