// SPDX-License-Identifier: GPL-3.0-only
import XCTest
@testable import XFCapture
import XFClock
import XFPrimitives

/// B6.6 — formato `.xfsession`: grabar y reproducir. "Una sesion grabada se
/// reproduce bit a bit igual".
final class XFSessionTests: XCTestCase {

    private func sampleSession() -> XFSession {
        let header = XFSession.Header(
            tempoBPM: 172.0,
            anchorHostTime: 2_000_000_000_000,
            anchorTick: 0,
            hostNumer: 125, hostDenom: 3,
            notes: "toma de prueba"
        )
        let motion = (0..<50).map { i in
            MotionSample(hostTime: 2_000_000_000_000 + UInt64(i) * 22_000,
                         position: Double(i) * 0.03 - 0.7,
                         velocity: (i % 2 == 0) ? 1.4 : -1.1,
                         confidence: 0.95)
        }
        let fader = (0..<12).map { i in
            FaderSample(hostTime: 2_000_000_000_000 + UInt64(i) * 90_000,
                        value: Float(i) / 12.0,
                        isOpen: i % 3 != 0)
        }
        return XFSession(header: header, motion: motion, fader: fader)
    }

    func testIdaYVueltaConservaTodo() throws {
        let s = sampleSession()
        let text = s.encodedJSONLines()
        let back = try XFSession(jsonLines: text)
        XCTAssertEqual(back, s)
    }

    func testReEncodeEsEstable() throws {
        // codificar, decodificar y volver a codificar da el MISMO texto.
        let s = sampleSession()
        let once = s.encodedJSONLines()
        let twice = try XFSession(jsonLines: once).encodedJSONLines()
        XCTAssertEqual(once, twice)
    }

    func testPrimeraLineaEsLaCabecera() {
        let text = sampleSession().encodedJSONLines()
        let first = text.split(separator: "\n").first.map(String.init) ?? ""
        XCTAssertTrue(first.contains("\"kind\":\"header\""))
        XCTAssertTrue(first.contains("\"bpm\":\"172.0\""))
    }

    func testReconstruyeElClockMap() {
        let s = sampleSession()
        let cm = s.clockMap
        XCTAssertEqual(cm.tempo.bpm, 172.0)
        XCTAssertEqual(cm.host.numer, 125)
        XCTAssertEqual(cm.host.denom, 3)
        // el ancla es tick 0 en su hostTime
        XCTAssertEqual(cm.tick(fromHostTime: 2_000_000_000_000), 0)
    }

    func testErroresDeFormato() {
        XCTAssertThrowsError(try XFSession(jsonLines: "")) { e in
            XCTAssertEqual(e as? XFSession.SessionError, .empty)
        }
        XCTAssertThrowsError(try XFSession(jsonLines: "{\"kind\":\"m\",\"t\":1,\"p\":\"0\",\"vel\":\"0\",\"c\":\"1\"}\n")) { e in
            XCTAssertEqual(e as? XFSession.SessionError, .missingHeader)
        }
        XCTAssertThrowsError(try XFSession(jsonLines: "no es json\n"))
    }
}
