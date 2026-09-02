// SPDX-License-Identifier: GPL-3.0-only
import XCTest
@testable import XFApp

/// Detección de tempo/fase de la instrumental (para cuadrar la rejilla a los
/// golpes). Se prueba con un tren de clicks sintético de tempo conocido.
final class TempoAnalyzerTests: XCTestCase {

    /// `seconds` de clicks a `bpm`: cada negra, una ráfaga corta que decae.
    private func clickTrack(bpm: Double, seconds: Double, sr: Double = 48_000,
                            phaseFrames: Int = 0) -> [Float] {
        let n = Int(seconds * sr)
        var out = [Float](repeating: 0, count: n)
        let period = 60.0 / bpm * sr
        var t = Double(phaseFrames)
        while Int(t) < n {
            let start = Int(t)
            for i in 0..<300 {
                let idx = start + i
                if idx >= n { break }
                out[idx] += Float(exp(-Double(i) / 60.0) * sin(Double(i) * 0.6))
            }
            t += period
        }
        return out
    }

    func testDetectaUnTempoConocido() throws {
        let sr = 48_000.0
        for bpm in [90.0, 120.0, 140.0] {
            let pcm = clickTrack(bpm: bpm, seconds: 6, sr: sr)
            let r = try XCTUnwrap(TempoAnalyzer.analyze(pcm, sampleRate: sr))
            XCTAssertEqual(r.bpm, bpm, accuracy: 3.0, "bpm \(bpm) -> \(r.bpm)")
        }
    }

    func testEncuentraLaFaseDelPrimerGolpe() throws {
        let sr = 48_000.0
        let phase = 7_000
        let pcm = clickTrack(bpm: 120, seconds: 6, sr: sr, phaseFrames: phase)
        let r = try XCTUnwrap(TempoAnalyzer.analyze(pcm, sampleRate: sr))
        let period = Int(60.0 / r.bpm * sr)
        let err = [0, period, -period].map { abs(r.phaseFrames - phase + $0) }.min() ?? .max
        XCTAssertLessThan(err, 700, "fase \(r.phaseFrames) vs \(phase)")
    }

    func testCuadraElBucleAUnNumeroEnteroDeNegras() throws {
        let sr = 48_000.0
        let pcm = clickTrack(bpm: 120, seconds: 4.0, sr: sr)   // 8 negras exactas
        let r = try XCTUnwrap(TempoAnalyzer.analyze(pcm, sampleRate: sr))
        XCTAssertEqual(r.beatsInLoop, 8)
        XCTAssertEqual(Double(r.beatsInLoop) * 60.0 / 4.0, r.bpm, accuracy: 0.01)
    }

    func testAudioMuyCortoDevuelveNil() {
        XCTAssertNil(TempoAnalyzer.analyze([Float](repeating: 0, count: 1000), sampleRate: 48_000))
        XCTAssertNil(TempoAnalyzer.analyze([Float](repeating: 0, count: 200_000), sampleRate: 48_000),
                     "silencio: sin onsets -> nil")
    }
}
