// SPDX-License-Identifier: GPL-3.0-only
import XCTest
import SwiftUI
@testable import XFDesign

/// B7.1 / B7.2 — tokens y componentes base.
final class XFDesignTests: XCTestCase {

    func testAPIVersion() {
        XCTAssertEqual(XFDesign.apiVersion, 1)
    }

    // MARK: - color

    func testHexInit() {
        let c = Color(hex: 0x34E1C4)
        // extrae los componentes vía NSColor (macOS)
        let ns = NSColor(c).usingColorSpace(.sRGB)!
        XCTAssertEqual(Double(ns.redComponent),   0x34 / 255.0, accuracy: 0.004)
        XCTAssertEqual(Double(ns.greenComponent), 0xE1 / 255.0, accuracy: 0.004)
        XCTAssertEqual(Double(ns.blueComponent),  0xC4 / 255.0, accuracy: 0.004)
    }

    func testGhostLlevaOpacidad() {
        let ns = NSColor(XFColor.ghost).usingColorSpace(.sRGB)!
        XCTAssertEqual(Double(ns.alphaComponent), 0.35, accuracy: 0.01)
    }

    // MARK: - HitLevel

    func testHitLevelClasificaPorVentana() {
        XCTAssertEqual(HitLevel(absOffsetMs: 0),   .perfect)
        XCTAssertEqual(HitLevel(absOffsetMs: 19),  .perfect)
        XCTAssertEqual(HitLevel(absOffsetMs: 20),  .great)
        XCTAssertEqual(HitLevel(absOffsetMs: 39),  .great)
        XCTAssertEqual(HitLevel(absOffsetMs: 55),  .good)
        XCTAssertEqual(HitLevel(absOffsetMs: 100), .offbeat)
        XCTAssertEqual(HitLevel(absOffsetMs: 200), .miss)
    }

    func testCadaNivelTieneFormaDistinta() {
        let shapes = HitLevel.allCases.map { $0.shape }
        XCTAssertEqual(Set(shapes.map { "\($0)" }).count, HitLevel.allCases.count)
    }

    // MARK: - espaciado

    func testEscalaDeEspaciado() {
        XCTAssertEqual([XFSpacing.xxs, XFSpacing.xs, XFSpacing.sm, XFSpacing.md,
                        XFSpacing.lg, XFSpacing.xl, XFSpacing.xxl],
                       [4, 8, 12, 16, 24, 32, 48])
        XCTAssertEqual(XFRadius.control, 10)
        XCTAssertEqual(XFRadius.card, 16)
        XCTAssertEqual(XFRadius.modal, 24)
    }

    // MARK: - componentes (solo que se construyen; el render necesita host)

    func testComponentesSeConstruyen() {
        _ = XFCard { Text("hola") }
        _ = HitBadge(.perfect, offsetMs: -18)
        _ = BPMStepper(bpm: .constant(90))
        _ = Button("ok") {}.xfButton(.filled)
        _ = Button("no") {}.xfButton(.bordered)
    }
}
