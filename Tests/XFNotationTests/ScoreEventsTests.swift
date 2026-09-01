// SPDX-License-Identifier: GPL-3.0-only
import XCTest
@testable import XFNotation

/// B3.6 — eventos evaluables y maxScore por variante. Criterio unificado con
/// `docs/SCORING.md` §1 (decision del autor, 2026-09-01): `pitch` es uno por
/// semicorchea (`ppq/4`).
final class ScoreEventsTests: XCTestCase {

    private func compose(_ hand: String, _ fader: String, div: String, cycles: Int) throws -> Scratch {
        try Composer.compose(hand: hand, fader: fader, division: div, cycles: cycles,
                             primitives: try XFNFixtures.primitives())
    }

    /// El ejemplo textual de SCORING.md: 16 clicks + 16 tono + 4 amplitud = 3600.
    func testFlare2CBase_igualQueScoringMD() throws {
        let sc = try compose("baby", "flare_2c", div: "1/8", cycles: 4)
        let s = ScoreEvents(of: sc)
        XCTAssertEqual(s.clicks, 16)
        XCTAssertEqual(s.pitch, 16)          // 1920 / (480/4)
        XCTAssertEqual(s.amplitude, 4)
        XCTAssertEqual(s.events, 36)
        XCTAssertEqual(s.maxScore, 3600)
    }

    /// La variante de doble tiempo: mismo compas, el doble de clicks.
    func testFlare2CSubdivision16() throws {
        let base = try compose("baby", "flare_2c", div: "1/8", cycles: 4)
        let div16 = try Composer.composeWithSubdivision(base, to: "1/16",
                                                        primitives: try XFNFixtures.primitives())
        XCTAssertEqual(div16.lengthTicks, 1920)      // misma longitud musical
        let s = ScoreEvents(of: div16)
        XCTAssertEqual(s.clicks, 32)                 // el doble
        XCTAssertEqual(s.pitch, 16)
        XCTAssertEqual(s.amplitude, 8)
        XCTAssertEqual(s.maxScore, 5600)
    }

    func testBabyBase() throws {
        let sc = try compose("baby", "open", div: "1/8", cycles: 4)
        let s = ScoreEvents(of: sc)
        XCTAssertEqual(s.clicks, 0)
        XCTAssertEqual(s.pitch, 16)
        XCTAssertEqual(s.amplitude, 4)
        XCTAssertEqual(s.maxScore, 2000)
    }

    func testCatalogFlare2C16() throws {
        // el scratch de catalogo `flare-2c-16`: div 1/16, cycles 6
        let sc = try compose("baby", "flare_2c", div: "1/16", cycles: 6)
        let s = ScoreEvents(of: sc)
        XCTAssertEqual(s.clicks, 24)
        XCTAssertEqual(s.pitch, 12)                  // 1440 / 120
        XCTAssertEqual(s.amplitude, 6)
        XCTAssertEqual(s.maxScore, 4200)
    }
}
