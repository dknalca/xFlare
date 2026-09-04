// SPDX-License-Identifier: GPL-3.0-only
import XCTest
import Combine
@testable import XFApp
import XFCapture
import XFProfiles

/// F.61 — el crossfader por MIDI (ADR-021) va de "el perfil lo declara" a
/// "de verdad llega a la práctica". `AppModel.midiMonitor.onMessage` es el
/// mismo punto de entrada que usaría CoreMIDI real; estos tests lo llaman
/// directo (sin abrir CoreMIDI de verdad, sin mesa) y comprueban que el
/// mensaje correcto acaba como `PracticeCommandEvent.faderClosed` en
/// `practiceCommandEvents`, igual que ya se comprueba con los comandos
/// discretos en `AppModelTests`.
final class AppModelMidiCrossfaderTests: XCTestCase {

    /// Perfil sintético con crossfader por MIDI: CC8, canal 16 (el mismo par
    /// que confirmó B1.4 con la Rane 72 real), cut-in a la mitad para que los
    /// bytes de prueba crucen el umbral con margen.
    private static let midiProfileText = """
    [profile]
    id = test-midi-mesa
    name = Test MIDI Mesa
    vendor = -
    schema = 1
    revision = 1
    verified = true
    [crossfader]
    method = midi
    midi.channel = 16
    midi.cc = 8
    midi.min = 0
    midi.max = 127
    cut_in.left = 0.5
    hysteresis = 0.1
    reverse_default = false
    [transport]
    command.cue = note:1:36
    """

    /// Mismo perfil pero por retorno de audio (ADR-021 respaldo): sirve para
    /// comprobar que unos bytes de crossfader NO hacen nada si el perfil
    /// activo no lee el crossfader por MIDI.
    private static let audioReturnProfileText = """
    [profile]
    id = test-audio-mesa
    name = Test Audio Mesa
    vendor = -
    schema = 1
    revision = 1
    verified = true
    [crossfader]
    method = audio_return
    pilot.frequency = 19500
    pilot.level_db = -40
    cut_in.left = 0.5
    hysteresis = 0.1
    """

    private func model() throws -> AppModel {
        let catalog = try CatalogLoader.load(from: RepoContentLoader())
        let profiles = ProfileStore(bundled: [
            ("test-midi-mesa.conf", Self.midiProfileText),
            ("test-audio-mesa.conf", Self.audioReturnProfileText),
        ], user: [])
        return AppModel(catalog: catalog, db: try .inMemory(), profiles: profiles)
    }

    /// CC8/canal16: byte de status 0xBF (Control Change, canal 16 = nibble 0xF).
    private func ccByte(_ value: UInt8) -> (UInt8, UInt8, UInt8) { (0xBF, 8, value) }

    func testElCrossfaderPorMidiAbreYCierraElFaderDeLaPractica() throws {
        let m = try model()
        m.activeProfileId = "test-midi-mesa"

        var got: [PracticeCommandEvent] = []
        let c = m.practiceCommandEvents.sink { got.append($0) }
        defer { c.cancel() }

        let (openSt, openD1, openD2) = ccByte(120)     // ~0.94 -> abierto
        m.midiMonitor.onMessage?(openSt, openD1, openD2)
        let (closeSt, closeD1, closeD2) = ccByte(10)    // ~0.08 -> cerrado
        m.midiMonitor.onMessage?(closeSt, closeD1, closeD2)

        XCTAssertEqual(got, [.faderClosed(false), .faderClosed(true)])
    }

    func testMensajesDentroDeLaHisteresisNoRepitenElEvento() throws {
        let m = try model()
        m.activeProfileId = "test-midi-mesa"

        var got: [PracticeCommandEvent] = []
        let c = m.practiceCommandEvents.sink { got.append($0) }
        defer { c.cancel() }

        for v: UInt8 in [120, 125, 118, 122] {   // siempre abierto, se mueve pero no cruza
            let (s, d1, d2) = ccByte(v)
            m.midiMonitor.onMessage?(s, d1, d2)
        }

        XCTAssertEqual(got, [.faderClosed(false)], "solo el primer mensaje cruza el umbral")
    }

    func testUnPerfilSinCrossfaderMidiIgnoraLosMismosBytes() throws {
        let m = try model()
        m.activeProfileId = "test-audio-mesa"   // method = audio_return, no midi

        var got: [PracticeCommandEvent] = []
        let c = m.practiceCommandEvents.sink { got.append($0) }
        defer { c.cancel() }

        let (s, d1, d2) = ccByte(120)
        m.midiMonitor.onMessage?(s, d1, d2)

        XCTAssertTrue(got.isEmpty, "sin method = midi no hay crossfaderSource que dispare nada")
    }

    func testCambiarDePerfilDesconectaElCrossfaderAnterior() throws {
        let m = try model()
        m.activeProfileId = "test-midi-mesa"

        var got: [PracticeCommandEvent] = []
        let c = m.practiceCommandEvents.sink { got.append($0) }
        defer { c.cancel() }

        m.activeProfileId = "test-audio-mesa"   // cambia ANTES de que llegue nada

        let (s, d1, d2) = ccByte(120)
        m.midiMonitor.onMessage?(s, d1, d2)

        XCTAssertTrue(got.isEmpty, "el crossfaderSource del perfil viejo ya no debe escuchar")
    }

    /// El mismo `onMessage` reparte a los comandos discretos (ADR-054) Y al
    /// crossfader — no son caminos separados por accidente.
    func testElMismoDespachoAtiendeComandosDiscretosYCrossfaderALaVez() throws {
        let m = try model()
        m.activeProfileId = "test-midi-mesa"   // trae command.cue = note:1:36

        var got: [PracticeCommandEvent] = []
        let c = m.practiceCommandEvents.sink { got.append($0) }
        defer { c.cancel() }

        m.midiMonitor.onMessage?(0x90, 36, 100)          // Note On 36 canal 1 -> cue
        let (s, d1, d2) = ccByte(120)
        m.midiMonitor.onMessage?(s, d1, d2)               // crossfader abre

        XCTAssertEqual(got, [.trigger(.cue), .faderClosed(false)])
    }
}
