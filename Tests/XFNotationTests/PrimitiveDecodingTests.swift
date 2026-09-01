// SPDX-License-Identifier: GPL-3.0-only
import XCTest
@testable import XFNotation

/// B3.1 — los modelos decodifican `data/primitives/*.json` sin perdida.
final class PrimitiveDecodingTests: XCTestCase {

    func testDecodificaLasPrimitivas() throws {
        let prims = try XFNFixtures.primitives()
        // los 8 patrones de mano y 16 de fader del catalogo actual
        XCTAssertEqual(prims.handPatterns.count, 8)
        XCTAssertEqual(prims.faderPatterns.count, 16)
    }

    func testPatronDeManoBaby() throws {
        let baby = try XFNFixtures.primitives().hand("baby")
        XCTAssertEqual(baby.name, "Baby")
        XCTAssertEqual(baby.level, 1)
        XCTAssertEqual(baby.phases.count, 2)
        XCTAssertEqual(baby.phases[0].dir, .fwd)
        XCTAssertEqual(baby.phases[0].dist, 1.0)
        XCTAssertEqual(baby.phases[0].curve, .bell)
        XCTAssertEqual(baby.phases[1].dist, -1.0)
    }

    func testPatronDeFaderConReglasHeterogeneas() throws {
        let fc = try XFNFixtures.primitives().fader("forward_cut")
        XCTAssertEqual(fc.initial, .closed)
        XCTAssertEqual(fc.technique, "indice")
        XCTAssertEqual(fc.rules(for: .fwd).map(\.frac), [0.0, 0.96])
        XCTAssertEqual(fc.rules(for: .fwd).map(\.state), [.open, .closed])
        XCTAssertEqual(fc.rules(for: .rev).map(\.state), [.closed])
    }

    func testResolucionAnyYHold() throws {
        let flare = try XFNFixtures.primitives().fader("flare_1c")
        XCTAssertEqual(flare.initial, .open)
        // fwd y rev sin clave propia -> usan "any"
        XCTAssertEqual(flare.rules(for: .fwd).count, 2)
        XCTAssertEqual(flare.rules(for: .rev).count, 2)
        // hold tiene clave propia vacia -> sin reglas (no cae en "any")
        XCTAssertEqual(flare.rules(for: .hold).count, 0)
    }

    func testCatalogoDecodifica() throws {
        let cat = try XFNFixtures.catalog()
        XCTAssertEqual(cat.count, 25)
        XCTAssertEqual(cat.first?.id, "baby")
    }
}
