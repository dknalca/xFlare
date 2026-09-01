// SPDX-License-Identifier: GPL-3.0-only
import XCTest
import Darwin   // sin/M_PI
import CXFTimecode

/// B5.2/B5.3/B5.4 — wrapper `xf_timecoder` sobre xwax en modo relativo.
///
/// Se prueba con **señales sintéticas de cuadratura** (dos portadoras senoidales
/// desfasadas 90°). Eso valida justo lo que usa el modo relativo (ADR-004/005):
/// velocidad por frecuencia de portadora y dirección por la fase entre canales.
/// El bitstream LFSR (posición absoluta) no se usa y no se sintetiza.
final class CXFTimecodeTests: XCTestCase {

    private let sr = 48_000.0

    /// Genera PCM estéreo 16 bits: portadora a `carrierHz`, con el canal
    /// "secundario" (izquierdo) desfasado `secondaryPhaseDeg` grados.
    private func signal(carrierHz: Double, secondaryPhaseDeg: Double,
                        seconds: Double, amplitude: Double = 10_000) -> [Int16] {
        let frames = Int(seconds * sr)
        var out = [Int16](repeating: 0, count: frames * 2)
        let w = 2.0 * Double.pi * carrierHz / sr
        let ph2 = secondaryPhaseDeg * Double.pi / 180.0
        for i in 0..<frames {
            let prim = amplitude * sin(w * Double(i))
            let sec  = amplitude * sin(w * Double(i) + ph2)
            out[i * 2 + 0] = clampI16(sec)
            out[i * 2 + 1] = clampI16(prim)
        }
        return out
    }

    private func clampI16(_ x: Double) -> Int16 {
        let r = x.rounded()
        if r >= 32767 { return 32767 }
        if r <= -32767 { return -32767 }
        return Int16(r)
    }

    private func feed(_ tc: OpaquePointer, _ pcm: [Int16], chunk: Int = 4096) {
        let frames = pcm.count / 2
        pcm.withUnsafeBufferPointer { buf in
            var off = 0
            while off < frames {
                let n = min(chunk, frames - off)
                xf_timecoder_submit(tc, buf.baseAddress! + off * 2, n)
                off += n
            }
        }
    }

    // MARK: -

    func testVersionYFormatoInvalido() {
        XCTAssertEqual(xf_timecode_scaffolding_version(), 1)
        XCTAssertNil(xf_timecoder_create("formato-que-no-existe", 48_000))
        XCTAssertNil(xf_timecoder_create("serato_2a", 0))
        let tc = xf_timecoder_create("serato_2a", 48_000)
        XCTAssertNotNil(tc)
        xf_timecoder_destroy(tc)
    }

    /// serato_2a tiene `resolution = 1000` → a 1000 Hz la velocidad ≈ 1.0.
    func testVelocidadSigueLaFrecuenciaDePortadora() {
        let tc = xf_timecoder_create("serato_2a", 48_000)!
        defer { xf_timecoder_destroy(tc) }
        feed(tc, signal(carrierHz: 1000, secondaryPhaseDeg: 90, seconds: 2.0))
        let v1 = abs(xf_timecoder_velocity(tc))
        XCTAssertEqual(v1, 1.0, accuracy: 0.35, "1000 Hz → ~1.0×, dio \(v1)")

        let tc2 = xf_timecoder_create("serato_2a", 48_000)!
        defer { xf_timecoder_destroy(tc2) }
        feed(tc2, signal(carrierHz: 1500, secondaryPhaseDeg: 90, seconds: 2.0))
        let v2 = abs(xf_timecoder_velocity(tc2))
        XCTAssertEqual(v2, 1.5, accuracy: 0.5, "1500 Hz → ~1.5×, dio \(v2)")
        XCTAssertGreaterThan(v2, v1, "más frecuencia → más velocidad")
    }

    /// B5.3 — señal invertida (cuadratura al revés) → dirección opuesta.
    func testSenalInvertidaDaDireccionOpuesta() {
        let a = xf_timecoder_create("serato_2a", 48_000)!
        defer { xf_timecoder_destroy(a) }
        feed(a, signal(carrierHz: 1000, secondaryPhaseDeg: 90, seconds: 2.0))
        let vA = xf_timecoder_velocity(a)
        let fA = xf_timecoder_forwards(a)

        let b = xf_timecoder_create("serato_2a", 48_000)!
        defer { xf_timecoder_destroy(b) }
        feed(b, signal(carrierHz: 1000, secondaryPhaseDeg: -90, seconds: 2.0))
        let vB = xf_timecoder_velocity(b)
        let fB = xf_timecoder_forwards(b)

        XCTAssertGreaterThan(abs(vA), 0.4)
        XCTAssertGreaterThan(abs(vB), 0.4)
        XCTAssertEqual(vA.sign == .minus, vB.sign != .minus, "velocidades de signo opuesto")
        XCTAssertNotEqual(fA, fB, "el flag de dirección se invierte")
        XCTAssertEqual(abs(vA), abs(vB), accuracy: 0.4, "misma magnitud")
    }

    /// B5.3 — hamster / reverse (ADR-008): el flag invierte el signo.
    func testHamsterInvierteElSigno() {
        let normal = xf_timecoder_create("serato_2a", 48_000)!
        defer { xf_timecoder_destroy(normal) }
        feed(normal, signal(carrierHz: 1000, secondaryPhaseDeg: 90, seconds: 2.0))
        let vNormal = xf_timecoder_velocity(normal)

        let ham = xf_timecoder_create("serato_2a", 48_000)!
        defer { xf_timecoder_destroy(ham) }
        xf_timecoder_set_reversed(ham, true)
        feed(ham, signal(carrierHz: 1000, secondaryPhaseDeg: 90, seconds: 2.0))
        let vHam = xf_timecoder_velocity(ham)

        XCTAssertGreaterThan(abs(vNormal), 0.4)
        XCTAssertGreaterThan(abs(vHam), 0.4)
        XCTAssertEqual(vNormal.sign == .minus, vHam.sign != .minus, "hamster invierte el signo")
    }

    /// B5.4 — al levantar la aguja (silencio) no se cuelga y la confianza cae.
    func testSilencioNoCuelgaYBajaLaConfianza() {
        let tc = xf_timecoder_create("serato_2a", 48_000)!
        defer { xf_timecoder_destroy(tc) }
        feed(tc, signal(carrierHz: 1000, secondaryPhaseDeg: 90, seconds: 1.5))
        XCTAssertGreaterThan(xf_timecoder_confidence(tc), 0.5, "con señal, confianza alta")

        feed(tc, [Int16](repeating: 0, count: Int(1.5 * sr) * 2))   // silencio
        XCTAssertLessThan(xf_timecoder_confidence(tc), 0.2, "sin señal, confianza baja")
        XCTAssertLessThan(abs(xf_timecoder_velocity(tc)), 0.6, "la velocidad decae hacia 0")
        // y un submit vacío tampoco revienta
        xf_timecoder_submit(tc, [], 0)
    }

    /// B5.4 — ruido blanco: no engancha, no revienta, no dispara la velocidad.
    func testRuidoNoEnganchaNiRevienta() {
        let tc = xf_timecoder_create("serato_2a", 48_000)!
        defer { xf_timecoder_destroy(tc) }
        var state: UInt64 = 0x1234_5678
        var pcm = [Int16](repeating: 0, count: Int(sr) * 2)
        for i in pcm.indices {
            state = state &* 6364136223846793005 &+ 1
            pcm[i] = Int16(truncatingIfNeeded: Int(state >> 40) - 2048) &* 4
        }
        feed(tc, pcm)
        XCTAssertLessThan(abs(xf_timecoder_velocity(tc)), 4.0, "sin blow-up de velocidad")
    }

    func testPosicionIntegraYSeResetea() {
        let tc = xf_timecoder_create("serato_2a", 48_000)!
        defer { xf_timecoder_destroy(tc) }
        feed(tc, signal(carrierHz: 1000, secondaryPhaseDeg: 90, seconds: 2.0))
        XCTAssertGreaterThan(abs(xf_timecoder_position(tc)), 0.3, "la posición avanza")
        xf_timecoder_reset_position(tc)
        XCTAssertEqual(xf_timecoder_position(tc), 0.0)
    }
}
