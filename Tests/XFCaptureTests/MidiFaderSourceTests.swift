// SPDX-License-Identifier: GPL-3.0-only
import XCTest
@testable import XFCapture
import XFProfiles
import XFPrimitives

/// B6.4 — fuente de fader por MIDI CC (parte testeable; el conector CoreMIDI no
/// se prueba, necesita hardware).
final class MidiFaderSourceTests: XCTestCase {

    private func source(cc: Int = 7, channel: Int? = nil, invert: Bool = false,
                        cutIn: Float = 0.5, hysteresis: Float = 0.1,
                        hamster: Bool = false) -> MidiFaderSource {
        MidiFaderSource(
            config: MidiCrossfaderConfig(channel: channel, cc: cc, invert: invert),
            binarizer: FaderBinarizer(cutIn: cutIn, hysteresis: hysteresis, hamster: hamster))
    }

    // MARK: - config desde perfil

    func testConfigDesdeElPerfil() throws {
        let ini = try INIDocument(text: """
        [profile]
        id = m
        name = M
        vendor = -
        schema = 1
        revision = 1
        verified = true
        [crossfader]
        method = midi
        midi.channel = 3
        midi.cc = 16
        midi.min = 0
        midi.max = 127
        midi.invert = true
        cut_in.left = 0.05
        cut_in.right = 0.95
        """)
        let p = try DeviceProfile.parse(resolved: ini)
        let c = try MidiCrossfaderConfig(from: p)
        XCTAssertEqual(c.channel, 3)
        XCTAssertEqual(c.cc, 16)
        XCTAssertTrue(c.invert)
        XCTAssertEqual(try XCTUnwrap(c.value(fromCC: 0)), 1, accuracy: 1e-6)     // invert
        XCTAssertEqual(try XCTUnwrap(c.value(fromCC: 127)), 0, accuracy: 1e-6)
    }

    func testConfigLanzaSiNoEsMidi() throws {
        let ini = try INIDocument(text: """
        [profile]
        id = m
        name = M
        vendor = -
        schema = 1
        revision = 1
        verified = true
        [crossfader]
        method = audio_return
        pilot.frequency = 19500
        pilot.level_db = -40
        cut_in.left = 0.05
        cut_in.right = 0.95
        """)
        let p = try DeviceProfile.parse(resolved: ini)
        XCTAssertThrowsError(try MidiCrossfaderConfig(from: p))
    }

    // MARK: - decodificacion CC -> fader

    func testUnCCAbreYCierraElFader() throws {
        let s = source(cc: 7, cutIn: 0.5, hysteresis: 0.1)
        try s.start()
        s.ingest(status: 0xB0, data1: 7, data2: 120, hostTime: 100)   // ~0.94
        XCTAssertEqual(s.latest()?.isOpen, true)
        s.ingest(status: 0xB0, data1: 7, data2: 10, hostTime: 200)    // ~0.08
        XCTAssertEqual(s.latest()?.isOpen, false)
        XCTAssertEqual(s.latest()?.hostTime, 200)
    }

    func testIgnoraOtrosCCyOtrosMensajes() throws {
        let s = source(cc: 7)
        try s.start()
        s.ingest(status: 0xB0, data1: 8, data2: 127, hostTime: 1)     // otro CC
        s.ingest(status: 0x90, data1: 7, data2: 127, hostTime: 2)     // note on, no CC
        XCTAssertNil(s.latest())
        s.ingest(status: 0xB0, data1: 7, data2: 127, hostTime: 3)     // el bueno
        XCTAssertNotNil(s.latest())
    }

    func testFiltroPorCanal() throws {
        let s = source(cc: 7, channel: 3)
        try s.start()
        s.ingest(status: 0xB2, data1: 7, data2: 127, hostTime: 1)     // canal 3 (0xB2)
        XCTAssertEqual(s.latest()?.isOpen, true)
        s.ingest(status: 0xB5, data1: 7, data2: 0, hostTime: 2)       // canal 6: ignorado
        XCTAssertEqual(s.latest()?.isOpen, true, "el mensaje de otro canal no cambia nada")
    }

    func testOmniAceptaCualquierCanal() throws {
        let s = source(cc: 7, channel: nil)
        try s.start()
        s.ingest(status: 0xBF, data1: 7, data2: 127, hostTime: 1)     // canal 16
        XCTAssertEqual(s.latest()?.isOpen, true)
    }

    func testHamster() throws {
        let s = source(cc: 7, hamster: true)
        try s.start()
        s.ingest(status: 0xB0, data1: 7, data2: 5, hostTime: 1)       // valor bajo
        XCTAssertEqual(s.latest()?.isOpen, true, "con hamster, valor bajo = abierto")
    }

    func testSinArrancarIgnora() {
        let s = source()
        s.ingest(status: 0xB0, data1: 7, data2: 127, hostTime: 1)
        XCTAssertNil(s.latest())
    }

    // MARK: - troceo del flujo (lo que usa el conector)

    func testTroceaConRunningStatus() {
        // Bn 07 40  |  07 60 (running status)  |  07 7F
        let msgs = MidiFaderSource.messages(from: [0xB0, 0x07, 0x40, 0x07, 0x60, 0x07, 0x7F])
        XCTAssertEqual(msgs.count, 3)
        XCTAssertEqual(msgs.map { $0.data2 }, [0x40, 0x60, 0x7F])
        XCTAssertTrue(msgs.allSatisfy { $0.status == 0xB0 && $0.data1 == 0x07 })
    }

    func testSaltaSysExYTiempoReal() {
        // Un F8 (clock, tiempo real) NO rompe el running status; el SysEx SI (es
        // system common). Tras el SysEx hace falta un status nuevo.
        let bytes: [UInt8] = [0xB0, 0x07, 0x10,
                              0xF8,                            // realtime en medio: se ignora
                              0x07, 0x20,                       // running status sigue
                              0xF0, 0x7D, 0x01, 0xF7,           // sysex: rompe el running status
                              0x07, 0x30,                       // <- sin status, se descarta
                              0xB0, 0x07, 0x40]                 // status nuevo
        let msgs = MidiFaderSource.messages(from: bytes)
        XCTAssertEqual(msgs.map { $0.data2 }, [0x10, 0x20, 0x40])
    }

    func testMensajeDeUnSoloDato() {
        // Program Change (0xC0) tiene 1 dato -> data2 = 0
        let msgs = MidiFaderSource.messages(from: [0xC0, 0x05])
        XCTAssertEqual(msgs.count, 1)
        XCTAssertEqual(msgs[0].data1, 0x05)
        XCTAssertEqual(msgs[0].data2, 0)
    }

    func testIngestBytesPasaPorElParser() throws {
        let s = source(cc: 7)
        try s.start()
        s.ingest(bytes: [0xB0, 0x07, 0x40, 0x07, 0x7F], hostTime: 9)   // 2 CC seguidos
        XCTAssertEqual(try XCTUnwrap(s.latest()).value, Float(0x7F) / 127, accuracy: 1e-6)
    }
}
