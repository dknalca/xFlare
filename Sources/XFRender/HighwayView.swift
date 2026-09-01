// SPDX-License-Identifier: GPL-3.0-only

import SwiftUI
import SpriteKit
import XFNotation

/// La autopista lista para meter en una pantalla de SwiftUI. Envuelve un `SKView`
/// con la `HighwayScene`.
///
/// `tick` es la fuente del tiempo: una función que devuelve el tick musical
/// actual leyendo el reloj de AUDIO (la prepara `XFApp` a partir de `XFClock` /
/// el transporte). El `SKView` redibuja al refresco real de la pantalla; el
/// contenido de cada fotograma sale de `tick()`, así que no hay deriva.
public struct HighwayView: NSViewRepresentable {

    private let scratch: Scratch
    private let geometry: HighwayGeometry
    private let tick: () -> Double
    private let userTrace: () -> [TracePoint]
    private let clickHits: () -> [ClickHit]

    public init(scratch: Scratch,
                geometry: HighwayGeometry,
                tick: @escaping () -> Double,
                userTrace: @escaping () -> [TracePoint] = { [] },
                clickHits: @escaping () -> [ClickHit] = { [] }) {
        self.scratch = scratch
        self.geometry = geometry
        self.tick = tick
        self.userTrace = userTrace
        self.clickHits = clickHits
    }

    public func makeNSView(context: Context) -> SKView {
        let view = SKView()
        view.preferredFramesPerSecond = 120   // SpriteKit lo capa al refresco real
        view.ignoresSiblingOrder = true

        let scene = HighwayScene(geometry: geometry)
        scene.currentTick = tick
        scene.userTrace = userTrace
        scene.clickHits = clickHits
        scene.load(scratch)
        context.coordinator.scene = scene
        context.coordinator.loadedId = scratch.id
        view.presentScene(scene)
        return view
    }

    public func updateNSView(_ view: SKView, context: Context) {
        let scene = context.coordinator.scene
        scene?.currentTick = tick
        scene?.userTrace = userTrace
        scene?.clickHits = clickHits
        if context.coordinator.loadedId != scratch.id {
            scene?.load(scratch)
            context.coordinator.loadedId = scratch.id
        }
    }

    public func makeCoordinator() -> Coordinator { Coordinator() }

    public final class Coordinator {
        var scene: HighwayScene?
        var loadedId: String?
    }
}
