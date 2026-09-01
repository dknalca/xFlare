// SPDX-License-Identifier: GPL-3.0-only
import XCTest
import XFTestKit
@testable import XFNotation

/// B3.4 — recorte con tramo parcial de curva.
/// B3.5 — transformaciones de variante (offset, amplitude, mirror, swing),
///        golden contra `tools/xfn_core.py`.
final class CropAndVariantTests: XCTestCase {

    private func primitives() throws -> PrimitiveSet { try XFNFixtures.primitives() }

    // MARK: - B3.4 crop

    /// Recortar por la mitad de un movimiento conserva la curva EXACTA (no la
    /// aproxima con rectas): la posicion muestreada en el tramo solapado tiene
    /// que coincidir con la del scratch entero.
    func testCropConservaLaCurvaExacta() throws {
        let sc = try Composer.compose(hand: "baby", fader: "flare_2c",
                                      division: "1/8", cycles: 4, primitives: primitives())
        // corte que cae en mitad de la 1a fase (dur 240) y de otra fase interior
        let t0 = 120, t1 = 900
        let cut = sc.cropped(from: t0, to: t1)
        XCTAssertEqual(cut.lengthTicks, t1 - t0)

        for tick in stride(from: 0, through: t1 - t0, by: 7) {
            let got = PositionSampler.position(of: cut, atTick: tick)
            let want = PositionSampler.position(of: sc, atTick: tick + t0)
            XCTAssertTrue(Golden.approxEqual(Golden.round4(got), Golden.round4(want)),
                          "tick \(tick): recortado \(got) vs entero \(want)")
        }
    }

    func testCropAjustaClickCountYFader() throws {
        let sc = try Composer.compose(hand: "baby", fader: "flare_2c",
                                      division: "1/8", cycles: 4, primitives: primitives())
        let cut = sc.cropped(from: 0, to: 480)   // primer ciclo
        XCTAssertEqual(cut.faderEvents.first?.t, 0)
        XCTAssertEqual(cut.clickCount, cut.faderEvents.filter { $0.state == .closed }.count)
        XCTAssertLessThan(cut.clickCount, sc.clickCount)
    }

    // MARK: - B3.5 variantes (golden vs xfn_core.py)

    /// [t, dur, dir, pFrom, pTo, u0, u1] por fase — la forma que devuelve el
    /// helper `dig()` con el que se generaron estas referencias en Python.
    private func digRecord(_ sc: Scratch) -> [[String]] {
        sc.record.map { p in
            [String(p.t), String(p.dur), p.dir.rawValue,
             String(Golden.round4(p.pFrom)), String(Golden.round4(p.pTo)),
             String(Golden.round4(p.u0)), String(Golden.round4(p.u1)), p.curve.rawValue]
        }
    }
    private func digFader(_ sc: Scratch) -> [[String]] {
        sc.faderEvents.map { [String($0.t), $0.state.rawValue] }
    }

    func testOffset50() throws {
        let v = try Composer.composeWithOffset(hand: "baby", fader: "flare_2c",
                                               division: "1/8", cycles: 4, fraction: 0.5,
                                               primitives: primitives())
        XCTAssertEqual(v.lengthTicks, 1920)
        XCTAssertEqual(v.clickCount, 16)
        XCTAssertEqual(digRecord(v), [
            ["0","240","rev","1.0","0.0","0.0","1.0","bell"],
            ["240","240","fwd","0.0","1.0","0.0","1.0","bell"],
            ["480","240","rev","1.0","0.0","0.0","1.0","bell"],
            ["720","240","fwd","0.0","1.0","0.0","1.0","bell"],
            ["960","240","rev","1.0","0.0","0.0","1.0","bell"],
            ["1200","240","fwd","0.0","1.0","0.0","1.0","bell"],
            ["1440","240","rev","1.0","0.0","0.0","1.0","bell"],
            ["1680","240","fwd","0.0","1.0","0.0","1.0","bell"],
        ])
        XCTAssertEqual(v.faderEvents.map(\.t).prefix(6).map { $0 }, [0, 67, 86, 149, 168, 307])
        XCTAssertEqual(v.faderEvents.count, 33)
    }

    func testAmplitude50() throws {
        let base = try Composer.compose(hand: "baby", fader: "flare_2c",
                                        division: "1/8", cycles: 4, primitives: primitives())
        let v = base.withAmplitude(scale: 0.5)
        XCTAssertEqual(digRecord(v).map { [$0[0], $0[3], $0[4]] }, [
            ["0","0.0","0.5"], ["240","0.5","0.0"], ["480","0.0","0.5"], ["720","0.5","0.0"],
            ["960","0.0","0.5"], ["1200","0.5","0.0"], ["1440","0.0","0.5"], ["1680","0.5","0.0"],
        ])
        // from/to nominales NO cambian
        XCTAssertEqual(v.record[0].from, 0.0)
        XCTAssertEqual(v.record[0].to, 1.0)
    }

    func testMirror() throws {
        let base = try Composer.compose(hand: "baby", fader: "flare_2c",
                                        division: "1/8", cycles: 4, primitives: primitives())
        let v = base.mirrored()
        XCTAssertEqual(v.record[0].dir, .rev)
        XCTAssertEqual(v.record[1].dir, .fwd)
        XCTAssertTrue(Golden.approxEqual(v.record[0].pTo, -1.0))
        XCTAssertTrue(Golden.approxEqual(v.record[1].pFrom, -1.0))
        XCTAssertEqual(v.faderEvents.map(\.t), base.faderEvents.map(\.t))   // el fader no se toca
    }

    func testSubdivision16PreservaLongitudYDuplicaClicks() throws {
        let base = try Composer.compose(hand: "baby", fader: "flare_2c",
                                        division: "1/8", cycles: 4, primitives: primitives())
        let v = try Composer.composeWithSubdivision(base, to: "1/16", primitives: primitives())
        XCTAssertEqual(v.div, "1/16")
        XCTAssertEqual(v.cycles, 8)                      // 4 * 240/120
        XCTAssertEqual(v.lengthTicks, base.lengthTicks)  // misma longitud musical
        XCTAssertEqual(v.clickCount, base.clickCount * 2)
        XCTAssertEqual(v.record.count, base.record.count * 2)
        // conserva los metadatos del scratch de origen
        XCTAssertEqual(v.id, base.id)
        XCTAssertEqual(v.family, base.family)
    }

    func testSwing062() throws {
        let base = try Composer.compose(hand: "baby", fader: "flare_2c",
                                        division: "1/8", cycles: 4, primitives: primitives())
        let v = base.withSwing(ratio: 0.62)
        XCTAssertEqual(v.record.map { [$0.t, $0.dur] }, [
            [0, 298], [298, 182], [480, 298], [778, 182],
            [960, 298], [1258, 182], [1440, 298], [1738, 182],
        ])
        XCTAssertEqual(Array(v.faderEvents.map(\.t).prefix(7)), [0, 83, 107, 185, 208, 349, 363])
    }
}
