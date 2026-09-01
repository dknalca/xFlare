// SPDX-License-Identifier: GPL-3.0-only
import XCTest
@testable import XFApp

/// B11.10 — asistente de mapeo MIDI/HID.
final class MidiMappingTests: XCTestCase {

    private let t0 = Date(timeIntervalSince1970: 1_760_000_000)

    func testMidiLearnCapturaElCC() {
        let m = MidiMappingModel()
        m.startListening(now: t0)
        m.learn(.crossfader)
        m.receivedMIDI(raw: "B0 07 40", cc: 7, value: 64, now: t0)
        XCTAssertEqual(m.crossfaderCC, 7)
        XCTAssertNil(m.learning, "aprender termina al capturar")
        XCTAssertTrue(m.isMapped)
    }

    func testSinAprenderLosMensajesSoloSeMonitorizan() {
        let m = MidiMappingModel()
        m.startListening(now: t0)
        m.receivedMIDI(raw: "90 3C 7F", cc: nil, value: nil, now: t0)
        XCTAssertNil(m.crossfaderCC)
        XCTAssertEqual(m.rawLog.first, "MIDI  90 3C 7F")
        XCTAssertTrue(m.sawMidi)
    }

    func testProponeAudioReturnSiNoLlegaMidiEn5s() {
        let m = MidiMappingModel()
        m.startListening(now: t0)
        XCTAssertFalse(m.shouldSuggestAudioReturn(now: t0.addingTimeInterval(4)))
        XCTAssertTrue(m.shouldSuggestAudioReturn(now: t0.addingTimeInterval(5)))
    }

    func testSiLlegaMidiNoProponeAudioReturn() {
        let m = MidiMappingModel()
        m.startListening(now: t0)
        m.receivedMIDI(raw: "B0 01 10", cc: 1, value: 16, now: t0.addingTimeInterval(2))
        XCTAssertFalse(m.shouldSuggestAudioReturn(now: t0.addingTimeInterval(30)))
    }

    func testElMonitorTraeLoMasRecienteDelanteYSeCapa() {
        let m = MidiMappingModel()
        m.startListening(now: t0)
        for i in 0..<250 { m.receivedHID(raw: "report \(i)", now: t0) }
        XCTAssertEqual(m.rawLog.count, 200)
        XCTAssertEqual(m.rawLog.first, "HID   report 249")
    }

    func testStartListeningReinicia() {
        let m = MidiMappingModel()
        m.startListening(now: t0)
        m.receivedMIDI(raw: "x", cc: nil, value: nil, now: t0)
        m.startListening(now: t0.addingTimeInterval(100))
        XCTAssertFalse(m.sawMidi)
        XCTAssertTrue(m.rawLog.isEmpty)
    }
}
