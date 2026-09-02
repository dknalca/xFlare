// SPDX-License-Identifier: GPL-3.0-only

import SpriteKit
import XFDesign
import XFRender
import XFNotation

/// **Una sola** escena para toda la practica rudimentaria: la autopista, la tira
/// de onda de la instrumental (banda superior) y la tira del sample (rail
/// izquierdo, vertical) se dibujan en el MISMO `update(_:)`, leyendo el reloj
/// UNA vez por fotograma.
///
/// Antes eran tres `SKView` distintos. Cada uno recibe su callback de vsync por
/// separado; si en un frame se dibuja uno y no otro (frame perdido), la rejilla
/// de compas de la instrumental se queda un fotograma por detras de la de la
/// autopista y se ve "temblar" / desfasada. Con una escena unica eso es
/// imposible: mismo `now`, misma formula de X, mismos nodos, siempre.
///
/// La geometria de la autopista la sigue calculando `HighwayLayout` (publico y
/// puro, de XFRender, modulo sellado): aqui solo se PINTA su `HighwayFrame`,
/// reutilizando nodos para no reservar memoria por fotograma. La tira de la
/// instrumental usa EXACTAMENTE la misma formula de X que `HighwayLayout`
/// (`playheadX + (t - now)·pxPerTick`), y su contenedor esta desplazado por el
/// mismo ancho de rail, asi que sus lineas y las de la autopista caen en la
/// misma X hasta el pixel.
final class PracticeScene: SKScene {

    // MARK: - entradas (las refresca `PracticeSceneView` en cada `updateNSView`)

    /// Tick musical actual, leido del reloj de `PracticeSession` (que va con el
    /// reloj de audio). Fuente unica del tiempo del fotograma.
    var currentTick: () -> Double = { 0 }
    /// Traza del disco del usuario (capa de acento sobre el fantasma).
    var userTrace: () -> [TracePoint] = { [] }
    /// Posicion actual de reproduccion del sample, 0…1 sobre el sample entero
    /// (`EngineHandle.scratchProgress`). Mueve la aguja del rail izquierdo.
    var sampleProgress: () -> Double = { 0 }
    /// En "tu turno" del call & response el fantasma se atenua: imitas de oido.
    var ghostDimmed = false

    /// Parametros de encuadre de la autopista. `size` lo fija la escena segun el
    /// tamano real de la vista menos el rail y la tira; el resto (pixelsPerBeat,
    /// playheadFraction, beatsPerBar, laneHeight...) lo pone `PracticeSceneView`.
    var geometry = HighwayGeometry(size: .zero)
    /// PPQ del patron (para la rejilla de la tira, que no pasa por HighwayLayout).
    var patternPPQ = 480
    /// Longitud del patron en ticks (para envolver la clasificacion de la
    /// rejilla de la tira igual que hace `HighwayLayout`).
    var patternLengthTicks = 1
    /// Longitud del bucle de la instrumental en ticks (cada cuanto repite su onda).
    var instrumentalLoopTicks: Double = 1

    let railWidth: CGFloat = 44
    let stripHeight: CGFloat = 46

    // MARK: - patron

    private var layout: HighwayLayout?
    private var loadedId: String?

    func load(_ scratch: Scratch) {
        guard loadedId != scratch.id else { return }
        layout = HighwayLayout(scratch: scratch)
        loadedId = scratch.id
    }

    // MARK: - ondas (imagenes pre-renderizadas; solo se mueve el sprite por frame)

    var instrumentalImage: CGImage? { didSet { rebuildInstrSprites() } }
    var sampleImage: CGImage? { didSet { rebuildSampleSprite() } }

    // MARK: - nodos

    // fondos de las dos tiras (el resto de la escena usa `backgroundColor`)
    private let stripBG = SKShapeNode()
    private let railBG = SKShapeNode()

    // contenedores: cada uno lleva su origen local; asi la X de la autopista y
    // la de la tira coinciden con solo desplazar el contenedor por `railWidth`.
    private let highwayContainer = SKNode()
    private let stripContainer = SKNode()
    private let railContainer = SKNode()

    // --- autopista (replica fiel de HighwayScene, modulo sellado) ---
    private let gridLayer = SKNode()
    private let laneLayer = SKNode()
    private let curveNode = SKShapeNode()
    private let curveLayer = SKNode()
    private let userLayer = SKNode()
    private let marksLayer = SKNode()
    private let phantomLayer = SKNode()
    private let hitLayer = SKNode()
    private let playheadNode = SKShapeNode()
    private var beatPool: [SKShapeNode] = []
    private var barPool: [SKShapeNode] = []
    private var bandPool: [SKShapeNode] = []
    private var curvePool: [SKShapeNode] = []
    private var markPool: [SKShapeNode] = []
    private var phantomPool: [SKShapeNode] = []
    private var userPool: [SKShapeNode] = []
    private var hitPool: [SKShapeNode] = []

    // --- tira de la instrumental ---
    private var instrSprites: [SKSpriteNode] = []
    private let stripGridLayer = SKNode()
    private var stripBeatPool: [SKShapeNode] = []
    private var stripBarPool: [SKShapeNode] = []
    private let stripNeedle = SKShapeNode()

    // --- rail del sample ---
    private var sampleSprite: SKSpriteNode?
    private let railAxis = SKShapeNode()
    private let sampleMarker = SKShapeNode()

    // MARK: - paleta (identica a HighwayScene / WaveformScene)

    private let bgColor       = SKColor(red: 0x0B/255, green: 0x0D/255, blue: 0x10/255, alpha: 1)
    private let stripBGColor  = SKColor(red: 0x11/255, green: 0x14/255, blue: 0x18/255, alpha: 1)
    private let ghostColor    = SKColor(red: 0x7A/255, green: 0x87/255, blue: 0x94/255, alpha: 0.55)
    private let openColor     = SKColor(red: 0x7A/255, green: 0x87/255, blue: 0x94/255, alpha: 0.9)
    private let closeColor    = SKColor(red: 0x34/255, green: 0xE1/255, blue: 0xC4/255, alpha: 1.0)
    private let accentColor   = SKColor(red: 0x34/255, green: 0xE1/255, blue: 0xC4/255, alpha: 1.0)
    private let playheadColor = SKColor(red: 0x3A/255, green: 0x44/255, blue: 0x4F/255, alpha: 1.0)
    private let laneOpenColor = SKColor(red: 0xF2/255, green: 0xF5/255, blue: 0xF7/255, alpha: 0.10)
    private let gridBeatColor = SKColor(red: 0x3A/255, green: 0x44/255, blue: 0x4F/255, alpha: 1.0)
    private let gridBarColor  = SKColor(red: 0x23/255, green: 0x2A/255, blue: 0x32/255, alpha: 1.0)
    private let phantomColor  = SKColor(red: 0x7A/255, green: 0x87/255, blue: 0x94/255, alpha: 0.6)
    private let stripBarColor = SKColor(red: 0x5A/255, green: 0x66/255, blue: 0x74/255, alpha: 1.0)
    private let needleColor   = SKColor(red: 0x34/255, green: 0xE1/255, blue: 0xC4/255, alpha: 0.6)
    private let axisColor     = SKColor(red: 0x2A/255, green: 0x32/255, blue: 0x3B/255, alpha: 1.0)

    // MARK: - init

    override init(size: CGSize) {
        super.init(size: size)
        scaleMode = .resizeFill
        backgroundColor = bgColor

        // `ignoresSiblingOrder` deja a SpriteKit reordenar nodos de igual
        // zPosition; los fondos (SKShapeNode rellenos) podrian taparse con los
        // sprites de onda. Se les da una zPosition claramente por detras.
        stripBG.strokeColor = .clear
        stripBG.fillColor = stripBGColor
        stripBG.zPosition = -10
        railBG.strokeColor = .clear
        railBG.fillColor = stripBGColor
        railBG.zPosition = -10

        curveNode.strokeColor = ghostColor
        curveNode.lineWidth = 3
        curveNode.lineJoin = .round
        playheadNode.strokeColor = playheadColor
        playheadNode.lineWidth = 1

        stripNeedle.strokeColor = needleColor
        stripNeedle.lineWidth = 1.5
        railAxis.strokeColor = axisColor
        railAxis.lineWidth = 1
        sampleMarker.strokeColor = needleColor
        sampleMarker.lineWidth = 1.5

        addChild(stripBG)
        addChild(railBG)
        addChild(railContainer)
        addChild(stripContainer)
        addChild(highwayContainer)

        // sublayers de la autopista, en el mismo orden que HighwayScene
        for n in [gridLayer, laneLayer, curveNode, curveLayer, userLayer,
                  marksLayer, phantomLayer, hitLayer, playheadNode] {
            highwayContainer.addChild(n)
        }
        stripContainer.addChild(stripGridLayer)
        stripContainer.addChild(stripNeedle)
        railContainer.addChild(railAxis)
        railContainer.addChild(sampleMarker)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("PracticeScene se crea en codigo") }

    // MARK: - sprites de onda

    private func rebuildInstrSprites() {
        instrSprites.forEach { $0.removeFromParent() }
        instrSprites = []
        guard let img = instrumentalImage else { return }
        let tex = SKTexture(cgImage: img)
        tex.filteringMode = .linear
        // 3 copias en fila para tapar la ventana cuando el bucle es mas corto
        // que el ancho visible (mismo truco que WaveformScene).
        for _ in 0..<3 {
            let s = SKSpriteNode(texture: tex)
            s.anchorPoint = CGPoint(x: 0, y: 0.5)
            s.zPosition = -1
            stripContainer.addChild(s)
            instrSprites.append(s)
        }
    }

    private func rebuildSampleSprite() {
        sampleSprite?.removeFromParent()
        sampleSprite = nil
        guard let img = sampleImage else { return }
        let tex = SKTexture(cgImage: img)
        tex.filteringMode = .linear
        let s = SKSpriteNode(texture: tex)
        s.anchorPoint = CGPoint(x: 0.5, y: 0.5)
        s.zPosition = -1
        // la imagen se renderiza horizontal (x = tiempo) y se gira 90º: el
        // inicio del sample queda abajo y el final arriba.
        s.zRotation = .pi / 2
        railContainer.addChild(s)
        sampleSprite = s
    }

    // MARK: - encuadre

    private var lastLaidOut: CGSize = .zero

    private func layoutContainers() {
        let hw = max(1, size.width - railWidth)
        let hh = max(1, size.height - stripHeight)
        geometry.size = CGSize(width: hw, height: hh)
        highwayContainer.position = CGPoint(x: railWidth, y: 0)
        stripContainer.position = CGPoint(x: railWidth, y: hh)
        railContainer.position = .zero
        stripBG.path = CGPath(rect: CGRect(x: railWidth, y: hh, width: hw, height: stripHeight),
                              transform: nil)
        railBG.path = CGPath(rect: CGRect(x: 0, y: 0, width: railWidth, height: size.height),
                             transform: nil)
        lastLaidOut = size
    }

    override func didChangeSize(_ oldSize: CGSize) {
        super.didChangeSize(oldSize)
        layoutContainers()
    }

    // MARK: - fotograma

    override func update(_ currentTime: TimeInterval) {
        guard size.width > railWidth + 8, size.height > stripHeight + 8 else { return }
        if size != lastLaidOut { layoutContainers() }

        let now = currentTick()

        if let layout {
            let frame = layout.frame(atTick: now, geometry: geometry,
                                     userTrace: userTrace())
            renderHighway(frame, height: geometry.size.height)
        }
        highwayContainer.alpha = ghostDimmed ? 0.14 : 1

        renderStrip(now: now)
        renderRail()
    }

    // MARK: - autopista (replica de HighwayScene.render)

    private func renderHighway(_ frame: HighwayFrame, height h: CGFloat) {
        drawGrid(pool: &beatPool, xs: frame.beatLines, color: gridBeatColor, width: 1, h: h)
        drawGrid(pool: &barPool, xs: frame.barLines, color: gridBarColor, width: 2, h: h)

        if !frame.discSegments.isEmpty {
            curveNode.path = nil
            drawDiscSegments(frame.discSegments)
        } else {
            drawDiscSegments([])
            if frame.discCurve.count >= 2 {
                let path = CGMutablePath()
                path.addLines(between: frame.discCurve)
                curveNode.path = path
            } else {
                curveNode.path = nil
            }
        }

        let vertical = CGMutablePath()
        vertical.move(to: CGPoint(x: frame.playheadX, y: 0))
        vertical.addLine(to: CGPoint(x: frame.playheadX, y: h))
        playheadNode.path = vertical

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

        ensurePool(&phantomPool, count: frame.phantomMarks.count, into: phantomLayer)
        for (i, node) in phantomPool.enumerated() {
            guard i < frame.phantomMarks.count else { node.isHidden = true; continue }
            node.isHidden = false
            node.position = frame.phantomMarks[i]
            let p = CGMutablePath()
            p.move(to: CGPoint(x: 0, y: -5))
            p.addLine(to: CGPoint(x: 0, y: 5))
            node.path = p
            node.strokeColor = phantomColor
            node.fillColor = .clear
            node.lineWidth = 2
        }

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

    private func color(for level: HitLevel?) -> SKColor {
        guard let level else { return accentColor }
        return SKColor(level.color)
    }

    private func drawDiscSegments(_ segments: [[CGPoint]]) {
        ensurePool(&curvePool, count: segments.count, into: curveLayer)
        for (i, node) in curvePool.enumerated() {
            guard i < segments.count, segments[i].count >= 2 else { node.isHidden = true; continue }
            node.isHidden = false
            let path = CGMutablePath()
            path.addLines(between: segments[i])
            node.path = path
            node.strokeColor = ghostColor
            node.lineWidth = 3
            node.lineJoin = .round
            node.fillColor = .clear
        }
    }

    private func drawGrid(pool: inout [SKShapeNode], xs: [CGFloat],
                          color: SKColor, width: CGFloat, h: CGFloat) {
        ensurePool(&pool, count: xs.count, into: gridLayer)
        for (i, node) in pool.enumerated() {
            guard i < xs.count else { node.isHidden = true; continue }
            node.isHidden = false
            let path = CGMutablePath()
            path.move(to: CGPoint(x: xs[i], y: 0))
            path.addLine(to: CGPoint(x: xs[i], y: h))
            node.path = path
            node.strokeColor = color
            node.lineWidth = width
        }
    }

    // MARK: - tira de la instrumental

    private func renderStrip(now: Double) {
        let ppq = CGFloat(max(1, patternPPQ))
        let pxPerTick = geometry.pixelsPerBeat / ppq
        let playheadX = geometry.playheadX
        let w = geometry.size.width
        let loop = max(1, instrumentalLoopTicks)
        let imgW = CGFloat(loop) * pxPerTick

        var phase = now.truncatingRemainder(dividingBy: loop)
        if phase < 0 { phase += loop }
        let baseX = playheadX - CGFloat(phase) * pxPerTick
        for (i, s) in instrSprites.enumerated() {
            s.position = CGPoint(x: baseX + CGFloat(i - 1) * imgW, y: stripHeight / 2)
            s.size = CGSize(width: imgW, height: stripHeight)
        }

        let (beats, bars) = Self.stripGridXs(
            now: now, width: w, playheadX: playheadX, pxPerTick: pxPerTick,
            ppq: max(1, patternPPQ), patternLen: max(1, patternLengthTicks),
            beatsPerBar: max(1, geometry.beatsPerBar))
        placeStripGrid(&stripBeatPool, at: beats, color: gridBeatColor, width: 1)
        placeStripGrid(&stripBarPool, at: bars, color: stripBarColor, width: 1.5)

        let np = CGMutablePath()
        np.move(to: CGPoint(x: playheadX, y: 0))
        np.addLine(to: CGPoint(x: playheadX, y: stripHeight))
        stripNeedle.path = np
    }

    /// X (locales a la tira, = locales a la autopista) de las lineas de negra y
    /// de compas visibles en `now`. **Misma formula y clasificacion** que
    /// `HighwayLayout.frame` (rejilla por `wrapped` sobre la longitud del
    /// patron): asi las lineas de la tira caen sobre las de la autopista hasta
    /// el pixel. `internal` para poder comprobarlo en un test contra
    /// `HighwayLayout`.
    static func stripGridXs(now: Double, width w: CGFloat, playheadX: CGFloat,
                            pxPerTick: CGFloat, ppq: Int, patternLen: Int,
                            beatsPerBar: Int) -> (beats: [CGFloat], bars: [CGFloat]) {
        let tMin = now + Double((0 - playheadX) / pxPerTick)
        let tMax = now + Double((w - playheadX) / pxPerTick)
        let len = Double(max(1, patternLen))
        let firstBeat = Int((tMin / Double(ppq)).rounded(.up))
        let lastBeat = Int((tMax / Double(ppq)).rounded(.down))
        var beats: [CGFloat] = []
        var bars: [CGFloat] = []
        guard firstBeat <= lastBeat else { return ([], []) }
        for b in firstBeat...lastBeat {
            let t = Double(b * ppq)
            let m = t.truncatingRemainder(dividingBy: len)
            let beatInPattern = Int(m < 0 ? m + len : m) / ppq
            let x = playheadX + CGFloat(t - now) * pxPerTick
            if beatInPattern % max(1, beatsPerBar) == 0 { bars.append(x) } else { beats.append(x) }
        }
        return (beats, bars)
    }

    private func placeStripGrid(_ pool: inout [SKShapeNode], at xs: [CGFloat],
                                color: SKColor, width: CGFloat) {
        while pool.count < xs.count {
            let n = SKShapeNode()
            stripGridLayer.addChild(n)
            pool.append(n)
        }
        for (i, n) in pool.enumerated() {
            guard i < xs.count else { n.isHidden = true; continue }
            n.isHidden = false
            let p = CGMutablePath()
            p.move(to: CGPoint(x: xs[i].rounded(), y: 0))
            p.addLine(to: CGPoint(x: xs[i].rounded(), y: stripHeight))
            n.path = p
            n.strokeColor = color
            n.lineWidth = width
        }
    }

    // MARK: - rail del sample

    private func renderRail() {
        let ax = CGMutablePath()
        ax.move(to: CGPoint(x: railWidth / 2, y: 0))
        ax.addLine(to: CGPoint(x: railWidth / 2, y: size.height))
        railAxis.path = ax

        if let s = sampleSprite {
            s.position = CGPoint(x: railWidth / 2, y: size.height / 2)
            // pre-giro: el eje largo (tiempo) mide el alto de la escena; el corto,
            // el ancho del rail. Con `zRotation = .pi/2` queda vertical.
            s.size = CGSize(width: size.height, height: railWidth)
        }

        let p = CGFloat(max(0, min(1, sampleProgress())))
        let y = (p * size.height).rounded()
        let mk = CGMutablePath()
        mk.move(to: CGPoint(x: 0, y: y))
        mk.addLine(to: CGPoint(x: railWidth, y: y))
        sampleMarker.path = mk
    }

    // MARK: - util

    private func ensurePool(_ pool: inout [SKShapeNode], count: Int, into parent: SKNode) {
        while pool.count < count {
            let node = SKShapeNode()
            pool.append(node)
            parent.addChild(node)
        }
    }
}
