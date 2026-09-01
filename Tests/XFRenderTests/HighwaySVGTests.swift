// SPDX-License-Identifier: GPL-3.0-only
import XCTest
import CoreGraphics
@testable import XFRender

/// B7.6 — serializador SVG (estructura y determinismo). Los golden de los 25
/// scratches están en `GoldenHighwayTests`.
final class HighwaySVGTests: XCTestCase {

    private let geo = HighwayGeometry(size: CGSize(width: 400, height: 200),
                                      playheadFraction: 0.25, pixelsPerBeat: 80,
                                      laneHeight: 20, curveInset: 10)

    private func sampleFrame() throws -> HighwayFrame {
        try HighwayLayout(scratch: RenderFixtures.forwardCut()).frame(atTick: 0, geometry: geo)
    }

    func testDocumentoBienFormado() throws {
        let svg = HighwaySVG.document(try sampleFrame(), geometry: geo)
        XCTAssertTrue(svg.hasPrefix("<svg xmlns=\"http://www.w3.org/2000/svg\""))
        XCTAssertTrue(svg.hasSuffix("</svg>\n"))
        XCTAssertTrue(svg.contains(#"viewBox="0 0 400.0000 200.0000""#))
        XCTAssertTrue(svg.contains(#"class="playhead""#))
        XCTAssertTrue(svg.contains(#"class="ghost""#))
    }

    func testEsDeterminista() throws {
        let f = try sampleFrame()
        XCTAssertEqual(HighwaySVG.document(f, geometry: geo),
                       HighwaySVG.document(f, geometry: geo))
    }

    func testCoordenadasDeLaCurvaCon4Decimales() throws {
        let svg = HighwaySVG.document(try sampleFrame(), geometry: geo)

        // cada valor del atributo points="x,y x,y ..." tiene la forma -?ddd.dddd
        guard let r = svg.range(of: #"points="[^"]*""#, options: .regularExpression) else {
            return XCTFail("no hay atributo points")
        }
        let inside = svg[r].dropFirst("points=\"".count).dropLast()
        let coords = inside.split(whereSeparator: { $0 == " " || $0 == "," })
        XCTAssertGreaterThan(coords.count, 10)
        for c in coords {
            XCTAssertNotNil(c.range(of: #"^-?\d+\.\d{4}$"#, options: .regularExpression),
                            "coordenada mal formateada: \(c)")
        }
    }

    func testCabezaDeLecturaEnSuSitio() throws {
        let svg = HighwaySVG.document(try sampleFrame(), geometry: geo)
        // playheadX = 400 * 0.25 = 100
        XCTAssertTrue(svg.contains(#"x1="100.0000" y1="0" x2="100.0000""#))
    }
}
