// SPDX-License-Identifier: GPL-3.0-only
import XCTest
@testable import XFClock

final class TimeSignatureTests: XCTestCase {

    func testCuatroCuartos() {
        let ts = TimeSignature.fourFour
        XCTAssertEqual(ts.ticksPerBeat, 480)      // negra = PPQ
        XCTAssertEqual(ts.ticksPerBar, 1920)      // 4 negras
    }

    func testTresCuartos() {
        let ts = TimeSignature(beatsPerBar: 3, beatUnit: 4)
        XCTAssertEqual(ts.ticksPerBeat, 480)
        XCTAssertEqual(ts.ticksPerBar, 1440)
    }

    func testSieteOctavos() {
        let ts = TimeSignature(beatsPerBar: 7, beatUnit: 8)
        XCTAssertEqual(ts.ticksPerBeat, 240)      // corchea = PPQ/2
        XCTAssertEqual(ts.ticksPerBar, 1680)
    }

    func testDosMitades() {
        let ts = TimeSignature(beatsPerBar: 2, beatUnit: 2)
        XCTAssertEqual(ts.ticksPerBeat, 960)      // blanca = PPQ*2
        XCTAssertEqual(ts.ticksPerBar, 1920)
    }
}
