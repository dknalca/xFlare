// SPDX-License-Identifier: GPL-3.0-only

import SwiftUI
import SpriteKit

/// El scope circular listo para una pantalla de SwiftUI. Envuelve un `SKView`
/// con la `ScopeScene`. `readings` es un búfer de las últimas lecturas del plato
/// (de la más vieja a la más nueva) que prepara `XFApp`.
public struct ScopeView: NSViewRepresentable {

    private let geometry: ScopeGeometry
    private let readings: () -> [ScopeReading]

    public init(geometry: ScopeGeometry, readings: @escaping () -> [ScopeReading]) {
        self.geometry = geometry
        self.readings = readings
    }

    public func makeNSView(context: Context) -> SKView {
        let view = SKView()
        view.preferredFramesPerSecond = 120
        let scene = ScopeScene(geometry: geometry)
        scene.readings = readings
        context.coordinator.scene = scene
        view.presentScene(scene)
        return view
    }

    public func updateNSView(_ view: SKView, context: Context) {
        context.coordinator.scene?.readings = readings
    }

    public func makeCoordinator() -> Coordinator { Coordinator() }

    public final class Coordinator {
        var scene: ScopeScene?
    }
}
