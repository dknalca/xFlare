// SPDX-License-Identifier: GPL-3.0-only
import XCTest
import Darwin
@testable import XFCapture
import XFClock
import XFPrimitives

/// B6.4 — fallback de ultimo recurso: seguidor de envolvente del retorno.
final class AudioEnvelopeFaderSourceTests: XCTestCase {

    private let sr = 48_000.0
    private let host = HostClock(numer: 1, denom: 1)

    /// PCM estereo: ruido rosa-ish a amplitud `amp` durante `seconds`.
    private func audio(amp: Double, seconds: Double) -> [Int16] {
        let n = Int(seconds * sr)
        var out = [Int16](repeating: 0, count: n * 2)
        var seed: UInt64 = 0x9E3779B97F4A7C15
        for i in 0..<n {
            seed = seed &* 6364136223846793005 &+ 1
            let s = amp * (Double(seed >> 40) / Double(1 << 24) - 0.5) * 2
            let v = Int16(max(-32767, min(32767, (s * 32767).rounded())))
            out[i * 2 + 0] = v; out[i * 2 + 1] = v
        }
        return out
    }

    private func source(cutIn: Float = 0.2, hysteresis: Float = 0.1) -> AudioEnvelopeFaderSource {
        AudioEnvelopeFaderSource(
            config: .init(sampleRate: sr, hopFrames: 256, cutIn: cutIn, hysteresis: hysteresis,
                          referenceLevel: 0.3),
            host: host)
    }

    func testAudioFuerteAbreYSilencioCierra() throws {
        let s = source()
        try s.start()
        s.submit(audio(amp: 0.4, seconds: 0.1), hostTime: 0)
        XCTAssertEqual(s.latest()?.isOpen, true, "hay señal -> abierto")
        s.submit(audio(amp: 0.005, seconds: 0.1), hostTime: 100_000_000)
        XCTAssertEqual(s.latest()?.isOpen, false, "silencio -> cortado")
        s.submit(audio(amp: 0.4, seconds: 0.1), hostTime: 200_000_000)
        XCTAssertEqual(s.latest()?.isOpen, true)
    }

    func testSenalEstableNoGeneraEventosFantasma() throws {
        let s = source()
        try s.start()
        var transitions = 0, prev: Bool?
        let out = s.submit(audio(amp: 0.35, seconds: 1.0), hostTime: 0)
        for sample in out {
            if let p = prev, p != sample.isOpen { transitions += 1 }
            prev = sample.isOpen
        }
        XCTAssertLessThanOrEqual(transitions, 1)
        XCTAssertEqual(s.latest()?.isOpen, true)
    }

    func testCadaHopUnaMuestraYSobrantesEntreSubmits() throws {
        let s = source()   // hop = 256
        try s.start()
        XCTAssertEqual(s.submit(audio(amp: 0.3, seconds: Double(256 * 5) / sr), hostTime: 0).count, 5)
        let a = s.submit(audio(amp: 0.3, seconds: 400.0 / sr), hostTime: 0)   // 400 -> 1 hop + 144
        XCTAssertEqual(a.count, 1)
        let b = s.submit(audio(amp: 0.3, seconds: 400.0 / sr), hostTime: 0)   // 144+400 = 544 -> 2 hops
        XCTAssertEqual(b.count, 2)
    }

    func testCalibrarEscalaLaEnvolvente() throws {
        let s = source()
        try s.start()
        // ruido uniforme +-0.4 -> RMS ~ 0.231. Calibrando a 0.2, el valor satura a 1.
        s.calibrate(openLevel: 0.2)
        s.submit(audio(amp: 0.4, seconds: 0.05), hostTime: 0)
        XCTAssertGreaterThan(s.envelope, 0.9)
    }

    func testSinArrancarIgnora() {
        let s = source()
        XCTAssertTrue(s.submit(audio(amp: 0.4, seconds: 0.05), hostTime: 0).isEmpty)
        XCTAssertNil(s.latest())
    }
}
