// SPDX-License-Identifier: GPL-3.0-only

import SwiftUI
import SpriteKit
import XFRender
import XFNotation

/// El `SKView` que hospeda `PracticeScene`: autopista + tira de instrumental
/// (arriba) + tira de sample (rail izquierdo) en UNA sola escena, un solo reloj
/// de fotograma. Sustituye al trio `HighwayView` + `InstrumentalStripView` +
/// `WaveformStripView`, que al ir en `SKView` separados se desfasaban al perder
/// un vsync.
struct PracticeSceneView: NSViewRepresentable {

    let scratch: Scratch
    let geometry: HighwayGeometry
    let tick: () -> Double
    let trace: () -> [TracePoint]
    let instrumentalWave: WaveformColored.Data
    let instrumentalLoopTicks: Double
    /// Cabezal de la base como fracción 0…1 del bucle (o < 0 si no hay base). La
    /// tira de la instrumental se dibuja pegada a ESTO, no a un reloj de ticks:
    /// así no se descuadra del audio al cambiar el tempo (TAP, ÷2/×2).
    var instrumentalHeadFraction: () -> Double = { -1 }
    let sampleWave: WaveformColored.Data
    let ghostDimmed: Bool
    /// `false` en Freestyle: sin onda fantasma que seguir.
    var showGhost: Bool = true
    /// Escala vertical de la onda fantasma (slider "Amplitud"). Ver `PracticeScene`.
    let patternAmplitude: CGFloat
    /// Desplazamiento manual de la rejilla en ticks (botones ◀/▶).
    let gridShift: Double
    /// Se llama con el tamaño real de la zona de autopista (para exportar el
    /// vídeo con la proporción de la ventana).
    var onHighwaySize: (CGSize) -> Void = { _ in }
    /// Muestra el overlay de fps (ajuste de diagnóstico, B7.2b).
    var showFPS: Bool = false

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        var scene: PracticeScene?
        var instrWaveCount = -1
        var instrLoopTicks = -1.0
        var sampleWaveCount = -1
        var syncedToScreen = false
    }

    func makeNSView(context: Context) -> SKView {
        let v = SKView()
        // arranca a 60; se ajusta al refresco real cuando la vista tiene ventana
        // (ADR-024: 60 en Intel, 120 si el panel lo da).
        v.preferredFramesPerSecond = 60
        v.ignoresSiblingOrder = true
        let start = CGSize(width: max(1, geometry.size.width),
                           height: max(1, geometry.size.height))
        let scene = PracticeScene(size: start)
        context.coordinator.scene = scene
        configure(scene, coord: context.coordinator)
        v.presentScene(scene)
        return v
    }

    func updateNSView(_ v: SKView, context: Context) {
        guard let scene = context.coordinator.scene else { return }
        if !context.coordinator.syncedToScreen, v.window != nil {
            context.coordinator.syncedToScreen = true
            v.preferredFramesPerSecond = ScreenRefresh.fps(for: v.window)
        }
        configure(scene, coord: context.coordinator)
    }

    private func configure(_ s: PracticeScene, coord: Coordinator) {
        s.currentTick = tick
        s.userTrace = trace
        s.instrumentalHeadFraction = instrumentalHeadFraction
        s.ghostDimmed = ghostDimmed
        s.showGhost = showGhost
        s.patternAmplitude = patternAmplitude
        s.gridShift = gridShift
        s.geometry = geometry            // `size` lo sobrescribe la escena
        s.onHighwaySize = onHighwaySize
        s.showFPS = showFPS
        s.patternPPQ = scratch.ppq
        s.patternLengthTicks = max(1, scratch.lengthTicks)
        s.instrumentalLoopTicks = max(1, instrumentalLoopTicks)
        s.load(scratch)

        // La imagen de la instrumental se rehace solo si cambia la onda o su
        // longitud de bucle. El ancho natural puede ser decenas de miles de px;
        // el maximo de textura de Metal en la GPU de referencia es 16384, se
        // renderiza a <=16000 y el sprite la escala (filtrado lineal).
        if coord.instrWaveCount != instrumentalWave.levels.count
            || coord.instrLoopTicks != instrumentalLoopTicks {
            coord.instrWaveCount = instrumentalWave.levels.count
            coord.instrLoopTicks = instrumentalLoopTicks
            let pxPerTick = geometry.pixelsPerBeat / CGFloat(max(1, scratch.ppq))
            let natural = Int((CGFloat(max(1, instrumentalLoopTicks)) * pxPerTick).rounded())
            let w = min(16_000, max(1, natural))
            s.instrumentalImage = WaveformImage.render(
                instrumentalWave, width: w, height: Int(s.stripHeight))
        }

        if coord.sampleWaveCount != sampleWave.levels.count {
            coord.sampleWaveCount = sampleWave.levels.count
            // se renderiza horizontal (x = tiempo) y la escena la gira 90º.
            s.sampleImage = WaveformImage.render(
                sampleWave, width: 4000, height: Int(s.railWidth))
        }
    }
}
