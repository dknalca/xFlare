// SPDX-License-Identifier: GPL-3.0-only
import XCTest
@testable import XFApp

final class SampleEditTests: XCTestCase {

    func testAcotaAlaVentanaDeScratch() {
        let e = SampleEdit(startSeconds: -3, lengthSeconds: 999)
        XCTAssertEqual(e.startSeconds, 0)
        XCTAssertEqual(e.lengthSeconds, AudioAsset.scratchMaxSeconds, accuracy: 1e-9)
        let tiny = SampleEdit(startSeconds: 1, lengthSeconds: 0.001)
        XCTAssertEqual(tiny.lengthSeconds, 0.05, accuracy: 1e-9, "mínimo 50 ms")
        XCTAssertEqual(tiny.endSeconds, 1.05, accuracy: 1e-9)
    }

    func testIsDefault() {
        XCTAssertTrue(SampleEdit().isDefault)
        XCTAssertFalse(SampleEdit(startSeconds: 0.4).isDefault)
        XCTAssertFalse(SampleEdit(lengthSeconds: 1.0).isDefault)
    }

    func testFrameRange() throws {
        let sr = 48_000.0
        let e = SampleEdit(startSeconds: 0.5, lengthSeconds: 1.0)
        let r = try XCTUnwrap(e.frameRange(frameCount: 48_000 * 3, sampleRate: sr))
        XCTAssertEqual(r.lowerBound, 24_000)
        XCTAssertEqual(r.upperBound, 72_000)
        // sample más corto que el inicio -> se acota (no revienta)
        XCTAssertNil(e.frameRange(frameCount: 100, sampleRate: sr))
    }

    func testStoreIdaYVuelta() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("sedits-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }

        let store = SampleEditStore(fileURL: url)
        store.set(SampleEdit(startSeconds: 0.75, lengthSeconds: 1.2), for: "/s/ahh.wav")
        store.set(SampleEdit(), for: "/s/def.wav")                 // por defecto -> no se guarda

        let back = SampleEditStore(fileURL: url)
        let e = try XCTUnwrap(back.edit(for: "/s/ahh.wav"))
        XCTAssertEqual(e.startSeconds, 0.75, accuracy: 1e-9)
        XCTAssertEqual(e.lengthSeconds, 1.2, accuracy: 1e-9)
        XCTAssertNil(back.edit(for: "/s/def.wav"))
    }
}
