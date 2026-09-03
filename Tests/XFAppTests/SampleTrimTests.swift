// SPDX-License-Identifier: GPL-3.0-only
import XCTest
import Foundation
@testable import XFApp

/// `SampleTrim` (F.3) — detección del punto cero de un sample que trae el
/// usuario: dónde empieza el sonido y cuadre a cruce por cero.
final class SampleTrimTests: XCTestCase {

    private let sr = 48_000.0

    private func silence(_ n: Int) -> [Float] { [Float](repeating: 0, count: n) }

    private func sine(_ hz: Double, frames n: Int, amp: Float = 0.5,
                      phase: Double = 0) -> [Float] {
        (0..<n).map { i in
            amp * Float(sin(2 * .pi * hz * Double(i) / sr + phase))
        }
    }

    func testDetectaElAtaqueTrasSilencioInicial() {
        let lead = 12_000                          // 0,25 s de silencio
        let pcm = silence(lead) + sine(220, frames: 24_000)
        let start = SampleTrim.detectStart(pcm, sampleRate: sr)

        // cae cerca del ataque (con el retroceso de 8 ms, un poco antes), no en 0
        XCTAssertGreaterThan(start, lead - Int(sr * 0.012))
        XCTAssertLessThan(start, lead + Int(sr * 0.010))
        // y en un cruce por cero: |muestra| pequeña
        XCTAssertLessThan(abs(pcm[start]), 0.02)
    }

    func testTodoSilencioDejaLosExtremos() {
        let pcm = silence(20_000)
        XCTAssertEqual(SampleTrim.detectStart(pcm, sampleRate: sr), 0)
        XCTAssertEqual(SampleTrim.detectEnd(pcm, sampleRate: sr), pcm.count)
    }

    func testSiYaEmpiezaSonandoStartEsCero() {
        let pcm = sine(330, frames: 20_000)
        XCTAssertEqual(SampleTrim.detectStart(pcm, sampleRate: sr), 0)
    }

    func testTrimmedRecortaCabezaYColaYDevuelveElOffset() {
        let lead = 9_000, body = 30_000, tailN = 15_000
        let pcm = silence(lead) + sine(180, frames: body) + silence(tailN)
        let (out, startFrame) = SampleTrim.trimmed(pcm, sampleRate: sr)

        XCTAssertGreaterThan(startFrame, 0)
        XCTAssertLessThan(out.count, pcm.count)
        XCTAssertGreaterThan(out.count, Int(sr * 0.02))     // queda algo útil
        // los bordes del recorte, cerca de cero (no clickan al scratchear)
        XCTAssertLessThan(abs(out.first ?? 1), 0.03)
        XCTAssertLessThan(abs(out.last ?? 1), 0.03)
    }

    func testTrimmedNoTocaUnSampleYaLimpio() {
        let pcm = sine(300, frames: 40_000)
        let (out, startFrame) = SampleTrim.trimmed(pcm, sampleRate: sr)
        XCTAssertEqual(startFrame, 0)
        XCTAssertEqual(out.count, pcm.count)
    }

    func testEntradaDegeneradaNoRevienta() {
        // vacío / 1 muestra / 2 ceros: no revienta, no toca nada
        for pcm in [[Float](), [Float]([0.1]), [Float]([0, 0])] {
            XCTAssertEqual(SampleTrim.detectStart(pcm, sampleRate: sr), 0)
            let (out, off) = SampleTrim.trimmed(pcm, sampleRate: sr)
            XCTAssertEqual(out.count, pcm.count)
            XCTAssertEqual(off, 0)
        }

        // sr = 0 tampoco
        let some = sine(200, frames: 4_000)
        let (o0, s0) = SampleTrim.trimmed(some, sampleRate: 0)
        XCTAssertEqual(o0.count, some.count)
        XCTAssertEqual(s0, 0)

        // varios trozos raros: el resultado siempre es un subrango válido del original
        let cases = [
            silence(500) + sine(200, frames: 400) + silence(500),
            sine(120, frames: 100),
            silence(30_000),
            sine(200, frames: 5_000, amp: 0.001),               // por debajo del umbral
        ]
        for pcm in cases {
            let (out, off) = SampleTrim.trimmed(pcm, sampleRate: sr)
            XCTAssertGreaterThanOrEqual(off, 0)
            XCTAssertLessThanOrEqual(off + out.count, pcm.count)
            XCTAssertFalse(out.isEmpty && !pcm.isEmpty)
        }
    }
}
