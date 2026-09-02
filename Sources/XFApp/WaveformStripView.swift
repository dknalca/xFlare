// SPDX-License-Identifier: GPL-3.0-only

import SwiftUI
import SpriteKit

/// Tira **inferior**: forma de onda del sample de scratch (con color por
/// frecuencia). Se desplaza bajo una aguja fija a `needleFraction` del ancho,
/// siguiendo `progress` (0…1 sobre el sample). `SKView` con `WaveformScene` en
/// modo `.windowed`, mismo reloj de frame que la autopista → sin tirones.
struct WaveformStripView: NSViewRepresentable {

    let wave: WaveformColored.Data
    let progress: () -> Double
    var visibleFraction: Double = 0.5
    var needleFraction: Double = 0.30

    static let imageWidth = 6000
    static let height: CGFloat = 54

    func makeCoordinator() -> Coordinator { Coordinator() }
    final class Coordinator { var scene: WaveformScene?; var waveCount = -1 }

    func makeNSView(context: Context) -> SKView {
        let v = SKView()
        v.preferredFramesPerSecond = 120
        v.ignoresSiblingOrder = true
        let scene = WaveformScene(size: CGSize(width: 1000, height: Self.height))
        scene.mode = .windowed
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
        s.progress = progress
        s.visibleFraction = CGFloat(min(1, max(0.05, visibleFraction)))
        s.needleFraction = CGFloat(min(0.9, max(0.05, needleFraction)))
        if coord.waveCount != wave.levels.count {
            coord.waveCount = wave.levels.count
            s.image = WaveformImage.render(wave, width: Self.imageWidth, height: Int(Self.height))
        }
    }
}
