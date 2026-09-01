// SPDX-License-Identifier: GPL-3.0-only
import XCTest
@testable import XFProfiles

/// B5b.4 — autodeteccion por nombre de puerto/dispositivo.
/// B5b.5 — carga bundle + carpeta de usuario con precedencia.
final class ProfileStoreTests: XCTestCase {

    func testCargaLosSeisPerfilesDeFabrica() throws {
        let store = try ProfilesFixtures.store()
        // 5 .conf + 1 .example
        XCTAssertEqual(store.entries.count, 6)
        for e in store.entries.values {
            XCTAssertNil(e.problem, "\(e.id): \(e.problem ?? "")")
            XCTAssertNotNil(e.profile, "\(e.id) deberia tipar")
        }
        XCTAssertNotNil(store.profile(id: "rane-seventy-two"))
        XCTAssertNotNil(store.profile(id: "pioneer-djm-s9"))   // resuelto via extends
    }

    func testAutodeteccionUnica() throws {
        let store = try ProfilesFixtures.store()
        let result = store.autodetect(
            midiPortNames: ["Rane Seventy-Two MIDI 1", "IAC Bus"],
            audioDeviceNames: ["Rane Seventy-Two", "Built-in Output"]
        )
        guard case .unique(let p) = result else { return XCTFail("esperaba unique, llego \(result)") }
        XCTAssertEqual(p.id, "rane-seventy-two")
    }

    func testAutodeteccionSinCoincidencia() throws {
        let store = try ProfilesFixtures.store()
        let result = store.autodetect(midiPortNames: ["Teclado USB"], audioDeviceNames: ["MacBook Pro"])
        XCTAssertEqual(result, .none)
    }

    func testAutodeteccionAmbiguaNoElige() throws {
        // dos perfiles con el mismo patron -> empate -> ambiguous
        let a = """
        [profile]
        id = mesa-a
        name = Mesa A
        vendor = -
        schema = 1
        revision = 1
        verified = true
        [match]
        midi.port = *Battle*
        [crossfader]
        method = none
        """
        let b = a.replacingOccurrences(of: "mesa-a", with: "mesa-b")
                 .replacingOccurrences(of: "Mesa A", with: "Mesa B")
        let store = ProfileStore(bundled: [("mesa-a.conf", a), ("mesa-b.conf", b)])
        let result = store.autodetect(midiPortNames: ["Generic Battle Mixer"], audioDeviceNames: [])
        guard case .ambiguous(let hits) = result else { return XCTFail("esperaba ambiguous, llego \(result)") }
        XCTAssertEqual(hits.map(\.id), ["mesa-a", "mesa-b"])
    }

    func testPrecedenciaElUsuarioPisaAlBundle() throws {
        let bundled = try ProfilesFixtures.allFiles()
        // el usuario redefine rane-seventy-two con otro nombre
        let userOverride = """
        [profile]
        id = rane-seventy-two
        name = Mi Rane calibrada
        vendor = Rane
        schema = 1
        revision = 2
        verified = true
        [match]
        midi.port = *Seventy-Two*
        [crossfader]
        method = audio_return
        pilot.frequency = 20000
        pilot.level_db = -38
        cut_in.left = 0.05
        cut_in.right = 0.95
        """
        let store = ProfileStore(bundled: bundled,
                                 user: [("rane-seventy-two.conf", userOverride)])
        let p = try XCTUnwrap(store.profile(id: "rane-seventy-two"))
        XCTAssertEqual(p.name, "Mi Rane calibrada")
        XCTAssertEqual(p.revision, 2)
        XCTAssertEqual(p.crossfader.pilotFrequency, 20000)
        XCTAssertEqual(store.entries["rane-seventy-two"]?.origin, .user)
    }
}
