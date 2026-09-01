// SPDX-License-Identifier: GPL-3.0-only
import XCTest
@testable import XFProfiles

final class INIDocumentTests: XCTestCase {

    func testParseoBasico() throws {
        let ini = try INIDocument(text: """
        # comentario
        ; otro comentario
        [profile]
        id   = rane-seventy-two
        name = Rane Seventy-Two

        [audio]
        output.main.ch = 1,2
        return.ch      = 7,8
        """)
        XCTAssertEqual(ini.sectionOrder, ["profile", "audio"])
        XCTAssertEqual(ini.get("profile", "id"), "rane-seventy-two")
        XCTAssertEqual(ini.get("profile", "name"), "Rane Seventy-Two")
        XCTAssertEqual(ini.get("audio", "output.main.ch"), "1,2")     // clave con puntos
        XCTAssertTrue(ini.hasSection("audio"))
        XCTAssertFalse(ini.hasOption("audio", "no.existe"))
    }

    func testClavesSensiblesAMayusculas() throws {
        let ini = try INIDocument(text: "[s]\nFoo = 1\nfoo = 2\n")
        XCTAssertEqual(ini.get("s", "Foo"), "1")
        XCTAssertEqual(ini.get("s", "foo"), "2")
    }

    func testClaveRepetidaSeQuedaConLaUltima() throws {
        let ini = try INIDocument(text: "[s]\nk = a\nk = b\n")
        XCTAssertEqual(ini.get("s", "k"), "b")
    }

    func testDelimitadorDosPuntos() throws {
        let ini = try INIDocument(text: "[s]\nk : v : con : dos puntos\n")
        XCTAssertEqual(ini.get("s", "k"), "v : con : dos puntos")
    }

    func testErrorClaveFueraDeSeccion() {
        XCTAssertThrowsError(try INIDocument(text: "k = v\n")) { err in
            XCTAssertEqual(err as? INIDocument.ParseError, .keyOutsideSection(line: 1))
        }
    }

    func testErrorSinDelimitador() {
        XCTAssertThrowsError(try INIDocument(text: "[s]\nsoloclave\n")) { err in
            XCTAssertEqual(err as? INIDocument.ParseError, .missingDelimiter(line: 2))
        }
    }

    func testTodosLosPerfilesRealesParsean() throws {
        for f in try ProfilesFixtures.allFiles() {
            XCTAssertNoThrow(try INIDocument(text: f.text), "no parsea \(f.filename)")
        }
    }
}
