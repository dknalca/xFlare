// SPDX-License-Identifier: GPL-3.0-only
import XCTest
import XFTestKit
@testable import XFNotation

/// B3.3 — la libreria compilada en Swift coincide con `library-v0.1.json`
/// (generada por `tools/xfn_build.py`) sobre los 25 scratches.
///
/// **Metodo de comparacion.** El criterio de TODO.md decia "diff vacio byte a
/// byte", pero **ADR-028 prohibe explicitamente comparar goldens de coma
/// flotante byte a byte** (los ultimos bits difieren legitimamente entre x86_64
/// y arm64). Se compara por tanto **campo a campo**: enteros y enums exactos,
/// dobles redondeados a 4 decimales con tolerancia 1e-9 (los helpers de
/// `XFTestKit.Golden`, definidos justo para esto en B0.8). Ver ADR-032.
final class GoldenLibraryTests: XCTestCase {

    func testLibreriaCompiladaCoincideConLaReferencia() throws {
        let prims = try XFNFixtures.primitives()
        let catalog = try XFNFixtures.catalog()
        let built = try ScratchLibrary.build(catalog: catalog, primitives: prims)
        let reference = try XFNFixtures.referenceLibrary()

        XCTAssertEqual(built.scratches.count, 25)
        XCTAssertEqual(built.scratches.count, reference.scratches.count)

        for ref in reference.scratches {
            guard let got = built.scratch(id: ref.id) else {
                XCTFail("falta el scratch \(ref.id) en la libreria compilada")
                continue
            }
            assertScratchEquivalent(got, ref)
        }
    }

    // MARK: - comparacion campo a campo

    private func assertScratchEquivalent(_ a: Scratch, _ b: Scratch,
                                         file: StaticString = #filePath, line: UInt = #line) {
        let id = b.id
        XCTAssertEqual(a.id, b.id, "id", file: file, line: line)
        XCTAssertEqual(a.name, b.name, "\(id).name", file: file, line: line)
        XCTAssertEqual(a.family, b.family, "\(id).family", file: file, line: line)
        XCTAssertEqual(a.level, b.level, "\(id).level", file: file, line: line)
        XCTAssertEqual(a.hand, b.hand, "\(id).hand", file: file, line: line)
        XCTAssertEqual(a.fader, b.fader, "\(id).fader", file: file, line: line)
        XCTAssertEqual(a.div, b.div, "\(id).div", file: file, line: line)
        XCTAssertEqual(a.cycles, b.cycles, "\(id).cycles", file: file, line: line)
        XCTAssertEqual(a.technique, b.technique, "\(id).technique", file: file, line: line)
        XCTAssertEqual(a.ppq, b.ppq, "\(id).ppq", file: file, line: line)
        XCTAssertEqual(a.bpmReference, b.bpmReference, "\(id).bpmReference", file: file, line: line)
        XCTAssertEqual(a.lengthTicks, b.lengthTicks, "\(id).lengthTicks", file: file, line: line)
        XCTAssertEqual(a.clickCount, b.clickCount, "\(id).clickCount", file: file, line: line)
        XCTAssertEqual(a.notes, b.notes, "\(id).notes", file: file, line: line)

        XCTAssertEqual(a.record.count, b.record.count, "\(id).record.count", file: file, line: line)
        for (i, pair) in zip(a.record, b.record).enumerated() {
            let (x, y) = pair
            XCTAssertEqual(x.t, y.t, "\(id).record[\(i)].t", file: file, line: line)
            XCTAssertEqual(x.dur, y.dur, "\(id).record[\(i)].dur", file: file, line: line)
            XCTAssertEqual(x.dir, y.dir, "\(id).record[\(i)].dir", file: file, line: line)
            XCTAssertEqual(x.curve, y.curve, "\(id).record[\(i)].curve", file: file, line: line)
            XCTAssertTrue(Golden.approxEqual(Golden.round4(x.dist), Golden.round4(y.dist)),
                          "\(id).record[\(i)].dist  \(x.dist) vs \(y.dist)", file: file, line: line)
            XCTAssertTrue(Golden.approxEqual(Golden.round4(x.from), Golden.round4(y.from)),
                          "\(id).record[\(i)].from  \(x.from) vs \(y.from)", file: file, line: line)
            XCTAssertTrue(Golden.approxEqual(Golden.round4(x.to), Golden.round4(y.to)),
                          "\(id).record[\(i)].to  \(x.to) vs \(y.to)", file: file, line: line)
        }

        XCTAssertEqual(a.faderEvents.count, b.faderEvents.count,
                       "\(id).faderEvents.count", file: file, line: line)
        for (i, pair) in zip(a.faderEvents, b.faderEvents).enumerated() {
            let (x, y) = pair
            XCTAssertEqual(x.t, y.t, "\(id).faderEvents[\(i)].t", file: file, line: line)
            XCTAssertEqual(x.state, y.state, "\(id).faderEvents[\(i)].state", file: file, line: line)
        }
    }
}
