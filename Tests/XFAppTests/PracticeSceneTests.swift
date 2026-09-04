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

    /// La rejilla de `PracticeScene` (tira + autopista, una sola capa): una
    /// linea por negra, X = `playheadX + (b·ppq - now)·pxPerTick`, y compas cada
    /// `beatsPerBar` negras contando desde el "1" absoluto (tick 0). Regular
    /// aunque el patron no mida un numero entero de compases.
    func testLaRejillaEsRegularYPorNegraAbsoluta() throws {
        let g = geometry(width: 900 - 44, height: 600 - 46)
        let ppq = 480
        let pxPerTick = g.pixelsPerTick(ppq: ppq)
        let barPx = pxPerTick * CGFloat(ppq * g.beatsPerBar)

        for now in stride(from: -1000.0, through: 5000.0, by: 133.0) {
            let (beats, bars) = PracticeScene.gridLines(
                now: now, width: g.size.width, playheadX: g.playheadX,
                pxPerTick: pxPerTick, ppq: ppq, beatsPerBar: g.beatsPerBar)

            // toda linea cae en una negra exacta respecto al cabezal
            for x in beats + bars {
                let tick = Double(now) + Double((x - g.playheadX) / pxPerTick)
                XCTAssertEqual(tick / Double(ppq), (tick / Double(ppq)).rounded(), accuracy: 1e-6)
            }
            // los compases van EXACTAMENTE a distancia de un compas
            let sortedBars = bars.sorted()
            for (a, b) in zip(sortedBars, sortedBars.dropFirst()) {
                XCTAssertEqual(b - a, barPx, accuracy: 1e-6, "compases no regulares en now=\(now)")
            }
            // 1 de cada `beatsPerBar` lineas es de compas
            XCTAssertEqual(bars.count + beats.count > 0, true)
            XCTAssertLessThanOrEqual(abs((beats.count + bars.count) - bars.count * g.beatsPerBar), g.beatsPerBar)
        }
    }

    /// Las etiquetas "compás.subdivisión" van 1.1, 1.2, …, y saltan a 2.1 tras
    /// `beatsPerBar` negras. No se etiqueta antes del "1" (negras < 0).
    func testEtiquetasDeCompasYSubdivision() throws {
        let g = geometry(width: 900 - 44, height: 600 - 46)
        let ppq = 480

        // en now = 0 el cabezal está en el tick 0: la primera etiqueta es "1.1".
        let l0 = PracticeScene.gridLabels(
            now: 0, width: g.size.width, playheadX: g.playheadX,
            pxPerTick: g.pixelsPerTick(ppq: ppq), ppq: ppq, beatsPerBar: 4)
        XCTAssertEqual(l0.first?.text, "1.1")
        XCTAssertEqual(Set(l0.map(\.text)).isSuperset(of: ["1.1", "1.2", "1.3", "1.4", "2.1"]), true)

        // muy atrás en el tiempo (todo negras negativas) -> sin etiquetas
        let lNeg = PracticeScene.gridLabels(
            now: -10_000, width: g.size.width, playheadX: g.playheadX,
            pxPerTick: g.pixelsPerTick(ppq: ppq), ppq: ppq, beatsPerBar: 4)
        XCTAssertTrue(lNeg.isEmpty)
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
            // alterna tramos con y sin fader cerrado (.miss) para ejercitar el
            // troceado de la traza en runs (pintado sin arrays intermedios).
            trace.append(TracePoint(tick: now, position: Double(i % 20) / 20.0,
                                    level: (i / 3) % 2 == 0 ? nil : .miss))
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
