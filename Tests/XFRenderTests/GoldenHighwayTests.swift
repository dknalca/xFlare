// SPDX-License-Identifier: GPL-3.0-only
import XCTest
import CoreGraphics
@testable import XFRender
import XFNotation

/// B7.6 — golden tests de render: los 25 scratches de la librería, dibujados a
/// SVG, contra `Fixtures/golden/highway/`.
///
/// Regenerar: `make golden-update` (pone `XF_GOLDEN_UPDATE=1`). REVISA EL DIFF.
final class GoldenHighwayTests: XCTestCase {

    /// Encuadre fijo del golden: no cambiarlo sin regenerar los 25.
    private let geo = HighwayGeometry(
        size: CGSize(width: 1200, height: 360),
        playheadFraction: 0.30, pixelsPerBeat: 96, laneHeight: 36, curveInset: 12)

    func testGoldenAutopistaDeLos25Scratches() throws {
        let update = ProcessInfo.processInfo.environment["XF_GOLDEN_UPDATE"] == "1"
        let dir = RenderFixtures.repoRoot
            .appendingPathComponent("Fixtures/golden/highway", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let scratches = try RenderFixtures.library().scratches
        XCTAssertGreaterThanOrEqual(scratches.count, 25, "la librería debería traer 25")

        var mismatches: [String] = []
        for scratch in scratches {
            let svg = HighwaySVG.document(
                HighwayLayout(scratch: scratch).frame(atTick: 0, geometry: geo),
                geometry: geo)
            let file = dir.appendingPathComponent("\(scratch.id).svg")

            if update {
                try svg.write(to: file, atomically: true, encoding: .utf8)
            } else if let golden = try? String(contentsOf: file, encoding: .utf8) {
                if golden != svg { mismatches.append(scratch.id) }
            } else {
                mismatches.append("\(scratch.id) (falta el golden)")
            }
        }

        if update {
            print("Goldens de autopista regenerados: \(scratches.count) en \(dir.path)")
        } else {
            XCTAssertTrue(mismatches.isEmpty,
                          "SVG distinto del golden en: \(mismatches.joined(separator: ", ")). "
                          + "Si el cambio es esperado: `make golden-update`.")
        }
    }
}
