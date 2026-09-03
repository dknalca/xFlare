// SPDX-License-Identifier: GPL-3.0-only
import XCTest
import Foundation
import AVFoundation
import CoreGraphics
@testable import XFApp
import XFRender
import XFNotation
import XFCapture
import XFPrimitives
import XFClock

/// F.4 — exportar la toma como vídeo vertical. Lo puro (plan de fotogramas,
/// traza, rasterizado) se prueba a fondo; el `AVAssetWriter` con un export
/// pequeño de verdad a un fichero temporal.
final class TakeVideoExporterTests: XCTestCase {

    private func babyScratch() throws -> Scratch {
        let cat = try CatalogLoader.load(from: RepoContentLoader())
        return try XCTUnwrap(cat.library.scratch(id: "baby"))
    }

    private func geometry() -> HighwayGeometry {
        HighwayGeometry(size: CGSize(width: 1000, height: 380))
    }

    /// Toma sintética: `n` muestras de movimiento repartidas en `seconds`.
    private func fakeSession(n: Int = 60, seconds: Double = 2, bpm: Double = 120) -> XFSession {
        // hostNumer/hostDenom = 1/1 -> nanosegundos == host-ticks
        let nsSpan = seconds * 1_000_000_000
        var motion: [MotionSample] = []
        for i in 0..<n {
            let t = UInt64(Double(i) / Double(max(1, n - 1)) * nsSpan)
            let pos = 0.5 + 0.4 * sin(Double(i) * 0.3)
            motion.append(MotionSample(hostTime: t, position: pos, velocity: 0, confidence: 1))
        }
        let fader = [FaderSample(hostTime: 0, value: 1, isOpen: true)]
        let header = XFSession.Header(formatVersion: 1, tempoBPM: bpm,
                                      anchorHostTime: 0, anchorTick: 0,
                                      hostNumer: 1, hostDenom: 1, notes: "test")
        return XFSession(header: header, motion: motion, fader: fader)
    }

    func testFramePlanCubreLaDuracionYEsMonotono() {
        let plan = TakeVideoExporter.framePlan(lengthTicks: 1920, bpm: 120, ppq: 480,
                                               fps: 30, leadOutTicks: 480)
        // 2400 ticks a 120bpm/480ppq = 960 t/s -> 2,5 s -> ~75 fotogramas
        XCTAssertGreaterThanOrEqual(plan.count, 75)
        XCTAssertEqual(plan.first, 0)
        XCTAssertEqual(plan.last!, 2400, accuracy: 1e-6)
        XCTAssertEqual(zip(plan, plan.dropFirst()).allSatisfy { $1 > $0 }, true)
    }

    func testTraceVaEnTicksCrecientesYRespetaLaPosicion() {
        let s = fakeSession(n: 20, seconds: 1, bpm: 120)
        let tr = TakeVideoExporter.trace(from: s, ppq: 480)
        XCTAssertEqual(tr.count, 20)
        XCTAssertEqual(tr.first?.tick, 0)
        XCTAssertEqual(zip(tr, tr.dropFirst()).allSatisfy { $1.tick > $0.tick }, true)
        // 1 s a 120 bpm / 480 ppq = 960 ticks
        XCTAssertEqual(tr.last!.tick, 960, accuracy: 5)
        XCTAssertEqual(tr[10].position, s.motion[10].position, accuracy: 1e-9)
    }

    func testRenderDaUnBitmapDelTamanoPedidoYNoEnBlanco() throws {
        let sc = try babyScratch()
        let g = geometry()
        let frame = HighwayLayout(scratch: sc).frame(
            atTick: 240, geometry: g,
            userTrace: [TracePoint(tick: 200, position: 0.3),
                        TracePoint(tick: 260, position: 0.8)])
        let px = CGSize(width: 216, height: 384)   // 1/5 de 1080x1920 ~ 9:16 sobre 1000x380
        let img = try XCTUnwrap(TakeVideoExporter.render(frame, geometry: g, pixelSize: px))
        XCTAssertEqual(img.width, 216)
        XCTAssertEqual(img.height, 384)
        XCTAssertTrue(hasNonBackgroundPixels(img), "el rasterizado debe pintar algo")
    }

    func testExportProduceUnMp4ConPistaDeVideo() throws {
        let sc = try babyScratch()
        let s = fakeSession(n: 40, seconds: 1.2, bpm: 120)
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("xflare-take-\(UUID().uuidString).mp4")
        defer { try? FileManager.default.removeItem(at: url) }

        var opts = TakeVideoExporter.Options()
        opts.width = 270; opts.height = 480; opts.fps = 15   // pequeño para el test

        let done = expectation(description: "export")
        var result: Result<URL, Error>?
        TakeVideoExporter.export(session: s, scratch: sc, geometry: geometry(),
                                 options: opts, to: url) { r in result = r; done.fulfill() }
        wait(for: [done], timeout: 30)

        switch result {
        case .success(let out):
            XCTAssertTrue(FileManager.default.fileExists(atPath: out.path))
            let attrs = try FileManager.default.attributesOfItem(atPath: out.path)
            XCTAssertGreaterThan((attrs[.size] as? Int) ?? 0, 1000, "el mp4 no está vacío")
            let asset = AVURLAsset(url: out)
            let track = try XCTUnwrap(asset.tracks(withMediaType: .video).first)
            XCTAssertEqual(track.naturalSize.width, 270, accuracy: 1)
            XCTAssertEqual(track.naturalSize.height, 480, accuracy: 1)
            XCTAssertGreaterThan(asset.duration.seconds, 0.5)
        case .failure(let e):
            XCTFail("export falló: \(e)")
        case .none:
            XCTFail("sin resultado")
        }
    }

    func testSesionVaciaDaError() throws {
        let sc = try babyScratch()
        let empty = XFSession(header: .init(formatVersion: 1, tempoBPM: 120,
                                            anchorHostTime: 0, anchorTick: 0,
                                            hostNumer: 1, hostDenom: 1, notes: ""),
                              motion: [], fader: [])
        let done = expectation(description: "err")
        TakeVideoExporter.export(session: empty, scratch: sc, geometry: geometry(),
                                 to: URL(fileURLWithPath: "/tmp/none.mp4")) { r in
            if case .failure = r { done.fulfill() }
        }
        wait(for: [done], timeout: 5)
    }

    // MARK: - helpers

    private func hasNonBackgroundPixels(_ img: CGImage) -> Bool {
        guard let data = img.dataProvider?.data,
              let ptr = CFDataGetBytePtr(data) else { return false }
        let n = CFDataGetLength(data)
        // el fondo es 0x0B0D10; si algún píxel se sale de ~ese valor, se pintó algo
        var i = 0
        while i + 3 < n {
            let r = ptr[i], gg = ptr[i + 1], b = ptr[i + 2]
            if abs(Int(r) - 0x0B) > 12 || abs(Int(gg) - 0x0D) > 12 || abs(Int(b) - 0x10) > 12 {
                return true
            }
            i += 4 * 97   // muestrea, no hace falta recorrerlo entero
        }
        return false
    }
}
