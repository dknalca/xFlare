// SPDX-License-Identifier: GPL-3.0-only
import XCTest
@testable import XFProfiles

/// B5b.2 — resolucion de `extends` con deteccion de herencia circular.
final class ProfileResolverTests: XCTestCase {

    private func registry() throws -> [String: INIDocument] {
        var reg: [String: INIDocument] = [:]
        for f in try ProfilesFixtures.allFiles() {
            let ini = try INIDocument(text: f.text)
            let id = ini.get("profile", "id") ?? (f.filename as NSString).deletingPathExtension
            reg[id] = ini
        }
        return reg
    }

    func testDJMS9HeredaDeLaS11() throws {
        let resolved = try ProfileResolver.resolve(id: "pioneer-djm-s9", in: try registry())
        // lo propio de la s9
        XCTAssertEqual(resolved.get("profile", "id"), "pioneer-djm-s9")
        XCTAssertEqual(resolved.get("match", "midi.port"), "*DJM-S9*")
        // heredado de la s11
        XCTAssertEqual(resolved.get("crossfader", "method"), "audio_return")
        XCTAssertEqual(resolved.get("audio", "return.ch"), "7,8")
        XCTAssertEqual(resolved.get("audio", "timecode.deck1.ch"), "3,4")
        XCTAssertEqual(resolved.get("quirks", "hid_serato_mode"), "true")
        // el valor de `extends` se conserva tras resolver (como en xf_profile.py)
        XCTAssertEqual(resolved.get("profile", "extends"), "pioneer-djm-s11")

        let profile = try DeviceProfile.parse(resolved: resolved)
        XCTAssertEqual(profile.crossfader.method, .audioReturn)
        XCTAssertEqual(profile.audio.returnCh, [7, 8])
        XCTAssertEqual(profile.ancestorID, "pioneer-djm-s11")
    }

    func testPerfilSinExtendsSeDevuelveTalCual() throws {
        let resolved = try ProfileResolver.resolve(id: "rane-seventy-two", in: try registry())
        XCTAssertEqual(resolved.get("profile", "id"), "rane-seventy-two")
        XCTAssertNil(resolved.get("profile", "extends"))
    }

    func testHerenciaCircularDaErrorClaro() throws {
        var reg: [String: INIDocument] = [:]
        reg["a"] = try INIDocument(text: "[profile]\nid = a\nextends = b\n")
        reg["b"] = try INIDocument(text: "[profile]\nid = b\nextends = a\n")
        XCTAssertThrowsError(try ProfileResolver.resolve(id: "a", in: reg)) { err in
            guard case ProfileResolver.ResolveError.circularInheritance(let chain) = err else {
                return XCTFail("esperaba circularInheritance, llego \(err)")
            }
            XCTAssertEqual(chain, ["b", "a", "b"])
        }
    }

    func testExtendsAInexistente() throws {
        var reg: [String: INIDocument] = [:]
        reg["x"] = try INIDocument(text: "[profile]\nid = x\nextends = no-existe\n")
        XCTAssertThrowsError(try ProfileResolver.resolve(id: "x", in: reg)) { err in
            guard case ProfileResolver.ResolveError.unknownAncestor(_, let anc) = err else {
                return XCTFail("esperaba unknownAncestor, llego \(err)")
            }
            XCTAssertEqual(anc, "no-existe")
        }
    }
}
