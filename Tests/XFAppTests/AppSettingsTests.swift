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
        s.username = "dj test"
        s.hamster = true
        s.bufferFrames = 256
        s.metronomeEnabled = false
        s.toleranceScale = 1.5
        s.highContrast = true
        s.lastScratchSamplePath = "/Users/dj/Samples/mi ahhh.wav"
        XCTAssertEqual(AppSettings(raw: s.raw), s)
    }

    func testBibliotecaDeSamplesYAjustesDeVideo() {
        var s = AppSettings.defaults
        s.sampleLibrary = ["/a/uno.wav", "/b/dos.wav", "/a/uno.wav", ""]   // con duplicado y vacío
        s.videoFps = 60
        s.videoLongSide = 2400
        let round = AppSettings(raw: s.raw)
        XCTAssertEqual(round.sampleLibrary, ["/a/uno.wav", "/b/dos.wav"], "dedup + sin vacíos")
        XCTAssertEqual(round.videoFps, 60)
        XCTAssertEqual(round.videoLongSide, 2400)

        // valores fuera de las opciones -> al default
        let bad = AppSettings(raw: ["video.fps": "45", "video.longSide": "999"])
        XCTAssertEqual(bad.videoFps, 30)
        XCTAssertEqual(bad.videoLongSide, 1600)
    }

    func testAjustesDebugDelPlatoIdaYVueltaYAcotados() {
        var s = AppSettings.defaults
        s.platterGlideMs = 2.0
        s.platterSpeedGate = 0.05
        s.platterFriction = 3.2
        s.trackpadSensitivity = 1.4
        let round = AppSettings(raw: s.raw)
        XCTAssertEqual(round.platterGlideMs, 2.0, accuracy: 1e-9)
        XCTAssertEqual(round.platterSpeedGate, 0.05, accuracy: 1e-9)
        XCTAssertEqual(round.platterFriction, 3.2, accuracy: 1e-9)
        XCTAssertEqual(round.trackpadSensitivity, 1.4, accuracy: 1e-9)

        // fuera de rango -> se acotan
        let ext = AppSettings(raw: [
            "debug.platterGlideMs": "999", "debug.platterSpeedGate": "-1",
            "debug.platterFriction": "0.01", "debug.trackpadSensitivity": "50",
        ])
        XCTAssertEqual(ext.platterGlideMs, 12.0)
        XCTAssertEqual(ext.platterSpeedGate, 0.0)
        XCTAssertEqual(ext.platterFriction, 0.3)
        XCTAssertEqual(ext.trackpadSensitivity, 2.0)
    }

    func testValoresIlegiblesCaenAlDefault() {
        let s = AppSettings(raw: [
            "audio.bufferFrames": "999",          // no esta en bufferOptions
            "scoring.toleranceScale": "no-num",
            "hamster": "quizas",
        ])
        XCTAssertEqual(s.bufferFrames, AppSettings.defaults.bufferFrames)
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
