// SPDX-License-Identifier: GPL-3.0-only

import SpriteKit

/// La escena SpriteKit del scope circular. Delgada, como `HighwayScene`: la
/// geometría la calcula `ScopeLayout`; esto la pinta y reutiliza nodos.
///
/// `readings` es la fuente de datos: la inyecta `XFApp` con un búfer de las
/// últimas lecturas del plato. SpriteKit llama a `update(_:)` al refresco real.
public final class ScopeScene: SKScene {

    public var readings: () -> [ScopeReading] = { [] }

    private let layout = ScopeLayout()
    private var geometry: ScopeGeometry

    private let ringNode = SKShapeNode()
    private let radialNode = SKShapeNode()
    private let trailNode = SKShapeNode()
    private let dotNode = SKShapeNode()

    private let idleColor = SKColor(red: 0x7A/255, green: 0x87/255, blue: 0x94/255, alpha: 0.35)
    private let liveColor = SKColor(red: 0x34/255, green: 0xE1/255, blue: 0xC4/255, alpha: 1.0)
    private let warnColor = SKColor(red: 0xFF/255, green: 0x4D/255, blue: 0x5E/255, alpha: 1.0)

    public init(geometry: ScopeGeometry) {
        self.geometry = geometry
        super.init(size: geometry.size)
        scaleMode = .resizeFill
        backgroundColor = SKColor(red: 0x0B/255, green: 0x0D/255, blue: 0x10/255, alpha: 1)

        ringNode.strokeColor = idleColor
        ringNode.lineWidth = 1
        radialNode.strokeColor = idleColor
        radialNode.lineWidth = 1
        trailNode.lineWidth = 2
        trailNode.lineJoin = .round
        dotNode.lineWidth = 0

        addChild(ringNode)
        addChild(radialNode)
        addChild(trailNode)
        addChild(dotNode)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("ScopeScene se crea en código") }

    public override func didChangeSize(_ oldSize: CGSize) {
        super.didChangeSize(oldSize)
        geometry.size = size
    }

    public override func update(_ currentTime: TimeInterval) {
        render(layout.figure(readings: readings(), geometry: geometry))
    }

    private func render(_ figure: ScopeFigure) {
        let accent = figure.isDegraded ? warnColor : liveColor

        ringNode.path = CGPath(ellipseIn: CGRect(
            x: figure.center.x - figure.referenceRadius,
            y: figure.center.y - figure.referenceRadius,
            width: figure.referenceRadius * 2, height: figure.referenceRadius * 2), transform: nil)

        let radial = CGMutablePath()
        radial.move(to: figure.center)
        radial.addLine(to: figure.dot)
        radialNode.path = radial
        radialNode.strokeColor = accent.withAlphaComponent(0.5)

        if figure.trail.count >= 2 {
            let path = CGMutablePath()
            path.addLines(between: figure.trail)
            trailNode.path = path
        } else {
            trailNode.path = nil
        }
        trailNode.strokeColor = accent.withAlphaComponent(0.6)

        dotNode.path = CGPath(ellipseIn: CGRect(x: -4, y: -4, width: 8, height: 8), transform: nil)
        dotNode.position = figure.dot
        dotNode.fillColor = accent
    }
}
