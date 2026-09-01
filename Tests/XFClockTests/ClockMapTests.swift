// SPDX-License-Identifier: GPL-3.0-only
import XCTest
@testable import XFClock

/// B2.3 — ClockMap: mapear una captura a ticks. "test con desfase y con tempo
/// distinto". Incluye tambien la ida y vuelta hostTime <-> tick de B2.1.
final class ClockMapTests: XCTestCase {

    // Timebases representativas: Intel (1/1) y Apple Silicon (125/3).
    private let intel = HostClock(numer: 1, denom: 1)
    private let apple = HostClock(numer: 125, denom: 3)

    func testValorConocidoSinDesfase() {
        // 120 bpm, ancla en el origen: 480 ticks = 1 negra = 500 ms = 5e8 ns.
        let map = ClockMap(anchorHostTime: 0, anchorTick: 0, tempo: Tempo(bpm: 120), host: intel)
        XCTAssertEqual(map.hostTime(fromTick: 480), 500_000_000)
        XCTAssertEqual(map.tick(fromHostTime: 500_000_000), 480)
    }

    func testConDesfaseDeAncla() {
        // El ancla dice: hostTime 1_000_000_000 corresponde al tick 96.
        let map = ClockMap(anchorHostTime: 1_000_000_000, anchorTick: 96,
                           tempo: Tempo(bpm: 120), host: intel)
        // en el ancla exacta
        XCTAssertEqual(map.tick(fromHostTime: 1_000_000_000), 96)
        XCTAssertEqual(map.hostTime(fromTick: 96), 1_000_000_000)
        // 500 ms despues del ancla -> 480 ticks mas -> tick 576
        XCTAssertEqual(map.tick(fromHostTime: 1_500_000_000), 576)
        // y hacia atras del ancla: 500 ms antes -> tick -384
        XCTAssertEqual(map.tick(fromHostTime: 500_000_000), 96 - 480)
    }

    func testTempoDistintoDaTicksDistintos() {
        let a = ClockMap(anchorHostTime: 0, anchorTick: 0, tempo: Tempo(bpm: 120), host: intel)
        let b = ClockMap(anchorHostTime: 0, anchorTick: 0, tempo: Tempo(bpm: 240), host: intel)
        // el mismo hostTime: al doble de tempo, el doble de ticks
        let h: UInt64 = 500_000_000
        XCTAssertEqual(a.tick(fromHostTime: h), 480)
        XCTAssertEqual(b.tick(fromHostTime: h), 960)
    }

    func testNoBajaDeCeroHaciaAtras() {
        let map = ClockMap(anchorHostTime: 1_000, anchorTick: 0, tempo: Tempo(bpm: 120), host: intel)
        // un tick muy negativo cae por debajo de 0 -> se satura en 0
        XCTAssertEqual(map.hostTime(fromTick: -100_000), 0)
    }

    /// Ida y vuelta tick -> hostTime -> tick para 10.000 valores, con desfase de
    /// ancla, varios tempos y las dos timebases.
    ///
    /// El ancla se pone en un `hostTime` grande y realista (un `mach_absolute_time`
    /// de una maquina encendida hace rato). Con anclas diminutas los ticks muy
    /// anteriores al ancla caerian en `hostTime` negativo, que se satura a 0 y
    /// entonces la ida y vuelta no puede recuperarlos; eso no pasa en uso real y
    /// se comprueba aparte en `testNoBajaDeCeroHaciaAtras`.
    func testRoundTripTickHostTime() {
        let hosts = [intel, apple]
        let tempos = [Tempo(bpm: 60), Tempo(bpm: 120), Tempo(bpm: 174), Tempo(bpm: 128.5)]
        for host in hosts {
            for tempo in tempos {
                let map = ClockMap(anchorHostTime: 2_000_000_000_000, anchorTick: 12_345,
                                   tempo: tempo, host: host)
                for i in 0..<10_000 {
                    let t: Tick = 12_345 + (i - 5_000) * 37   // alrededor del ancla, ambos signos
                    let h = map.hostTime(fromTick: t)
                    XCTAssertEqual(map.tick(fromHostTime: h), t,
                                   "host=\(host.numer)/\(host.denom) bpm=\(tempo.bpm) t=\(t)")
                }
            }
        }
    }

    func testStartingNowUsaTick0() {
        let map = ClockMap.startingNow(tempo: Tempo(bpm: 120), host: intel)
        XCTAssertEqual(map.anchorTick, 0)
        XCTAssertGreaterThan(map.anchorHostTime, 0)
    }

    func testEquatable() {
        let m1 = ClockMap(anchorHostTime: 10, anchorTick: 2, tempo: Tempo(bpm: 120), host: intel)
        let m2 = ClockMap(anchorHostTime: 10, anchorTick: 2, tempo: Tempo(bpm: 120), host: intel)
        let m3 = ClockMap(anchorHostTime: 10, anchorTick: 2, tempo: Tempo(bpm: 120), host: apple)
        XCTAssertEqual(m1, m2)
        XCTAssertNotEqual(m1, m3)
    }
}
