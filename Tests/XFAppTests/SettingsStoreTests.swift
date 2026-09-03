// SPDX-License-Identifier: GPL-3.0-only
import XCTest
@testable import XFApp

/// `SettingsStore`: los ajustes se guardan en un fichero JSON legible y
/// copiable, escrito de forma atómica en cada cambio (así no dependen de que
/// `cfprefsd` vacíe a tiempo).
final class SettingsStoreTests: XCTestCase {

    /// El JSON del `save` se vuelve a leer idéntico con `load` (pasando por
    /// `AppSettings.raw` / `init(raw:)`).
    func testIdaYVueltaPorFichero() throws {
        // aislamos el fichero real: guardamos el contenido y lo restauramos.
        let url = SettingsStore.fileURL()
        let backup = try? Data(contentsOf: url)
        defer {
            if let backup { try? backup.write(to: url) }
            else { try? FileManager.default.removeItem(at: url) }
        }

        var s = AppSettings.defaults
        s.username = "dj"
        s.instrumentalLibrary = ["/m/a.wav", "/m/b.mp3"]
        s.sampleSlots = ["/s/kick.wav", "", "/s/vox.wav"]
        s.platterGlideMs = 2.5
        s.metronomeEnabled = false

        SettingsStore.save(s)
        let back = try XCTUnwrap(SettingsStore.load())

        XCTAssertEqual(back.username, "dj")
        XCTAssertEqual(back.instrumentalLibrary, ["/m/a.wav", "/m/b.mp3"])
        XCTAssertEqual(back.sampleSlots, ["/s/kick.wav", "", "/s/vox.wav", ""])
        XCTAssertEqual(back.platterGlideMs, 2.5, accuracy: 1e-9)
        XCTAssertFalse(back.metronomeEnabled)
    }

    func testEsUnJSONLegible() throws {
        let url = SettingsStore.fileURL()
        let backup = try? Data(contentsOf: url)
        defer {
            if let backup { try? backup.write(to: url) }
            else { try? FileManager.default.removeItem(at: url) }
        }

        SettingsStore.save(.defaults)
        let text = try String(contentsOf: url, encoding: .utf8)
        XCTAssertTrue(text.contains("\"metronome.enabled\""), "claves con nombre, no opacas")
        XCTAssertTrue(text.contains("\n"), "con sangría (prettyPrinted)")
    }
}
