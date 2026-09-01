// SPDX-License-Identifier: GPL-3.0-only
import XCTest
import Darwin
@testable import XFCapture
import XFClock
import XFPrimitives

/// B6.4b — captura del crossfader por retorno de audio con tono piloto (ADR-021).
///
/// Se valida con **piloto sintético**: un seno a 19,5 kHz modulado en amplitud
/// por la "posición" del crossfader (como el `--selfcheck` del spike).
final class AudioReturnFaderSourceTests: XCTestCase {

    private let sr = 48_000.0
    private let host = HostClock(numer: 1, denom: 1)   // 1 tick = 1 ns

    /// PCM estéreo 16 bits: piloto a 19,5 kHz con amplitud `openAmp` mientras
    /// `open` y `closedAmp` cuando no, durante `seconds`. `noise` añade ruido.
    private func pilot(open: Bool, seconds: Double, openAmp: Double = 0.35,
                       closedAmp: Double = 0.02, noise: Double = 0) -> [Int16] {
        let n = Int(seconds * sr)
        let w = 2.0 * Double.pi * 19_500.0 / sr
        var out = [Int16](repeating: 0, count: n * 2)
        var seed: UInt64 = 0x2545F4914F6CDD1D
        let amp = open ? openAmp : closedAmp
        for i in 0..<n {
            var s = amp * sin(w * Double(i))
            if noise > 0 {
                seed = seed &* 6364136223846793005 &+ 1
                s += noise * (Double(seed >> 40) / Double(1 << 24) - 0.5)
            }
            let v = Int16(max(-32767, min(32767, (s * 32767).rounded())))
            out[i * 2 + 0] = v
            out[i * 2 + 1] = v
        }
        return out
    }

    private func source(cutIn: Float = 0.15, hysteresis: Float = 0.08,
                        hamster: Bool = false) -> AudioReturnFaderSource {
        AudioReturnFaderSource(
            config: .init(pilotHz: 19_500, sampleRate: sr, hopFrames: 64,
                          cutIn: cutIn, hysteresis: hysteresis, hamster: hamster,
                          referenceLevel: 0.35),
            host: host)
    }

    // MARK: -

    func testDetectaAperturaYCierre() throws {
        let s = source()
        try s.start()
        var t: UInt64 = 1_000_000

        s.submit(pilot(open: true, seconds: 0.05), hostTime: t); t += 50_000_000
        XCTAssertEqual(s.latest()?.isOpen, true, "con piloto fuerte, abierto")

        s.submit(pilot(open: false, seconds: 0.05), hostTime: t); t += 50_000_000
        XCTAssertEqual(s.latest()?.isOpen, false, "sin piloto, cortado")

        s.submit(pilot(open: true, seconds: 0.05), hostTime: t)
        XCTAssertEqual(s.latest()?.isOpen, true, "vuelve a abrir")
    }

    func testFaderQuietoAbiertoNoGeneraEventosFantasma() throws {
        let s = source()
        try s.start()
        var transitions = 0
        var prev: Bool?
        // 1 s de piloto abierto con ruido -> ~750 hops
        let out = s.submit(pilot(open: true, seconds: 1.0, noise: 0.02), hostTime: 5_000_000)
        for sample in out {
            if let p = prev, p != sample.isOpen { transitions += 1 }
            prev = sample.isOpen
        }
        XCTAssertLessThanOrEqual(transitions, 1, "solo la transición inicial a abierto")
        XCTAssertEqual(s.latest()?.isOpen, true)
    }

    func testCadaHopProduceUnaMuestra() throws {
        let s = source()
        try s.start()
        // 64*10 frames -> 10 hops exactos
        let out = s.submit(pilot(open: true, seconds: Double(64 * 10) / sr), hostTime: 0)
        XCTAssertEqual(out.count, 10)
    }

    func testMuestrasSueltasSeGuardanEntreSubmits() throws {
        let s = source()
        try s.start()
        // 100 frames: 1 hop (64) + 36 sobrantes
        let a = s.submit(pilot(open: true, seconds: 100.0 / sr), hostTime: 0)
        XCTAssertEqual(a.count, 1)
        // otros 100: 36 + 100 = 136 -> 2 hops
        let b = s.submit(pilot(open: true, seconds: 100.0 / sr), hostTime: 0)
        XCTAssertEqual(b.count, 2)
    }

    func testHostTimeDeLosHops() throws {
        let s = source()
        try s.start()
        let out = s.submit(pilot(open: true, seconds: Double(64 * 4) / sr), hostTime: 1_000_000)
        // hop k -> 1_000_000 + k*64/48000 s en ns
        for (k, sample) in out.enumerated() {
            let expected = 1_000_000 + UInt64((Double(k * 64) / sr * 1e9).rounded())
            XCTAssertEqual(sample.hostTime, expected, accuracy: 2)
        }
    }

    func testHamsterInvierteElCriterio() throws {
        let s = source(hamster: true)
        try s.start()
        // con hamster, "abierto" es la zona de piloto BAJO
        s.submit(pilot(open: false, seconds: 0.05), hostTime: 0)
        XCTAssertEqual(s.latest()?.isOpen, true, "piloto bajo + hamster -> abierto")
        s.submit(pilot(open: true, seconds: 0.05), hostTime: 100_000_000)
        XCTAssertEqual(s.latest()?.isOpen, false)
    }

    func testCalibrarAjustaElNivelDeReferencia() throws {
        let s = source()
        try s.start()
        // referencia demasiado baja al principio: un piloto medio ya "satura" a 1
        s.calibrate(openLevel: 0.35)
        s.submit(pilot(open: true, seconds: 0.05, openAmp: 0.35), hostTime: 0)
        XCTAssertEqual(s.pilotLevel, 1.0, accuracy: 0.1)
        XCTAssertEqual(s.latest()?.isOpen, true)
    }

    func testSinArrancarIgnora() {
        let s = source()
        XCTAssertTrue(s.submit(pilot(open: true, seconds: 0.05), hostTime: 0).isEmpty)
        XCTAssertNil(s.latest())
    }

    func testStopYReArranque() throws {
        let s = source()
        try s.start()
        s.submit(pilot(open: true, seconds: 0.05), hostTime: 0)
        s.stop()
        XCTAssertFalse(s.isConnected)
        try s.start()
        XCTAssertNil(s.latest(), "el re-arranque limpia el estado")
    }
}
