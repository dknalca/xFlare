// SPDX-License-Identifier: GPL-3.0-only
import XCTest
@testable import XFApp

/// Onda con color por frecuencia (tipo Serato): 3 bandas -> RGB por tramo.
final class WaveformColoredTests: XCTestCase {

    private func tone(_ hz: Double, seconds: Double = 2, sr: Double = 48_000) -> [Float] {
        let n = Int(seconds * sr)
        return (0..<n).map { Float(0.5 * sin(2 * Double.pi * hz * Double($0) / sr)) }
    }

    func testTonoGraveTiraANaranjaYAgudoAAzul() {
        let sr = 48_000.0
        let low = WaveformColored.build(tone(60, sr: sr), sampleRate: sr, buckets: 200)
        let high = WaveformColored.build(tone(9000, sr: sr), sampleRate: sr, buckets: 200)
        XCTAssertFalse(low.isEmpty)

        // media del color por tramo
        func mean(_ d: WaveformColored.Data) -> SIMD3<Float> {
            d.colors.reduce(.zero, +) / Float(max(1, d.colors.count))
        }
        let lc = mean(low), hc = mean(high)
        // grave: canal rojo domina sobre el azul; agudo: al reves
        XCTAssertGreaterThan(lc.x, lc.z, "60 Hz -> mas calido que azul")
        XCTAssertGreaterThan(hc.z, hc.x, "9 kHz -> mas azul que calido")
    }

    func testAmplitudNormalizadaYMismaLongitud() {
        let d = WaveformColored.build(tone(440), sampleRate: 48_000, buckets: 300)
        XCTAssertEqual(d.levels.count, 300)
        XCTAssertEqual(d.colors.count, 300)
        XCTAssertEqual(d.levels.max() ?? 0, 1.0, accuracy: 0.001)
    }

    func testAudioVacioNoRevienta() {
        let d = WaveformColored.build([], sampleRate: 48_000)
        XCTAssertTrue(d.isEmpty)
    }
}
