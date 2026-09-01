// SPDX-License-Identifier: GPL-3.0-only
import XCTest
@testable import XFProfiles

/// B5b.3 — validacion equivalente a `tools/xf_profile.py` sobre los mismos
/// ficheros: mismos OK/FALLO y mismos avisos.
final class ProfileValidatorTests: XCTestCase {

    private func registry() throws -> [String: INIDocument] {
        var reg: [String: INIDocument] = [:]
        for f in try ProfilesFixtures.allFiles() {
            let ini = try INIDocument(text: f.text)
            let id = ini.get("profile", "id") ?? (f.filename as NSString).deletingPathExtension
            reg[id] = ini
        }
        return reg
    }

    /// `xf_profile.py --all` da: los 6 perfiles OK, y aviso "SIN VERIFICAR" en
    /// todos menos `keyboard.conf`.
    func testTodosLosPerfilesRealesCoincidenConPython() throws {
        let reg = try registry()
        let unverifiedWarn = "perfil SIN VERIFICAR contra hardware real"

        for f in try ProfilesFixtures.allFiles() {
            let raw = try INIDocument(text: f.text)
            let stem = (f.filename as NSString).deletingPathExtension
            let isExample = f.filename.hasSuffix(".example")
            let report = ProfileValidator.validate(raw: raw, registry: reg,
                                                   filenameStem: stem, isExample: isExample)

            XCTAssertTrue(report.isValid, "\(f.filename) deberia validar. errores: \(report.errors)")

            let verified = (raw.get("profile", "verified") ?? "false") == "true"
            if verified {
                XCTAssertFalse(report.warnings.contains(unverifiedWarn), "\(f.filename)")
            } else {
                XCTAssertTrue(report.warnings.contains(unverifiedWarn), "\(f.filename)")
            }
        }
    }

    func testDetectaMetodoInvalido() throws {
        let raw = try INIDocument(text: """
        [profile]
        id = x
        name = X
        vendor = -
        schema = 1
        revision = 1
        verified = true
        [crossfader]
        method = telepatia
        """)
        let r = ProfileValidator.validate(raw: raw, registry: [:], filenameStem: "x", isExample: false)
        XCTAssertFalse(r.isValid)
        XCTAssertTrue(r.errors.contains { $0.contains("method invalido") })
    }

    func testDetectaClavesQueFaltanSegunMetodo() throws {
        let raw = try INIDocument(text: """
        [profile]
        id = x
        name = X
        vendor = -
        schema = 1
        revision = 1
        verified = true
        [crossfader]
        method = audio_return
        cut_in.left = 0.1
        cut_in.right = 0.9
        """)
        let r = ProfileValidator.validate(raw: raw, registry: [:], filenameStem: "x", isExample: false)
        XCTAssertTrue(r.errors.contains("con method=audio_return hace falta crossfader.pilot.frequency"))
        XCTAssertTrue(r.errors.contains("con method=audio_return hace falta crossfader.pilot.level_db"))
    }

    func testCutInFueraDeRangoYOrden() throws {
        let raw = try INIDocument(text: """
        [profile]
        id = x
        name = X
        vendor = -
        schema = 1
        revision = 1
        verified = true
        [crossfader]
        method = none
        cut_in.left = 0.9
        cut_in.right = 0.2
        hysteresis = 1.5
        """)
        let r = ProfileValidator.validate(raw: raw, registry: [:], filenameStem: "x", isExample: false)
        XCTAssertTrue(r.errors.contains("crossfader.hysteresis fuera de 0..1"))
        XCTAssertTrue(r.errors.contains("cut_in.left debe ser menor que cut_in.right"))
    }

    func testIdConMayusculasOEspacios() throws {
        let raw = try INIDocument(text: """
        [profile]
        id = Mi Mesa
        name = X
        vendor = -
        schema = 1
        revision = 1
        verified = true
        [crossfader]
        method = none
        """)
        let r = ProfileValidator.validate(raw: raw, registry: [:], filenameStem: "Mi Mesa", isExample: false)
        XCTAssertTrue(r.errors.contains("el id debe ir en minusculas y sin espacios"))
    }

    func testExtendsInexistenteCortaLaValidacion() throws {
        let raw = try INIDocument(text: "[profile]\nid = x\nname = X\nextends = fantasma\n")
        let r = ProfileValidator.validate(raw: raw, registry: [:], filenameStem: "x", isExample: false)
        XCTAssertEqual(r.errors, ["extends apunta a un perfil que no existe: fantasma"])
    }
}
