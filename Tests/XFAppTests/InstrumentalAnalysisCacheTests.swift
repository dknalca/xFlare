// SPDX-License-Identifier: GPL-3.0-only
import XCTest
@testable import XFApp

/// Fase 2 — caché de pre-análisis de instrumentales.
final class InstrumentalAnalysisCacheTests: XCTestCase {

    private func tempFile(bytes: Int = 4096) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("xf-analysis-\(UUID().uuidString).wav")
        try Data(count: bytes).write(to: url)
        return url
    }

    private let result = TempoAnalyzer.Result(bpm: 92.5, phaseFrames: 1234,
                                              isShortLoop: false, beats: 480)

    func testCachedAnalysisRoundTripCodable() throws {
        let c = CachedAnalysis(result: result, fileBytes: 4096, mtime: 1000, sampleRate: 48_000)
        let data = try JSONEncoder().encode(c)
        XCTAssertEqual(try JSONDecoder().decode(CachedAnalysis.self, from: data), c)
    }

    func testFreshCuandoElFicheroNoHaCambiado() throws {
        let url = try tempFile()
        defer { try? FileManager.default.removeItem(at: url) }
        let c = CachedAnalysis.make(result, path: url.path, sampleRate: 48_000)
        XCTAssertTrue(c.isFresh(for: url.path, sampleRate: 48_000))
        XCTAssertEqual(c.result, result)
        XCTAssertEqual(c.fileBytes, 4096)
    }

    func testNoFreshSiCambiaTamano_SampleRateOFaltaElFichero() throws {
        let url = try tempFile()
        let c = CachedAnalysis.make(result, path: url.path, sampleRate: 48_000)

        // otra sample rate -> el análisis no vale
        XCTAssertFalse(c.isFresh(for: url.path, sampleRate: 44_100))

        // el fichero crece -> no vale
        try Data(count: 8192).write(to: url)
        XCTAssertFalse(c.isFresh(for: url.path, sampleRate: 48_000))

        // el fichero desaparece -> no vale
        try FileManager.default.removeItem(at: url)
        XCTAssertFalse(c.isFresh(for: url.path, sampleRate: 48_000))
    }

    func testElCachePersisteYSeRecarga() throws {
        let url = try tempFile()
        defer { try? FileManager.default.removeItem(at: url) }
        let store = FileManager.default.temporaryDirectory
            .appendingPathComponent("xf-cache-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: store) }

        let c1 = InstrumentalAnalysisCache(fileURL: store)
        // sin nada, no hay resultado
        XCTAssertNil(c1.result(for: url.path, sampleRate: 48_000))

        // simula un análisis terminado escribiendo el JSON a mano
        let entry = CachedAnalysis.make(result, path: url.path, sampleRate: 48_000)
        try JSONEncoder().encode([url.path: entry]).write(to: store)

        // otra instancia lo recarga
        let c2 = InstrumentalAnalysisCache(fileURL: store)
        XCTAssertEqual(c2.result(for: url.path, sampleRate: 48_000), result)

        // forget lo quita y reescribe
        c2.forget(url.path)
        XCTAssertNil(c2.result(for: url.path, sampleRate: 48_000))
        XCTAssertNil(InstrumentalAnalysisCache(fileURL: store).result(for: url.path, sampleRate: 48_000))
    }
}
