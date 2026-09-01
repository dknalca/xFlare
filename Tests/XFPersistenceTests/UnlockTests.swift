// SPDX-License-Identifier: GPL-3.0-only
import XCTest
import GRDB
@testable import XFPersistence

/// B10.2 — guardar y consultar el desbloqueo de variantes.
final class UnlockTests: XCTestCase {

    private let now = Date(timeIntervalSince1970: 1_760_000_000)

    func testMarcarYConsultar() throws {
        let db = try XFDatabase.inMemory()
        XCTAssertFalse(try db.isVariantUnlocked(exerciseId: "ex", variantId: "off50"))

        try db.markVariantUnlocked(exerciseId: "ex", variantId: "off50", at: now)
        XCTAssertTrue(try db.isVariantUnlocked(exerciseId: "ex", variantId: "off50"))
        XCTAssertEqual(try db.unlockedVariants(exerciseId: "ex"), ["off50"])
    }

    func testEsIdempotenteYConservaLaFecha() throws {
        let db = try XFDatabase.inMemory()
        try db.markVariantUnlocked(exerciseId: "ex", variantId: "off50", at: now)
        try db.markVariantUnlocked(exerciseId: "ex", variantId: "off50",
                                   at: now.addingTimeInterval(9_999))

        let rows = try db.writer.read { db in
            try VariantUnlock.filter(Column("exerciseId") == "ex").fetchAll(db)
        }
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows[0].unlockedAt, now, "no se pisa la fecha original")
    }

    func testCadaEjercicioLlevaSusVariantes() throws {
        let db = try XFDatabase.inMemory()
        try db.markVariantUnlocked(exerciseId: "ex-a", variantId: "off50", at: now)
        try db.markVariantUnlocked(exerciseId: "ex-a", variantId: "amp50", at: now)
        try db.markVariantUnlocked(exerciseId: "ex-b", variantId: "div16", at: now)

        XCTAssertEqual(try db.unlockedVariants(exerciseId: "ex-a"), ["off50", "amp50"])
        XCTAssertEqual(try db.unlockedVariants(exerciseId: "ex-b"), ["div16"])
    }
}
