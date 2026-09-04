// SPDX-License-Identifier: GPL-3.0-only

import XCTest
@testable import XFApp

final class TransientDetectorTests: XCTestCase {

    private let sr = 48_000.0

    /// Silencio -> ningún onset.
    func testSilencioNoDaOnsets() {
        let pcm = [Float](repeating: 0, count: Int(sr))   // 1 s de ceros
        XCTAssertTrue(TransientDetector.onsets(pcm, sampleRate: sr).isEmpty)
    }

    /// Audio demasiado corto -> vacío, sin reventar.
    func testAudioCortoDaVacio() {
        let pcm = [Float](repeating: 0.5, count: 100)
        XCTAssertTrue(TransientDetector.onsets(pcm, sampleRate: sr).isEmpty)
    }

    /// Tres ráfagas en instantes conocidos -> tres onsets, cada uno cerca de su
    /// instante (tolerancia ~15 ms).
    func testDetectaRafagasEnSusInstantes() {
        var pcm = [Float](repeating: 0, count: Int(sr * 2))   // 2 s
        let hits = [0.30, 0.90, 1.55]
        for t in hits { addBurst(&pcm, atSeconds: t, lengthMs: 40, freq: 440) }

        let onsets = TransientDetector.onsets(pcm, sampleRate: sr)
        XCTAssertEqual(onsets.count, hits.count, "onsets: \(onsets)")
        for (got, want) in zip(onsets.sorted(), hits) {
            XCTAssertEqual(got, want, accuracy: 0.015)
        }
    }

    /// Más sensibilidad no puede dar MENOS onsets que menos sensibilidad.
    func testSensibilidadEsMonotona() {
        var pcm = [Float](repeating: 0, count: Int(sr * 2))
        for t in stride(from: 0.2, to: 1.9, by: 0.25) {
            addBurst(&pcm, atSeconds: t, lengthMs: 30, freq: 300, amp: 0.2)
        }
        let low = TransientDetector.onsets(pcm, sampleRate: sr, sensitivity: 0.6).count
        let high = TransientDetector.onsets(pcm, sampleRate: sr, sensitivity: 1.8).count
        XCTAssertGreaterThanOrEqual(high, low)
    }

    /// Dos ataques MUY juntos (< 40 ms) se colapsan en uno (separación mínima).
    func testAtaquesMuyJuntosSeColapsan() {
        var pcm = [Float](repeating: 0, count: Int(sr))
        addBurst(&pcm, atSeconds: 0.50, lengthMs: 10, freq: 500)
        addBurst(&pcm, atSeconds: 0.52, lengthMs: 10, freq: 500)   // +20 ms
        XCTAssertEqual(TransientDetector.onsets(pcm, sampleRate: sr).count, 1)
    }

    // MARK: - util

    private func addBurst(_ pcm: inout [Float], atSeconds t: Double,
                          lengthMs: Double, freq: Double, amp: Float = 0.6) {
        let start = Int(t * sr)
        let n = Int(lengthMs / 1000 * sr)
        guard start >= 0, start + n < pcm.count else { return }
        for i in 0..<n {
            // envolvente con ataque instantáneo y caída, para que sea un onset claro
            let env = Float(exp(-Double(i) / (0.25 * Double(n))))
            pcm[start + i] += amp * env * Float(sin(2 * .pi * freq * Double(i) / sr))
        }
    }
}
