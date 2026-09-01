// SPDX-License-Identifier: GPL-3.0-only
import XCTest
@testable import XFClock

/// B2.1 — conversiones tick <-> ms. El criterio es "ida y vuelta sin perdida en
/// 10.000 valores".
final class TempoConversionTests: XCTestCase {

    func testMillisecondsPorTickConocido() {
        // 120 bpm: una negra dura 500 ms; 500 / 480 ticks.
        let t = Tempo(bpm: 120)
        XCTAssertEqual(t.millisecondsPerTick, 500.0 / 480.0, accuracy: 1e-12)
        XCTAssertEqual(t.milliseconds(fromTicks: 480), 500.0, accuracy: 1e-9)
        XCTAssertEqual(t.seconds(fromTicks: 480), 0.5, accuracy: 1e-12)
    }

    func testTicksPorSegundo() {
        let t = Tempo(bpm: 120)               // 2 negras/s * 480 = 960 ticks/s
        XCTAssertEqual(t.ticksPerSecond, 960.0, accuracy: 1e-9)
    }

    /// Ida y vuelta tick -> ms -> tick para 10.000 valores y varios tempos.
    func testRoundTripTicksMilliseconds() {
        let tempos = [Tempo(bpm: 60), Tempo(bpm: 120), Tempo(bpm: 174),
                      Tempo(bpm: 240), Tempo(bpm: 128.5), Tempo(bpm: 33.333)]
        for tempo in tempos {
            for i in 0..<10_000 {
                // rango realista y ademas valores grandes (hasta ~10 millones)
                let t: Tick = i * 977 - 4_000_000
                let ms = tempo.milliseconds(fromTicks: t)
                XCTAssertEqual(tempo.ticks(fromMilliseconds: ms), t,
                               "bpm=\(tempo.bpm) t=\(t)")
            }
        }
    }

    func testRoundTripSeconds() {
        let tempo = Tempo(bpm: 100)
        for i in 0..<10_000 {
            let t: Tick = i - 5_000
            XCTAssertEqual(tempo.ticks(fromSeconds: tempo.seconds(fromTicks: t)), t)
        }
    }

    func testTempoEquatable() {
        XCTAssertEqual(Tempo(bpm: 120), Tempo(bpm: 120))
        XCTAssertNotEqual(Tempo(bpm: 120), Tempo(bpm: 121))
    }
}
