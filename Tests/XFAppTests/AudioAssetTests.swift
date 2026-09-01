// SPDX-License-Identifier: GPL-3.0-only
import XCTest
@testable import XFApp

/// `AudioAsset`: decodifica los audios de la práctica a mono float. Usa los
/// ficheros reales del repo (`Audio/`), resueltos por `RepoContentLoader`.
final class AudioAssetTests: XCTestCase {

    private let content = RepoContentLoader()

    func testDecodificaElSampleDeScratch() throws {
        let url = try XCTUnwrap(content.url(AudioAsset.scratchRelPath),
                                "falta \(AudioAsset.scratchRelPath) en el repo")
        let pcm = try XCTUnwrap(AudioAsset.loadMono(url, sampleRate: 48_000))
        XCTAssertGreaterThan(pcm.count, 4_800, "al menos 0,1 s")
        XCTAssertGreaterThan(pcm.map { abs($0) }.max() ?? 0, 0.01, "no está en silencio")
        XCTAssertLessThanOrEqual(pcm.map { abs($0) }.max() ?? 0, 1.0)
    }

    func testDecodificaLaBaseInstrumental() throws {
        let url = try XCTUnwrap(content.url(AudioAsset.instrumentalRelPath),
                                "falta \(AudioAsset.instrumentalRelPath) en el repo")
        let pcm = try XCTUnwrap(AudioAsset.loadMono(url, sampleRate: 48_000))
        XCTAssertGreaterThan(pcm.count, 48_000, "al menos 1 s de loop")
        XCTAssertGreaterThan(pcm.map { abs($0) }.max() ?? 0, 0.01)
    }

    func testReamuestreaALaFrecuenciaPedida() throws {
        let url = try XCTUnwrap(content.url(AudioAsset.instrumentalRelPath))
        let at48 = try XCTUnwrap(AudioAsset.loadMono(url, sampleRate: 48_000))
        let at24 = try XCTUnwrap(AudioAsset.loadMono(url, sampleRate: 24_000))
        // la mitad de frecuencia -> ~la mitad de muestras para la misma duración
        XCTAssertEqual(Double(at24.count), Double(at48.count) / 2, accuracy: Double(at48.count) * 0.02)
    }

    func testRutaInexistenteDaNil() {
        XCTAssertNil(AudioAsset.loadMono("Audio/no-existe.wav", from: content))
    }
}
