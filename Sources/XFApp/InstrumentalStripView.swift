// SPDX-License-Identifier: GPL-3.0-only

import SwiftUI
import SpriteKit
import XFRender

/// Tira **superior**: onda de la instrumental (en bucle, con color por
/// frecuencia) + rejilla de compás/negra. Es un `SKView` con `WaveformScene` en
/// modo `.looping`, así comparte el reloj de frame de `HighwayScene` y la
/// rejilla cae en la MISMA X que la de la autopista.
struct InstrumentalStripView: NSViewRepresentable {

    let wave: WaveformColored.Data
    let loopTicks: Double
    let geometry: HighwayGeometry
    let ppq: Int
    let patternLengthTicks: Int
    let tick: () -> Double

    static let height: CGFloat = 46

    func makeCoordinator() -> Coordinator { Coordinator() }
    final class Coordinator { var scene: WaveformScene?; var waveCount = -1 }

    func makeNSView(context: Context) -> SKView {
        let v = SKView()
        v.preferredFramesPerSecond = 120
        v.ignoresSiblingOrder = true
        let scene = WaveformScene(size: CGSize(width: max(1, geometry.size.width),
                                               height: Self.height))
        scene.mode = .looping
        context.coordinator.scene = scene
        configure(scene, coord: context.coordinator)
        v.presentScene(scene)
        return v
    }

    func updateNSView(_ v: SKView, context: Context) {
        guard let scene = context.coordinator.scene else { return }
        configure(scene, coord: context.coordinator)
    }

    private func configure(_ s: WaveformScene, coord: Coordinator) {
        s.loopTicks = max(1, loopTicks)
        s.ppq = max(1, ppq)
        s.patternLen = max(1, patternLengthTicks)
        s.beatsPerBar = geometry.beatsPerBar
        s.pixelsPerBeat = geometry.pixelsPerBeat
        s.playheadFraction = geometry.playheadFraction
        s.currentTick = tick

        if coord.waveCount != wave.levels.count {
            coord.waveCount = wave.levels.count
            let pxPerTick = geometry.pixelsPerBeat / CGFloat(max(1, ppq))
            let w = min(80_000, max(1, Int((CGFloat(loopTicks) * pxPerTick).rounded())))
            s.image = WaveformImage.render(wave, width: w, height: Int(Self.height))
        }
    }
}
