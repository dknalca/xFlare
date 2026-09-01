// SPDX-License-Identifier: GPL-3.0-only

import SpriteKit
import XFDesign
import XFNotation

/// La escena SpriteKit de la autopista. **Delgada a propósito**: toda la
/// geometría la calcula `HighwayLayout` (puro, testeable); esto solo la pinta y
/// reutiliza nodos para no reservar memoria en cada fotograma.
///
/// Sincronización (B7.2b / B7.3): SpriteKit llama a `update(_:)` al ritmo del
/// **refresco real** de la pantalla (60 en Intel, 120 en ProMotion). Nosotros
/// leemos ahí el **reloj de AUDIO** vía `currentTick` y dibujamos ese instante.
/// Como la posición sale siempre del reloj de audio y nunca de un contador
/// propio, la autopista no deriva por muchas horas que pase.
public final class HighwayScene: SKScene {

    /// Fuente del tick musical actual. La inyecta `XFApp` leyendo `XFClock` /
    /// el transporte, que a su vez va con el reloj de audio.
    public var currentTick: () -> Double = { 0 }

    /// Traza del disco del usuario (capa de acento). La inyecta `XFApp` con lo
    /// que va capturando. Vacía = solo se ve el fantasma.
    public var userTrace: () -> [TracePoint] = { [] }

    /// Resultado del usuario en cada click, para las marcas teñidas.
    public var clickHits: () -> [ClickHit] = { [] }

    private var layout: HighwayLayout?
    private var geometry: HighwayGeometry

    // Nodos reutilizados fotograma a fotograma.
    private let curveNode = SKShapeNode()
    private let playheadNode = SKShapeNode()
    private let laneLayer = SKNode()
    private let marksLayer = SKNode()
    private let userLayer = SKNode()
    private let hitLayer = SKNode()
    private var bandPool: [SKShapeNode] = []
    private var markPool: [SKShapeNode] = []
    private var userPool: [SKShapeNode] = []
    private var hitPool: [SKShapeNode] = []

    // Paleta (docs/UI_DESIGN.md §2). XFDesign es SwiftUI; aquí usamos SKColor.
    private let ghostColor = SKColor(red: 0x7A/255, green: 0x87/255, blue: 0x94/255, alpha: 0.55)
    private let openColor  = SKColor(red: 0x7A/255, green: 0x87/255, blue: 0x94/255, alpha: 0.9)
    private let closeColor = SKColor(red: 0x34/255, green: 0xE1/255, blue: 0xC4/255, alpha: 1.0)
    private let accentColor = SKColor(red: 0x34/255, green: 0xE1/255, blue: 0xC4/255, alpha: 1.0)
    private let playheadColor = SKColor(red: 0x3A/255, green: 0x44/255, blue: 0x4F/255, alpha: 1.0)
    private let laneOpenColor = SKColor(red: 0xF2/255, green: 0xF5/255, blue: 0xF7/255, alpha: 0.10)

    public init(geometry: HighwayGeometry) {
        self.geometry = geometry
        super.init(size: geometry.size)
        scaleMode = .resizeFill
        backgroundColor = SKColor(red: 0x0B/255, green: 0x0D/255, blue: 0x10/255, alpha: 1)

        curveNode.strokeColor = ghostColor
        curveNode.lineWidth = 3
        curveNode.lineJoin = .round
        playheadNode.strokeColor = playheadColor
        playheadNode.lineWidth = 1

        addChild(laneLayer)
        addChild(curveNode)      // fantasma detrás
        addChild(userLayer)      // tu curva delante
        addChild(marksLayer)
        addChild(hitLayer)
        addChild(playheadNode)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("HighwayScene se crea en código, no desde un .sks") }

    /// Carga el patrón a mostrar. Recalcula el rango vertical una sola vez.
    public func load(_ scratch: Scratch) {
        layout = HighwayLayout(scratch: scratch)
    }

    public override func didChangeSize(_ oldSize: CGSize) {
        super.didChangeSize(oldSize)
        geometry.size = size
    }

    public override func update(_ currentTime: TimeInterval) {
        guard let layout else { return }
        render(layout.frame(atTick: currentTick(), geometry: geometry,
                            userTrace: userTrace(), clickHits: clickHits()))
    }

    /// Color de un nivel de acierto. `nil` (dentro de tolerancia) → acento.
    private func color(for level: HitLevel?) -> SKColor {
        guard let level else { return accentColor }
        return SKColor(level.color)
    }

    // MARK: - pintado

    private func render(_ frame: HighwayFrame) {
        // curva
        if frame.discCurve.count >= 2 {
            let path = CGMutablePath()
            path.addLines(between: frame.discCurve)
            curveNode.path = path
        } else {
            curveNode.path = nil
        }

        // cabeza de lectura
        let vertical = CGMutablePath()
        vertical.move(to: CGPoint(x: frame.playheadX, y: 0))
        vertical.addLine(to: CGPoint(x: frame.playheadX, y: size.height))
        playheadNode.path = vertical

        // carril de fader (solo se dibujan los tramos abiertos)
        ensurePool(&bandPool, count: frame.faderBands.count, into: laneLayer)
        for (i, node) in bandPool.enumerated() {
            guard i < frame.faderBands.count else { node.isHidden = true; continue }
            let band = frame.faderBands[i]
            node.isHidden = !band.isOpen
            node.path = CGPath(rect: CGRect(x: band.xRange.lowerBound, y: 0,
                                            width: band.xRange.upperBound - band.xRange.lowerBound,
                                            height: geometry.laneHeight), transform: nil)
            node.fillColor = laneOpenColor
            node.strokeColor = .clear
        }

        // marcas de fader
        let marks = frame.openMarks.map { ($0, false) } + frame.closeMarks.map { ($0, true) }
        ensurePool(&markPool, count: marks.count, into: marksLayer)
        for (i, node) in markPool.enumerated() {
            guard i < marks.count else { node.isHidden = true; continue }
            let (point, closes) = marks[i]
            node.isHidden = false
            node.position = point
            node.path = CGPath(ellipseIn: CGRect(x: -5, y: -5, width: 10, height: 10), transform: nil)
            node.fillColor = closes ? closeColor : .clear
            node.strokeColor = closes ? closeColor : openColor
            node.lineWidth = 2
        }

        // capa de usuario: cada tramo con su tinte
        ensurePool(&userPool, count: frame.userSegments.count, into: userLayer)
        for (i, node) in userPool.enumerated() {
            guard i < frame.userSegments.count, frame.userSegments[i].points.count >= 2 else {
                node.isHidden = true; continue
            }
            let segment = frame.userSegments[i]
            node.isHidden = false
            node.position = .zero
            let path = CGMutablePath()
            path.addLines(between: segment.points)
            node.path = path
            node.strokeColor = color(for: segment.level)
            node.lineWidth = 3
            node.lineJoin = .round
            node.fillColor = .clear
        }

        // marcas de click con el resultado del usuario (color; la forma la da
        // XFApp con HitLevel.shape en la barra inferior)
        ensurePool(&hitPool, count: frame.hitMarks.count, into: hitLayer)
        for (i, node) in hitPool.enumerated() {
            guard i < frame.hitMarks.count else { node.isHidden = true; continue }
            let mark = frame.hitMarks[i]
            node.isHidden = false
            node.position = mark.point
            node.path = CGPath(ellipseIn: CGRect(x: -6, y: -6, width: 12, height: 12), transform: nil)
            node.strokeColor = color(for: mark.level)
            node.fillColor = mark.closes ? color(for: mark.level) : .clear
            node.lineWidth = 2
        }
    }

    private func ensurePool(_ pool: inout [SKShapeNode], count: Int, into parent: SKNode) {
        while pool.count < count {
            let node = SKShapeNode()
            pool.append(node)
            parent.addChild(node)
        }
    }
}
