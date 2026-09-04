// SPDX-License-Identifier: GPL-3.0-only
import XCTest
@testable import XFApp

final class InstrumentalEditTests: XCTestCase {

    func testNormalizaAlConstruir() {
        let e = InstrumentalEdit(
            bpm: 1_000, downbeatSeconds: -5, beatsPerBar: 99,
            cues: [.init(name: "B", atSeconds: 8), .init(name: "A", atSeconds: 2)],
            loops: [.init(name: "x", startSeconds: 10, endSeconds: 4)])
        XCTAssertEqual(e.bpm, 300, "BPM acotado")
        XCTAssertEqual(e.downbeatSeconds, 0, "no negativo")
        XCTAssertEqual(e.beatsPerBar, 12, "acotado")
        XCTAssertEqual(e.cues.map(\.name), ["A", "B"], "cues ordenados por tiempo")
        XCTAssertEqual(e.loops[0].startSeconds, 4, "región: inicio < fin")
        XCTAssertEqual(e.loops[0].endSeconds, 10)
    }

    func testRegionActivaTieneQueExistir() {
        let l = InstrumentalEdit.LoopRegion(name: "a", startSeconds: 0, endSeconds: 4)
        let ok = InstrumentalEdit(loops: [l], activeLoopID: l.id)
        XCTAssertEqual(ok.activeLoop?.id, l.id)
        let bad = InstrumentalEdit(loops: [l], activeLoopID: UUID())
        XCTAssertNil(bad.activeLoop, "un id que no está en loops se ignora")
    }

    func testIsEmpty() {
        XCTAssertTrue(InstrumentalEdit().isEmpty)
        XCTAssertFalse(InstrumentalEdit(bpm: 120).isEmpty)
        XCTAssertFalse(InstrumentalEdit(cues: [.init(name: "a", atSeconds: 1)]).isEmpty)
    }

    // MARK: - store

    private func tempStore() -> (InstrumentalEditStore, URL) {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("edits-\(UUID().uuidString).json")
        return (InstrumentalEditStore(fileURL: url), url)
    }

    func testGuardaYReleePorFichero() {
        let (store, url) = tempStore()
        defer { try? FileManager.default.removeItem(at: url) }

        var e = InstrumentalEdit(bpm: 92.5, downbeatSeconds: 0.35, beatsPerBar: 4)
        e.cues = [.init(name: "estrofa", atSeconds: 12.4)]
        store.set(e, for: "/m/beat.wav")

        let reread = InstrumentalEditStore(fileURL: url)
        let back = reread.edit(for: "/m/beat.wav")
        XCTAssertEqual(back?.bpm, 92.5)
        XCTAssertEqual(back?.downbeatSeconds, 0.35)
        XCTAssertEqual(back?.cues.first?.name, "estrofa")
        XCTAssertNil(reread.edit(for: "/otro.wav"))
    }

    func testGuardarVacioLoBorra() {
        let (store, url) = tempStore()
        defer { try? FileManager.default.removeItem(at: url) }
        store.set(InstrumentalEdit(bpm: 100), for: "/x.wav")
        XCTAssertNotNil(store.edit(for: "/x.wav"))
        store.set(InstrumentalEdit(), for: "/x.wav")   // vacío -> se borra
        XCTAssertNil(store.edit(for: "/x.wav"))
    }
}
