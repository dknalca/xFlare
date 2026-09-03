// SPDX-License-Identifier: GPL-3.0-only
import XCTest
import Darwin
import CXFAudioCore

/// `xf_eq` — EQ de 3 bandas (Lo/Mid/Hi) del sample de scratch. Se mide la
/// respuesta en frecuencia con Goertzel (no se confía en el oído), y se
/// comprueba que en plano es transparente y que mover los mandos no mete clicks.
final class XFEqTests: XCTestCase {

    private let sr = 48_000.0

    private func sine(_ hz: Double, n: Int, amp: Float = 0.5) -> [Float] {
        let w = 2.0 * Double.pi * hz / sr
        return (0..<n).map { amp * Float(sin(w * Double($0))) }
    }

    private func rms(_ x: ArraySlice<Float>) -> Double {
        guard !x.isEmpty else { return 0 }
        let s = x.reduce(0.0) { $0 + Double($1) * Double($1) }
        return (s / Double(x.count)).squareRoot()
    }
    private func rms(_ x: [Float]) -> Double { rms(x[...]) }

    private func goertzel(_ x: [Float], _ hz: Double) -> Double {
        let w = 2.0 * Double.pi * hz / sr
        let c = 2.0 * cos(w)
        var s1 = 0.0, s2 = 0.0
        for v in x { let s0 = Double(v) + c * s1 - s2; s2 = s1; s1 = s0 }
        let power = s1 * s1 + s2 * s2 - c * s1 * s2
        return 2.0 * max(0, power).squareRoot() / Double(x.count)
    }

    /// Pasa `input` por una EQ con esas ganancias y devuelve la salida (se
    /// descartan los primeros 512 por el transitorio del filtro).
    private func filtered(_ input: [Float], low: Float, mid: Float, high: Float) -> [Float] {
        var eq = xf_eq()
        xf_eq_init(&eq, sr)
        xf_eq_set_gains_db(&eq, low, mid, high)
        var buf = input
        buf.withUnsafeMutableBufferPointer {
            xf_eq_process_block(&eq, $0.baseAddress, Int32($0.count))
        }
        return Array(buf[512...])
    }

    // MARK: - plano = transparente

    func testPlanoNoTocaLaSenal() {
        let x = sine(1000, n: 4096)
        var eq = xf_eq()
        xf_eq_init(&eq, sr)                    // arranca en bypass
        var buf = x
        buf.withUnsafeMutableBufferPointer {
            xf_eq_process_block(&eq, $0.baseAddress, Int32($0.count))
        }
        XCTAssertEqual(buf, x, "en plano la EQ no modifica ni un bit")
    }

    func testGananciasCeroSonPlano() {
        let x = sine(1000, n: 4096)
        let y = filtered(x, low: 0, mid: 0, high: 0)
        XCTAssertEqual(rms(y), rms(Array(x[512...])), accuracy: 1e-6)
    }

    // MARK: - cada banda mueve SU zona del espectro

    func testGravesSubenLosBajosYCasiNoTocanLosAgudos() {
        let lo = sine(120, n: 8192), hi = sine(9000, n: 8192)
        let loBoost = goertzel(filtered(lo, low: 12, mid: 0, high: 0), 120)
                    / goertzel(Array(lo[512...]), 120)
        let hiBleed = goertzel(filtered(hi, low: 12, mid: 0, high: 0), 9000)
                    / goertzel(Array(hi[512...]), 9000)
        XCTAssertGreaterThan(loBoost, 2.0, "Lo +12 dB sube los graves > 6 dB")
        XCTAssertEqual(hiBleed, 1.0, accuracy: 0.15, "y casi no toca los agudos")
    }

    func testAgudosSubenLosAltosYCasiNoTocanLosBajos() {
        let lo = sine(120, n: 8192), hi = sine(9000, n: 8192)
        let hiBoost = goertzel(filtered(hi, low: 0, mid: 0, high: 12), 9000)
                    / goertzel(Array(hi[512...]), 9000)
        let loBleed = goertzel(filtered(lo, low: 0, mid: 0, high: 12), 120)
                    / goertzel(Array(lo[512...]), 120)
        XCTAssertGreaterThan(hiBoost, 2.0, "Hi +12 dB sube los agudos > 6 dB")
        XCTAssertEqual(loBleed, 1.0, accuracy: 0.15, "y casi no toca los graves")
    }

    func testMediosBajanLaCampanaDe1kHz() {
        let mid = sine(1000, n: 8192)
        let cut = goertzel(filtered(mid, low: 0, mid: -18, high: 0), 1000)
                / goertzel(Array(mid[512...]), 1000)
        XCTAssertLessThan(cut, 0.4, "Mid -18 dB atenúa 1 kHz a menos de la mitad")
    }

    // MARK: - robustez

    func testDbSeAcotaYNoRevienta() {
        // pide ganancias fuera de rango + ruido fuerte: nada de NaN/inf
        var eq = xf_eq()
        xf_eq_init(&eq, sr)
        xf_eq_set_gains_db(&eq, 999, -999, 999)
        var rng: UInt64 = 1
        var buf = (0..<8192).map { _ -> Float in
            rng = rng &* 6364136223846793005 &+ 1
            return Float(Int32(truncatingIfNeeded: rng >> 33)) / Float(1 << 30)
        }
        buf.withUnsafeMutableBufferPointer {
            xf_eq_process_block(&eq, $0.baseAddress, Int32($0.count))
        }
        XCTAssertTrue(buf.allSatisfy { $0.isFinite }, "sin NaN/inf con dB extremos")
    }

    func testCambiarLosMandosNoMeteClick() {
        // Como en la vida real: bloques de 64 frames. A mitad de camino se suben
        // los graves de golpe (+12 dB). La rampa de ~20 ms reparte el cambio, así
        // que ningún salto entre muestras contiguas pega un "tic".
        var eq = xf_eq()
        xf_eq_init(&eq, sr)
        let block = 64
        let nBlocks = 200
        let x = sine(180, n: block * nBlocks)
        var out = x

        out.withUnsafeMutableBufferPointer { dst in
            for b in 0..<nBlocks {
                if b == 100 { xf_eq_set_gains_db(&eq, 12, 0, -8) }
                xf_eq_process_block(&eq, dst.baseAddress! + b * block, Int32(block))
            }
        }

        // salto natural del seno entre muestras contiguas (referencia)
        let natural = x.indices.dropFirst().map { abs(x[$0] - x[$0 - 1]) }.max() ?? 0
        // mayor salto en la salida alrededor del cambio de mandos
        var maxJump: Float = 0
        for i in (block * 98)..<(block * 130) { maxJump = max(maxJump, abs(out[i] - out[i - 1])) }
        XCTAssertLessThan(maxJump, natural * 3 + 0.02,
                          "sin discontinuidad audible al mover el mando (salto \(maxJump))")
    }
}
