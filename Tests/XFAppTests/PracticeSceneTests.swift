// SPDX-License-Identifier: GPL-3.0-only
import XCTest
import SpriteKit
@testable import XFApp
import XFRender
import XFNotation

/// `PracticeScene`: la escena unica de la practica (autopista + tira de la
/// instrumental + rail del sample en un solo `update(_:)`).
final class PracticeSceneTests: XCTestCase {

    private func babyScratch() throws -> Scratch {
        let c = try CatalogLoader.load(from: RepoContentLoader())
        return try XCTUnwrap(c.library.scratch(id: "baby"))
    }

    private func geometry(width: CGFloat, height: CGFloat) -> HighwayGeometry {
        HighwayGeometry(size: CGSize(width: width, height: height),
                        playheadFraction: 0.30, pixelsPerBeat: 120, beatsPerBar: 4)
    }

    /// El objetivo de ADR-048: la rejilla de compas de la tira de la
    /// instrumental cae EXACTAMENTE sobre la de la autopista. Se comprueba que
    /// `PracticeScene.stripGridXs` produce las mismas X que `HighwayLayout`.
    func testLaRejillaDeLaTiraCaeSobreLaDeLaAutopista() throws {
        let scratch = try babyScratch()
        // la zona de autopista = ancho de vista menos el rail izquierdo (44).
        let g = geometry(width: 900 - 44, height: 600 - 46)
        let layout = HighwayLayout(scratch: scratch)
        let pxPerTick = g.pixelsPerTick(ppq: scratch.ppq)

        for now in stride(from: -1000.0, through: 5000.0, by: 137.0) {
            let frame = layout.frame(atTick: now, geometry: g)
            let expected = (frame.beatLines + frame.barLines).sorted()

            let (beats, bars) = PracticeScene.stripGridXs(
                now: now, width: g.size.width, playheadX: g.playheadX,
                pxPerTick: pxPerTick, ppq: scratch.ppq,
                patternLen: scratch.lengthTicks, beatsPerBar: g.beatsPerBar)
            let got = (beats + bars).sorted()

            XCTAssertEqual(got.count, expected.count, "distinto numero de lineas en now=\(now)")
            for (a, b) in zip(got, expected) {
                XCTAssertEqual(a, b, accuracy: 1e-6, "linea desalineada en now=\(now)")
            }
            // y ademas: los compases de la tira son los compases de la autopista
            XCTAssertEqual(bars.sorted(), frame.barLines.sorted())
        }
    }

    /// La escena traga `update(_:)` a distintos ticks y tamanos sin reventar
    /// (giro del sprite del sample, pools de la autopista, tiling de la tira).
    func testUpdateNoRevientaConImagenesYCambiosDeTamano() throws {
        let scratch = try babyScratch()
        let scene = PracticeScene(size: CGSize(width: 900, height: 600))
        scene.geometry = geometry(width: 900, height: 600)
        scene.patternPPQ = scratch.ppq
        scene.patternLengthTicks = scratch.lengthTicks
        scene.instrumentalLoopTicks = Double(scratch.ppq * 4)
        scene.load(scratch)

        let sr = 48_000.0
        let pcm = (0..<9600).map { Float(0.4 * sin(2 * Double.pi * 220 * Double($0) / sr)) }
        let wave = WaveformColored.build(pcm, sampleRate: sr, buckets: 300)
        scene.instrumentalImage = WaveformImage.render(wave, width: 2000, height: 46)
        scene.sampleImage = WaveformImage.render(wave, width: 2000, height: 44)

        var trace: [TracePoint] = []
        scene.userTrace = { trace }

        for (i, now) in stride(from: 0.0, through: 4000.0, by: 91.0).enumerated() {
            scene.currentTick = { now }
            trace.append(TracePoint(tick: now, position: Double(i % 20) / 20.0))
            if i == 15 { scene.size = CGSize(width: 640, height: 480) }   // dispara didChangeSize
            if i == 30 { scene.size = CGSize(width: 1200, height: 700) }
            scene.ghostDimmed = (i % 7 == 0)
            scene.update(TimeInterval(now))
        }

        // update dejo la zona de autopista = vista menos rail y tira
        XCTAssertEqual(scene.geometry.size.width, 1200 - scene.railWidth, accuracy: 0.5)
        XCTAssertEqual(scene.geometry.size.height, 700 - scene.stripHeight, accuracy: 0.5)
    }

    /// Sin imagenes de onda ni patron cargado, `update` tampoco revienta
    /// (arranque: las ondas llegan tras decodificar el audio, asincrono).
    func testUpdateAntesDeCargarNadaNoRevienta() {
        let scene = PracticeScene(size: CGSize(width: 800, height: 500))
        scene.geometry = geometry(width: 800, height: 500)
        scene.update(0)
        scene.update(1234)
    }
}
