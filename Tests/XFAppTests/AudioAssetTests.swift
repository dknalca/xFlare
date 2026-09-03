// SPDX-License-Identifier: GPL-3.0-only
import XCTest
@testable import XFApp

/// `AudioAsset`: decodifica los audios de la práctica a mono float. Usa los
/// ficheros reales del repo (`Audio/`), resueltos por `RepoContentLoader`.
///
/// `Audio/` NO está en git (samples con copyright, CLAUDE.md §12): en una
/// máquina de dev con esa carpeta estos tests corren; en CI se **saltan**
/// (`XCTSkip`) en vez de fallar.
final class AudioAssetTests: XCTestCase {

    private let content = RepoContentLoader()

    /// Resuelve un audio del repo o salta el test si `Audio/` no está presente.
    private func requireAudio(_ relPath: String) throws -> URL {
        guard let url = content.url(relPath) else {
            throw XCTSkip("falta \(relPath) (Audio/ no está en git, CLAUDE.md §12)")
        }
        return url
    }

    func testDecodificaElSampleDeScratch() throws {
        let url = try requireAudio(AudioAsset.scratchRelPath)
        let pcm = try XCTUnwrap(AudioAsset.loadMono(url, sampleRate: 48_000))
        XCTAssertGreaterThan(pcm.count, 4_800, "al menos 0,1 s")
        XCTAssertGreaterThan(pcm.map { abs($0) }.max() ?? 0, 0.01, "no está en silencio")
        XCTAssertLessThanOrEqual(pcm.map { abs($0) }.max() ?? 0, 1.0)
    }

    func testDecodificaLaBaseInstrumental() throws {
        let url = try requireAudio(AudioAsset.instrumentalRelPath)
        let pcm = try XCTUnwrap(AudioAsset.loadMono(url, sampleRate: 48_000))
        XCTAssertGreaterThan(pcm.count, 48_000, "al menos 1 s de loop")
        XCTAssertGreaterThan(pcm.map { abs($0) }.max() ?? 0, 0.01)
    }

    func testReamuestreaALaFrecuenciaPedida() throws {
        let url = try requireAudio(AudioAsset.instrumentalRelPath)
        let at48 = try XCTUnwrap(AudioAsset.loadMono(url, sampleRate: 48_000))
        let at24 = try XCTUnwrap(AudioAsset.loadMono(url, sampleRate: 24_000))
        // la mitad de frecuencia -> ~la mitad de muestras para la misma duración
        XCTAssertEqual(Double(at24.count), Double(at48.count) / 2, accuracy: Double(at48.count) * 0.02)
    }

    func testRutaInexistenteDaNil() {
        XCTAssertNil(AudioAsset.loadMono("Audio/no-existe.wav", from: content))
    }

    /// `capScratch` recorta a `scratchMaxSeconds` y deja igual lo más corto: un
    /// sample largo se scratchea como el `Ahh`, no "se va todo".
    func testRecortaElSampleLargoALaVentanaDeScratch() {
        let sr = 48_000.0
        let cap = Int(AudioAsset.scratchMaxSeconds * sr)

        let corto = [Float](repeating: 0.2, count: 10_000)
        XCTAssertEqual(AudioAsset.capScratch(corto, sampleRate: sr).count, 10_000, "lo corto no se toca")

        let largo = [Float](repeating: 0.2, count: Int(sr) * 60)   // 60 s
        XCTAssertEqual(AudioAsset.capScratch(largo, sampleRate: sr).count, cap, "lo largo se recorta a la ventana")
    }
}
