// SPDX-License-Identifier: GPL-3.0-only
import XCTest
@testable import XFApp

/// Envolvente del sample de scratch para `WaveformStripView`.
final class WaveformEnvelopeTests: XCTestCase {

    func testNormalizaA0y1() {
        let pcm = (0..<10_000).map { Float(sin(Double($0) * 0.05)) * 0.3 }
        let env = WaveformEnvelope.build(pcm, buckets: 200)
        XCTAssertEqual(env.count, 200)
        XCTAssertEqual(env.max() ?? 0, 1.0, accuracy: 1e-4, "el pico se normaliza a 1")
        XCTAssertGreaterThanOrEqual(env.min() ?? -1, 0)
    }

    func testSilencioDaEnvolventePlana() {
        let env = WaveformEnvelope.build([Float](repeating: 0, count: 5_000), buckets: 100)
        XCTAssertEqual(env.count, 100)
        XCTAssertEqual(env.max() ?? 1, 0)
    }

    func testSigueLaForma() {
        // primera mitad fuerte, segunda mitad floja
        var pcm = [Float](repeating: 0.8, count: 4_000)
        pcm += [Float](repeating: 0.1, count: 4_000)
        let env = WaveformEnvelope.build(pcm, buckets: 80)
        XCTAssertGreaterThan(env[10], 0.9)
        XCTAssertLessThan(env[70], 0.2)
    }

    func testPCMVacioNoRevienta() {
        XCTAssertTrue(WaveformEnvelope.build([], buckets: 100).isEmpty)
    }
}
