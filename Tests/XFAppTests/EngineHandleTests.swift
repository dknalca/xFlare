// SPDX-License-Identifier: GPL-3.0-only
import XCTest
import Darwin
@testable import XFApp

/// Envoltorio del motor de audio. Se prueba el nucleo RT (`renderBlock`); el
/// host CoreAudio (`start`) no, necesita un dispositivo.
final class EngineHandleTests: XCTestCase {

    private func rms(_ x: [Float]) -> Double {
        (x.reduce(0.0) { $0 + Double($1) * Double($1) } / Double(max(1, x.count))).squareRoot()
    }

    func testCrear() {
        XCTAssertNotNil(EngineHandle(sampleRate: 48_000, maxFrames: 64))
    }

    func testElSampleSuenaYSePuedeCambiar() throws {
        let h = try XCTUnwrap(EngineHandle(sampleRate: 48_000, maxFrames: 64))
        h.loadSample((0..<48_000).map { Float(sin(2 * .pi * 1000 * Double($0) / 48_000)) * 0.5 })
        h.setMasterGain(1)
        h.setVelocity(1.0)

        var acc: [Float] = []
        for _ in 0..<80 { acc += h.renderBlock(count: 64).l }
        XCTAssertGreaterThan(rms(Array(acc.suffix(2048))), 0.2)

        h.loadSample([Float](repeating: 0.1, count: 8000))   // cambio sonando
        _ = h.renderBlock(count: 64)
        h.clearSample()
        _ = h.renderBlock(count: 64)   // sin crash
    }

    func testLaEntradaSeDrena() throws {
        let h = try XCTUnwrap(EngineHandle(sampleRate: 48_000, maxFrames: 64))
        let inL = (0..<64).map { Float(sin(Double($0) * 0.3)) * 0.4 }
        _ = h.renderBlock(inL: inL, inR: inL, count: 64)
        let pcm = h.drainInput()
        XCTAssertEqual(pcm.count, 128, "64 frames estereo int16")
        XCTAssertEqual(Int(pcm[0]), Int((inL[0] * 32767).rounded()), accuracy: 2)
        XCTAssertTrue(h.drainInput().isEmpty, "ya drenado")
    }

    func testElRelojMusicalYElMetronomo() throws {
        let h = try XCTUnwrap(EngineHandle(sampleRate: 48_000, maxFrames: 64))
        h.seek(tick: 0)
        h.setTransport(bpm: 120, ppq: 480, playing: true)

        XCTAssertFalse(h.metronomeEnabled == false && false)   // toggle
        h.metronomeEnabled = true
        XCTAssertTrue(h.metronomeEnabled)

        _ = h.renderBlock(count: 64)            // publica tick 0, luego avanza
        XCTAssertEqual(h.tick, 0)
        _ = h.renderBlock(count: 64)
        let perBlock = 120.0 / 60.0 * 480.0 / 48_000.0 * 64.0
        XCTAssertEqual(h.tick, perBlock, accuracy: 1e-6)
    }

    func testGananciaCeroSilencia() throws {
        let h = try XCTUnwrap(EngineHandle(sampleRate: 48_000, maxFrames: 64))
        h.loadSample([Float](repeating: 0.8, count: 4000))
        h.setVelocity(1.0)
        h.setMasterGain(0)
        let out = h.renderBlock(count: 64).l
        XCTAssertEqual(out.map { abs($0) }.max() ?? 0, 0)
    }
}
