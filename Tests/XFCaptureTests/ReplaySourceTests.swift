// SPDX-License-Identifier: GPL-3.0-only
import XCTest
@testable import XFCapture
import XFPrimitives

/// B6.6 — `ReplayMotionSource` / `ReplayFaderSource`.
final class ReplaySourceTests: XCTestCase {

    private let motion = (0..<10).map { i in
        MotionSample(hostTime: UInt64(i) * 100, position: Double(i), velocity: 1, confidence: 1)
    }

    func testAvanzaConElReloj() throws {
        let src = ReplayMotionSource(motion)
        XCTAssertNil(src.latest())          // sin start
        try src.start()
        XCTAssertNil(src.latest())          // start no adelanta nada

        src.seek(toHostTime: 250)           // pasan las muestras t=0,100,200
        XCTAssertEqual(src.latest()?.hostTime, 200)
        XCTAssertFalse(src.isFinished)

        src.seek(toHostTime: 1_000)         // todas
        XCTAssertEqual(src.latest()?.hostTime, 900)
        XCTAssertTrue(src.isFinished)
    }

    func testSeekNoRetrocede() throws {
        let src = ReplayMotionSource(motion)
        try src.start()
        src.seek(toHostTime: 500)
        XCTAssertEqual(src.latest()?.hostTime, 500)
        src.seek(toHostTime: 100)           // hacia atras: no hace nada
        XCTAssertEqual(src.latest()?.hostTime, 500)
    }

    func testDesdeSesion() throws {
        let header = XFSession.Header(tempoBPM: 120, anchorHostTime: 0, anchorTick: 0,
                                     hostNumer: 1, hostDenom: 1)
        let fader = [FaderSample(hostTime: 10, value: 0, isOpen: true),
                     FaderSample(hostTime: 20, value: 1, isOpen: false)]
        let session = XFSession(header: header, motion: motion, fader: fader)

        let m = ReplayMotionSource(session: session)
        let f = ReplayFaderSource(session: session)
        XCTAssertEqual(m.allSamples.count, 10)
        XCTAssertEqual(f.allSamples.count, 2)

        try f.start()
        f.seek(toHostTime: 15)
        XCTAssertEqual(f.latest()?.isOpen, true)
        f.seek(toHostTime: 25)
        XCTAssertEqual(f.latest()?.isOpen, false)
    }

    func testSesionVaciaNoRompe() throws {
        let src = ReplayFaderSource([])
        try src.start()
        src.seek(toHostTime: 999)
        XCTAssertNil(src.latest())
        XCTAssertTrue(src.isFinished)
    }
}
