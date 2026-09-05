// SPDX-License-Identifier: GPL-3.0-only
import XCTest
@testable import XFApp

/// B11.7 — Ajustes (clave/valor tipado).
final class AppSettingsTests: XCTestCase {

    func testRawVacioDaLosDefaults() {
        XCTAssertEqual(AppSettings(raw: [:]), .defaults)
    }

    /// F.85 — la mesa activa por defecto es la Rane 72 (único hardware de
    /// referencia, `CLAUDE.md`), y sobrevive a un ida y vuelta por `raw`
    /// (antes vivía solo en memoria en `AppModel`, se perdía en cada
    /// reinicio de la app).
    func testActiveProfileIdPorDefectoEsRane72YSobreviveAlIdaYVuelta() {
        XCTAssertEqual(AppSettings.defaults.activeProfileId, "rane-seventy-two")
        var s = AppSettings.defaults
        s.activeProfileId = "generic-midi"
        XCTAssertEqual(AppSettings(raw: s.raw).activeProfileId, "generic-midi")
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

    /// F.80: el autor pidió más opciones de buffer "por arriba y por abajo"
    /// en el asistente de calibración -- el suelo baja a 32 (ya lo tenía
    /// arriba, hasta 2048). init(raw:) no debe recortarlo al default.
    func testBufferDe32EsUnaOpcionValidaNoSeRecortaAlDefault() {
        var s = AppSettings.defaults
        s.bufferFrames = 32
        XCTAssertEqual(AppSettings(raw: s.raw).bufferFrames, 32)
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

    func testLibreriaDeInstrumentalesIdaYVuelta() {
        var s = AppSettings.defaults
        s.instrumentalLibrary = ["/x/beat90.wav", "/y/loop.aif", "/x/beat90.wav", ""]  // dup + vacío
        let round = AppSettings(raw: s.raw)
        XCTAssertEqual(round.instrumentalLibrary, ["/x/beat90.wav", "/y/loop.aif"], "dedup + sin vacíos")
        XCTAssertEqual(AppSettings(raw: [:]).instrumentalLibrary, [], "por defecto vacía")
    }

    func testSlotsDeSampleSiempreSonCuatroYSobrevivenAlIdaYVuelta() {
        // por defecto: 4 slots vacíos
        XCTAssertEqual(AppSettings(raw: [:]).sampleSlots, ["", "", "", ""])

        // el init normaliza a 4: rellena con "" y conserva los huecos intermedios
        var s = AppSettings.defaults
        s.sampleSlots = ["/a/kick.wav", "", "/c/vocal.wav"]
        let round = AppSettings(raw: s.raw)
        XCTAssertEqual(round.sampleSlots, ["/a/kick.wav", "", "/c/vocal.wav", ""],
                       "ida y vuelta rellena hasta 4 y preserva el hueco intermedio")

        // si vienen más de 4, se recorta
        var big = AppSettings.defaults
        big.sampleSlots = ["1", "2", "3", "4", "5", "6"]
        XCTAssertEqual(AppSettings(raw: big.raw).sampleSlots, ["1", "2", "3", "4"])
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

    /// F.75 (ADR-079) — ancla de posición del scratch (timecode real).
    func testAnclaDeScratchIdaYVueltaYAcotada() {
        var s = AppSettings.defaults
        s.scratchSeekTrimMs = 80.0
        s.scratchSeekMaxTrim = 0.04
        let round = AppSettings(raw: s.raw)
        XCTAssertEqual(round.scratchSeekTrimMs, 80.0, accuracy: 1e-9)
        XCTAssertEqual(round.scratchSeekMaxTrim, 0.04, accuracy: 1e-9)

        let ext = AppSettings(raw: [
            "debug.scratchSeekTrimMs": "99999", "debug.scratchSeekMaxTrim": "-1",
        ])
        XCTAssertEqual(ext.scratchSeekTrimMs, 1000.0)
        XCTAssertEqual(ext.scratchSeekMaxTrim, 0.0)
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

    // MARK: - F.68: canal de salida separado para la instrumental

    func testInstrumentalOutputChannelPorDefectoEsCombinado() {
        XCTAssertEqual(AppSettings.defaults.instrumentalOutputChannel, 0)
    }

    func testInstrumentalOutputChannelIdaYVuelta() {
        var s = AppSettings.defaults
        s.instrumentalOutputChannel = 3
        XCTAssertEqual(AppSettings(raw: s.raw).instrumentalOutputChannel, 3)
    }

    func testInstrumentalOutputChannelNegativoSeAcotaACero() {
        // el recorte vive en el init (como `outputChannel`/`inputChannel`), no
        // en un `didSet` -- se prueba pasando por `raw:`, que sí pasa por él.
        let s = AppSettings(raw: ["audio.instrumentalOutputChannel": "-5"])
        XCTAssertEqual(s.instrumentalOutputChannel, 0)
    }
}
