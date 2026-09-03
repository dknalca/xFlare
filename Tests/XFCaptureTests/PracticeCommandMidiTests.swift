// SPDX-License-Identifier: GPL-3.0-only
import XCTest
@testable import XFCapture
import XFProfiles

final class PracticeCommandMidiTests: XCTestCase {

    // MARK: - MidiBinding

    func testBindingIdaYVuelta() {
        for t in ["note:1:36", "cc:0:24", "note:16:127"] {
            let b = MidiBinding(t)
            XCTAssertNotNil(b, t)
            XCTAssertEqual(b?.text, t)
        }
        XCTAssertEqual(MidiBinding("note:2:0x30")?.number, 0x30)   // hex
        for bad in ["", "note:1", "midi:1:2", "note:x:2", "note:1:999"] {
            // "note:1:999" no falla al parsear pero se recorta a 127
            let b = MidiBinding(bad)
            if bad == "note:1:999" { XCTAssertEqual(b?.number, 127) }
            else { XCTAssertNil(b, bad) }
        }
    }

    // MARK: - decodificador

    private func map(_ pairs: [(PracticeCommand, String)]) -> MidiCommandMap {
        var b: [PracticeCommand: MidiBinding] = [:]
        for (c, s) in pairs { b[c] = MidiBinding(s) }
        return MidiCommandMap(bindings: b)
    }

    func testNoteOnDisparaElComando() {
        let m = map([(.cue, "note:1:36")])
        // Note On canal 1, nota 36, vel 100
        XCTAssertEqual(m.event(status: 0x90, data1: 36, data2: 100), .trigger(.cue))
        // Note Off / vel 0 -> nada para un discreto
        XCTAssertNil(m.event(status: 0x80, data1: 36, data2: 0))
        XCTAssertNil(m.event(status: 0x90, data1: 36, data2: 0))
        // otra nota -> nada
        XCTAssertNil(m.event(status: 0x90, data1: 37, data2: 100))
    }

    func testCCPorEncimaDe64Dispara() {
        let m = map([(.freeze, "cc:1:20")])
        XCTAssertEqual(m.event(status: 0xB0, data1: 20, data2: 127), .trigger(.freeze))
        XCTAssertEqual(m.event(status: 0xB0, data1: 20, data2: 64), .trigger(.freeze))
        XCTAssertNil(m.event(status: 0xB0, data1: 20, data2: 10))   // por debajo: nada
    }

    func testElFaderEsMomentaneo() {
        let m = map([(.fader, "note:1:48")])
        XCTAssertEqual(m.event(status: 0x90, data1: 48, data2: 100), .faderClosed(true))
        XCTAssertEqual(m.event(status: 0x80, data1: 48, data2: 0), .faderClosed(false))
        XCTAssertEqual(m.event(status: 0x90, data1: 48, data2: 0), .faderClosed(false))
        // por CC: >=64 cerrado, <64 abierto
        let mc = map([(.fader, "cc:1:7")])
        XCTAssertEqual(mc.event(status: 0xB0, data1: 7, data2: 90), .faderClosed(true))
        XCTAssertEqual(mc.event(status: 0xB0, data1: 7, data2: 5), .faderClosed(false))
    }

    func testCanalCeroEsCualquiera() {
        let any = map([(.cue, "note:0:36")])
        XCTAssertEqual(any.event(status: 0x95, data1: 36, data2: 100), .trigger(.cue))  // canal 6
        let ch1 = map([(.cue, "note:1:36")])
        XCTAssertNil(ch1.event(status: 0x95, data1: 36, data2: 100))                    // canal 6 != 1
        XCTAssertEqual(ch1.event(status: 0x90, data1: 36, data2: 100), .trigger(.cue))  // canal 1
    }

    // MARK: - perfil [transport] + overrides

    func testLeeLaSeccionTransportDelPerfil() throws {
        let ini = try INIDocument(text: """
        [transport]
        command.cue = note:1:36
        command.restart_base = note:1:37
        command.fader = cc:1:7
        command.freeze = cc:0:64
        """)
        let m = MidiCommandMap.fromProfile(ini)
        XCTAssertEqual(m.bindings[.cue]?.text, "note:1:36")
        XCTAssertEqual(m.bindings[.fader]?.text, "cc:1:7")
        XCTAssertEqual(m.bindings[.freeze]?.channel, 0)
        XCTAssertNil(m.bindings[.record])
    }

    func testMidiLearnTraduceElMensajeAAsignacion() {
        // Note On -> note:canal:nota
        XCTAssertEqual(MidiBinding.learned(status: 0x90, data1: 36, data2: 100)?.text, "note:1:36")
        XCTAssertEqual(MidiBinding.learned(status: 0x95, data1: 60, data2: 1)?.text, "note:6:60")
        // Control Change -> cc:canal:cc (cualquier valor, tambien 0)
        XCTAssertEqual(MidiBinding.learned(status: 0xB0, data1: 24, data2: 127)?.text, "cc:1:24")
        XCTAssertEqual(MidiBinding.learned(status: 0xB3, data1: 7, data2: 0)?.text, "cc:4:7")
        // Note Off / Note On vel 0 / pitch bend / aftertouch -> nada que aprender
        XCTAssertNil(MidiBinding.learned(status: 0x80, data1: 36, data2: 0))
        XCTAssertNil(MidiBinding.learned(status: 0x90, data1: 36, data2: 0))
        XCTAssertNil(MidiBinding.learned(status: 0xE0, data1: 0, data2: 64))
        XCTAssertNil(MidiBinding.learned(status: 0xD0, data1: 20, data2: 0))
    }

    func testElOverrideDelUsuarioGana() {
        let base = map([(.cue, "note:1:36"), (.freeze, "note:1:40")])
        let merged = base.merging(userOverrides: [.cue: MidiBinding("note:2:60")!])
        XCTAssertEqual(merged.bindings[.cue]?.text, "note:2:60")   // pisado
        XCTAssertEqual(merged.bindings[.freeze]?.text, "note:1:40") // intacto
    }

    func testLosCuatroSlotsDeSampleSonComandosMapeables() {
        // los 4 slots existen, tienen confKey y label propios y no son momentáneos
        let slots: [PracticeCommand] = [.sample1, .sample2, .sample3, .sample4]
        XCTAssertEqual(slots.map { $0.confKey },
                       ["command.sample_1", "command.sample_2", "command.sample_3", "command.sample_4"])
        XCTAssertEqual(slots.map { $0.label }, ["Sample 1", "Sample 2", "Sample 3", "Sample 4"])
        XCTAssertFalse(slots.contains { $0.isMomentary })

        // se leen de la sección [transport] y disparan como discretos
        let ini = try! INIDocument(text: """
        [transport]
        command.sample_1 = note:1:60
        command.sample_3 = cc:1:20
        """)
        let m = MidiCommandMap.fromProfile(ini)
        XCTAssertEqual(m.event(status: 0x90, data1: 60, data2: 100), .trigger(.sample1))
        XCTAssertEqual(m.event(status: 0xB0, data1: 20, data2: 127), .trigger(.sample3))
        XCTAssertNil(m.bindings[.sample2])
    }

    // MARK: - source

    func testSourceEmiteAlRecibirBytes() {
        let src = MidiCommandSource(map: map([(.record, "note:1:50")]))
        var got: [PracticeCommandEvent] = []
        src.onCommand = { got.append($0) }
        src.ingest(bytes: [0x90, 50, 0x64])          // Note On 50
        src.ingest(bytes: [0x90, 51, 0x64])          // otra nota
        XCTAssertEqual(got, [.trigger(.record)])
    }
}
