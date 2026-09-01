// SPDX-License-Identifier: GPL-3.0-only
import XCTest
@testable import XFApp
import XFClock
import XFPrimitives

/// B11.5 — grabación rodante de los últimos 30 s.
final class FreeModeRecorderTests: XCTestCase {

    // 1 host tick = 1 ns, para poder razonar en segundos.
    private let host = HostClock(numer: 1, denom: 1)
    private func s(_ seconds: Double) -> UInt64 { UInt64(seconds * 1_000_000_000) }

    private func motion(at t: UInt64) -> MotionSample {
        MotionSample(hostTime: t, position: 0, velocity: 0, confidence: 1)
    }

    func testMantieneSoloLaVentana() {
        let r = FreeModeRecorder(windowSeconds: 30, host: host)
        for i in 0...60 { r.append(motion: motion(at: s(Double(i)))) }   // una por segundo, 0..60 s

        // "ahora" son 60 s; la ventana es [30, 60] -> 31 muestras (30..60)
        XCTAssertEqual(r.motion.count, 31)
        XCTAssertEqual(r.motion.first?.hostTime, s(30))
        XCTAssertEqual(r.motion.last?.hostTime, s(60))
    }

    func testAntesDeLlenarLaVentanaNoTiraNada() {
        let r = FreeModeRecorder(windowSeconds: 30, host: host)
        for i in 0...10 { r.append(motion: motion(at: s(Double(i)))) }
        XCTAssertEqual(r.motion.count, 11, "solo llevamos 10 s")
    }

    func testDuracionYSnapshot() {
        let r = FreeModeRecorder(windowSeconds: 30, host: host)
        r.append(motion: motion(at: s(100)))
        r.append(fader: FaderSample(hostTime: s(112), value: 0.9, isOpen: true))
        XCTAssertEqual(r.durationSeconds, 12, accuracy: 1e-6)
        XCTAssertEqual(r.snapshot.motion.count, 1)
        XCTAssertEqual(r.snapshot.fader.count, 1)
    }

    func testReset() {
        let r = FreeModeRecorder(host: host)
        r.append(motion: motion(at: s(1)))
        r.reset()
        XCTAssertTrue(r.motion.isEmpty)
        XCTAssertEqual(r.durationSeconds, 0)
    }

    func testMotionYFaderComparteVentana() {
        let r = FreeModeRecorder(windowSeconds: 10, host: host)
        r.append(motion: motion(at: s(1)))
        r.append(fader: FaderSample(hostTime: s(2), value: 0.1, isOpen: false))
        r.append(motion: motion(at: s(15)))   // ahora = 15 s, ventana [5, 15]
        XCTAssertTrue(r.motion.allSatisfy { $0.hostTime >= s(5) })
        XCTAssertTrue(r.fader.isEmpty, "el evento de fader de los 2 s se ha ido")
    }
}
