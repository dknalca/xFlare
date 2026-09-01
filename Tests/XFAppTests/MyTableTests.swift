// SPDX-License-Identifier: GPL-3.0-only
import XCTest
@testable import XFApp

/// B11.9 — "Mi mesa".
final class MyTableTests: XCTestCase {

    private func row(_ id: String, name: String, source: MyTableRow.Source = .bundled,
                     verified: Bool = false, cal: Bool = false) -> MyTableRow {
        MyTableRow(profileId: id, name: name, source: source, verified: verified,
                   hasCalibration: cal)
    }

    private var table: MyTable {
        MyTable(rows: [
            row("generic-midi", name: "Genérico MIDI"),
            row("rane-seventy-two", name: "Rane Seventy-Two", verified: true, cal: true),
            row("keyboard", name: "Teclado", verified: true),
            row("mi-mesa", name: "Mi mesa", source: .user, cal: true),
        ], activeProfileId: "mi-mesa")
    }

    func testActivoYContadores() {
        let t = table
        XCTAssertEqual(t.active?.name, "Mi mesa")
        XCTAssertEqual(t.verifiedCount, 2)
        XCTAssertEqual(t.calibratedCount, 2)
    }

    func testOrdenActivoPrimeroLuegoVerificadosLuegoElResto() {
        let ids = table.sorted.map(\.profileId)
        XCTAssertEqual(ids.first, "mi-mesa", "el activo primero aunque no esté verificado")
        // luego los verificados por nombre: keyboard ("Teclado") vs rane ("Rane...")
        XCTAssertEqual(Array(ids[1...2]).sorted(), ["keyboard", "rane-seventy-two"])
        XCTAssertTrue(Set(ids[1...2]) == ["keyboard", "rane-seventy-two"])
        XCTAssertEqual(ids.last, "generic-midi", "el no verificado, al final")
    }

    func testSinActivo() {
        let t = MyTable(rows: [row("a", name: "A")], activeProfileId: nil)
        XCTAssertNil(t.active)
        XCTAssertEqual(t.sorted.count, 1)
    }
}
