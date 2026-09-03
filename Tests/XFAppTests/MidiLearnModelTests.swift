// SPDX-License-Identifier: GPL-3.0-only
import XCTest
@testable import XFApp
import XFCapture

/// "MIDI Learn" de Ajustes: seleccionar un comando, armar, y el siguiente
/// mensaje MIDI queda asignado. Se prueba el núcleo (`handle`), sin CoreMIDI.
final class MidiLearnModelTests: XCTestCase {

    func testAprendeElComandoSeleccionadoYSeDesarma() {
        let m = MidiLearnModel()
        var learned: [(PracticeCommand, String)] = []
        m.onLearn = { learned.append(($0, $1.text)) }

        m.select(.cue)
        m.arm()
        XCTAssertTrue(m.armed)

        // llega un CC 1·24 -> se asigna a cue y se desarma
        m.handle(status: 0xB0, data1: 24, data2: 90)
        XCTAssertEqual(learned.map { $0.0 }, [.cue])
        XCTAssertEqual(learned.first?.1, "cc:1:24")
        XCTAssertFalse(m.armed, "un solo aprendizaje por pulsación")

        // el siguiente mensaje ya no asigna nada
        m.handle(status: 0x90, data1: 40, data2: 100)
        XCTAssertEqual(learned.count, 1)
    }

    func testSinArmarSoloActualizaElMonitor() {
        let m = MidiLearnModel()
        var learned = 0
        m.onLearn = { _, _ in learned += 1 }
        m.select(.freeze)                       // seleccionado pero NO armado

        m.handle(status: 0x90, data1: 48, data2: 64)
        XCTAssertEqual(learned, 0)
        XCTAssertEqual(m.lastSeen, "note 1·48")

        m.handle(status: 0xB2, data1: 7, data2: 10)
        XCTAssertEqual(m.lastSeen, "cc 3·7")
    }

    func testMensajeNoAsignableNoDesarma() {
        let m = MidiLearnModel()
        var learned = 0
        m.onLearn = { _, _ in learned += 1 }
        m.select(.record); m.arm()

        // Note Off no sirve para aprender: sigue armado, esperando
        m.handle(status: 0x80, data1: 36, data2: 0)
        XCTAssertTrue(m.armed)
        XCTAssertEqual(learned, 0)

        // ahora un Note On de verdad
        m.handle(status: 0x90, data1: 36, data2: 100)
        XCTAssertEqual(learned, 1)
        XCTAssertFalse(m.armed)
    }

    func testSelectAlterna() {
        let m = MidiLearnModel()
        m.select(.bpmUp)
        XCTAssertEqual(m.selected, .bpmUp)
        m.select(.bpmUp)                        // otra vez -> deselecciona
        XCTAssertNil(m.selected)
    }
}
