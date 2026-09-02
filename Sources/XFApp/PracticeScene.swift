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
/// reutilizando nodos para no reservar memoria por fotograma.
///
/// La rejilla de negras/compas y el cabezal se dibujan como lineas **de altura
/// completa** (tira + autopista) en una capa a nivel de escena: asi la rejilla
/// de la tira y la de la autopista son literalmente la misma linea, sin hueco.
/// Los contenedores de la autopista y de la tira van dentro de un `SKCropNode`
/// para que su contenido no se salga por la izquierda encima del rail.
final class PracticeScene: SKScene {

    // MARK: - entradas (las refresca `PracticeSceneView` en cada `updateNSView`)

    /// Tick musical actual, leido del reloj de `PracticeSession` (que va con el
    /// reloj de audio). Fuente unica del tiempo del fotograma.
    var currentTick: () -> Double = { 0 }
    /// Traza del disco del usuario (capa de acento sobre el fantasma).
    var userTrace: () -> [TracePoint] = { [] }
    /// En "tu turno" del call & response el fantasma se atenua: imitas de oido.
    var ghostDimmed = false
    /// Escala vertical de la ONDA FANTASMA (la que hay que seguir), respecto al
    /// borde inferior de la banda de la curva. `1` = tal cual (pico a 2/3);
    /// `1.5` = pico arriba del todo. El slider de "Amplitud" lo mueve. NO afecta
    /// a la traza del usuario, que siempre puede ir de abajo arriba del todo.
    var ghostScale: CGFloat = 1

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

    // recorte: el contenido de la autopista / la tira no debe salirse por la
    // izquierda y pintarse encima del rail del sample.
    private let highwayCrop = SKCropNode()
    private let stripCrop = SKCropNode()
    private let highwayMask = SKSpriteNode(color: .white, size: CGSize(width: 1, height: 1))
    private let stripMask = SKSpriteNode(color: .white, size: CGSize(width: 1, height: 1))

    // contenedores: cada uno lleva su origen local; asi la X de la autopista y
    // la de la tira coinciden con solo desplazar el contenedor por `railWidth`.
    private let highwayContainer = SKNode()
    private let stripContainer = SKNode()
    private let railContainer = SKNode()

    // rejilla + cabezal a nivel de escena, altura completa (tira + autopista).
    private let fullGridLayer = SKNode()
    private var fullBeatPool: [SKShapeNode] = []
    private var fullBarPool: [SKShapeNode] = []
    private let fullPlayhead = SKShapeNode()

    // --- autopista (replica fiel de HighwayScene, modulo sellado; sin rejilla:
    // esa va en `fullGridLayer`) ---
    private let laneLayer = SKNode()
    /// Contenedor de todo lo FANTASMA (curva + marcas), con `yScale = ghostScale`
    /// alrededor del borde inferior de la banda. La traza del usuario NO va aqui.
    private let ghostContainer = SKNode()
    private let curveNode = SKShapeNode()
    private let curveLayer = SKNode()
    private let userLayer = SKNode()
    private let marksLayer = SKNode()
    private let phantomLayer = SKNode()
    private let hitLayer = SKNode()
    private var bandPool: [SKShapeNode] = []
    private var curvePool: [SKShapeNode] = []
    private var markPool: [SKShapeNode] = []
    private var phantomPool: [SKShapeNode] = []
    private var userPool: [SKShapeNode] = []
    private var hitPool: [SKShapeNode] = []

    // --- tira de la instrumental ---
    private var instrSprites: [SKSpriteNode] = []

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
    private let needleColor   = SKColor(red: 0x34/255, green: 0xE1/255, blue: 0xC4/255, alpha: 0.6)
    private let axisColor     = SKColor(red: 0x2A/255, green: 0x32/255, blue: 0x3B/255, alpha: 1.0)

    // MARK: - init

    override init(size: CGSize) {
        super.init(size: size)
        scaleMode = .resizeFill
        backgroundColor = bgColor

        // `ignoresSiblingOrder` deja a SpriteKit reordenar nodos de igual
        // zPosition; se ordena todo con zPosition explicita.
        stripBG.strokeColor = .clear
        stripBG.fillColor = stripBGColor
        stripBG.zPosition = -10
        railBG.strokeColor = .clear
        railBG.fillColor = stripBGColor
        railBG.zPosition = 5           // por encima de la autopista: tapa cualquier resto

        fullGridLayer.zPosition = -5    // rejilla al fondo, sobre los fondos
        highwayCrop.zPosition = 0
        stripCrop.zPosition = 1
        railContainer.zPosition = 6     // rail (onda + aguja) sobre su fondo

        curveNode.strokeColor = ghostColor
        curveNode.lineWidth = 3
        curveNode.lineJoin = .round
        fullPlayhead.strokeColor = playheadColor
        fullPlayhead.lineWidth = 1

        railAxis.strokeColor = axisColor
        railAxis.lineWidth = 1
        sampleMarker.strokeColor = needleColor
        sampleMarker.lineWidth = 1.5

        addChild(stripBG)
        addChild(railBG)
        addChild(fullGridLayer)
        fullGridLayer.addChild(fullPlayhead)
        addChild(railContainer)
        addChild(stripCrop)
        addChild(highwayCrop)

        highwayCrop.maskNode = highwayMask
        highwayCrop.addChild(highwayContainer)
        stripCrop.maskNode = stripMask
        stripCrop.addChild(stripContainer)

        // sublayers de la autopista. Lo FANTASMA (curva + marcas) va dentro de
        // `ghostContainer` (se escala con `ghostScale`); la traza del usuario,
        // fuera (siempre a escala 1, de abajo arriba del todo).
        for n in [curveNode, curveLayer, marksLayer, phantomLayer, hitLayer] {
            ghostContainer.addChild(n)
        }
        for n in [laneLayer, ghostContainer, userLayer] {
            highwayContainer.addChild(n)
        }
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

    /// Alto de la zona de autopista (la escena menos la tira de arriba).
    private var highwayHeight: CGFloat { max(1, size.height - stripHeight) }

    private func layoutContainers() {
        let hw = max(1, size.width - railWidth)
        let hh = highwayHeight
        geometry.size = CGSize(width: hw, height: hh)

        highwayContainer.position = CGPoint(x: railWidth, y: 0)
        stripContainer.position = CGPoint(x: railWidth, y: hh)
        railContainer.position = .zero

        // mascaras de recorte: exactamente la zona de cada contenedor
        highwayMask.anchorPoint = CGPoint(x: 0, y: 0)
        highwayMask.position = CGPoint(x: railWidth, y: 0)
        highwayMask.size = CGSize(width: hw, height: hh)
        stripMask.anchorPoint = CGPoint(x: 0, y: 0)
        stripMask.position = CGPoint(x: railWidth, y: hh)
        stripMask.size = CGSize(width: hw, height: stripHeight)

        stripBG.path = CGPath(rect: CGRect(x: railWidth, y: hh, width: hw, height: stripHeight),
                              transform: nil)
        // el rail = el sample ENTERO, toda la franja de la autopista (0…hh). El
        // movimiento, dentro, llega solo hasta `amplitude` (por defecto 2/3).
        railBG.path = CGPath(rect: CGRect(x: 0, y: 0, width: railWidth, height: hh), transform: nil)
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
        // la traza del usuario NO pasa por `HighwayLayout.frame` (su mapeo `y()`
        // con `patternFill` la dejaba con techo a 2/3): la dibujamos aparte con
        // un mapeo lineal propio, de abajo del todo (inicio del sample) a arriba
        // del todo (final). Ver `renderUserTrace`.
        let frame = layout?.frame(atTick: now, geometry: geometry)

        if let frame { renderHighway(frame, height: geometry.size.height) }
        highwayContainer.alpha = ghostDimmed ? 0.14 : 1

        // escala vertical de la onda fantasma alrededor del borde inferior de la
        // banda: `y' = yb + (y - yb)·s`  ->  offset = yb·(1 - s).
        let yb = geometry.curveBand.bottom
        let s = max(0.1, ghostScale)
        ghostContainer.yScale = s
        ghostContainer.position = CGPoint(x: 0, y: yb * (1 - s))

        renderFullGrid(now: now)
        renderUserTrace(now: now)
        renderStrip(now: now)
        renderRail(frame)
    }

    /// Dibuja la traza del usuario con un mapeo vertical LINEAL propio: el rango
    /// entero del plato (`[posLo, posHi]`, es decir el sample de principio a fin)
    /// ocupa toda la banda de la curva. Sin techo a 2/3. Los tramos con el fader
    /// cerrado (`.miss`) se pintan apagados.
    private func renderUserTrace(now: Double) {
        guard let layout else {
            for n in userPool { n.isHidden = true }
            return
        }
        let pts = userTrace()
        let ppq = CGFloat(max(1, patternPPQ))
        let pxPerTick = geometry.pixelsPerBeat / ppq
        let playheadX = geometry.playheadX
        let (yb, yt) = geometry.curveBand

        // rango del plato en unidades de posicion: [lo, lo + span/topFraction]
        let lo = layout.positionRange.lowerBound
        let span = max(1e-9, layout.positionRange.upperBound - lo)
        let hi = lo + span / AudioAsset.scratchPatternTopFraction   // = lo + 1.5·span
        func mapY(_ p: Double) -> CGFloat {
            let f = (p - lo) / (hi - lo)
            return yb + CGFloat(min(1.02, max(-0.02, f))) * (yt - yb)
        }

        // parte la polilinea donde cambia el nivel (nil <-> .miss)
        var runs: [(muted: Bool, pts: [CGPoint])] = []
        var cur: (muted: Bool, pts: [CGPoint])?
        for tp in pts {
            let muted = (tp.level == .miss)
            let pt = CGPoint(x: playheadX + CGFloat(tp.tick - now) * pxPerTick, y: mapY(tp.position))
            if cur == nil || cur!.muted != muted {
                if var c = cur { c.pts.append(pt); runs.append(c) }   // punto de corte compartido
                cur = (muted, [pt])
            } else {
                cur!.pts.append(pt)
            }
        }
        if let c = cur { runs.append(c) }

        ensurePool(&userPool, count: runs.count, into: userLayer)
        for (i, node) in userPool.enumerated() {
            guard i < runs.count, runs[i].pts.count >= 2 else { node.isHidden = true; continue }
            node.isHidden = false
            node.position = .zero
            let path = CGMutablePath()
            path.addLines(between: runs[i].pts)
            node.path = path
            node.strokeColor = runs[i].muted ? SKColor(XFColor.textMuted) : accentColor
            node.lineWidth = 3
            node.lineJoin = .round
            node.fillColor = .clear
        }
    }

    // MARK: - rejilla + cabezal de altura completa (tira + autopista)

    private func renderFullGrid(now: Double) {
        let pxPerTick = geometry.pixelsPerTick(ppq: max(1, patternPPQ))
        let playheadX = geometry.playheadX
        let (beats, bars) = Self.gridLines(
            now: now, width: geometry.size.width, playheadX: playheadX,
            pxPerTick: pxPerTick, ppq: max(1, patternPPQ),
            beatsPerBar: max(1, geometry.beatsPerBar))

        // X locales a la autopista -> se desplazan por `railWidth` y van de
        // y=0 a y=alto de escena (una linea unica atraviesa tira + autopista).
        drawFullLines(pool: &fullBeatPool, xs: beats, color: gridBeatColor, width: 1)
        drawFullLines(pool: &fullBarPool, xs: bars, color: gridBarColor, width: 2)

        let p = CGMutablePath()
        let px = (railWidth + playheadX).rounded()
        p.move(to: CGPoint(x: px, y: 0))
        p.addLine(to: CGPoint(x: px, y: size.height))
        fullPlayhead.path = p
    }

    private func drawFullLines(pool: inout [SKShapeNode], xs: [CGFloat],
                               color: SKColor, width: CGFloat) {
        while pool.count < xs.count {
            let n = SKShapeNode()
            fullGridLayer.addChild(n)
            pool.append(n)
        }
        for (i, n) in pool.enumerated() {
            guard i < xs.count else { n.isHidden = true; continue }
            n.isHidden = false
            let path = CGMutablePath()
            let x = (railWidth + xs[i]).rounded()
            path.move(to: CGPoint(x: x, y: 0))
            path.addLine(to: CGPoint(x: x, y: size.height))
            n.path = path
            n.strokeColor = color
            n.lineWidth = width
        }
    }

    // MARK: - autopista (replica de HighwayScene.render, sin la rejilla)

    private func renderHighway(_ frame: HighwayFrame, height h: CGFloat) {
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

        // la traza del usuario la pinta `renderUserTrace` (mapeo lineal propio,
        // sin techo), no esta capa.

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
        _ = h
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

    // MARK: - tira de la instrumental

    private func renderStrip(now: Double) {
        let ppq = CGFloat(max(1, patternPPQ))
        let pxPerTick = geometry.pixelsPerBeat / ppq
        let playheadX = geometry.playheadX
        let loop = max(1, instrumentalLoopTicks)
        let imgW = CGFloat(loop) * pxPerTick

        var phase = now.truncatingRemainder(dividingBy: loop)
        if phase < 0 { phase += loop }
        let baseX = playheadX - CGFloat(phase) * pxPerTick
        for (i, s) in instrSprites.enumerated() {
            s.position = CGPoint(x: baseX + CGFloat(i - 1) * imgW, y: stripHeight / 2)
            s.size = CGSize(width: imgW, height: stripHeight)
        }
    }

    /// X (locales a la autopista) de las lineas de negra y de compas visibles en
    /// `now`, una linea por negra. Una negra es **linea de compas** cuando su
    /// indice ABSOLUTO es multiplo de `beatsPerBar`: el "1" es el tick 0, que
    /// `PracticeSession.resyncClock()` alinea con el primer golpe de la
    /// instrumental. Asi los compases quedan regulares aunque el patron no mida
    /// un numero entero de compases (la clasificacion `wrapped` de
    /// `HighwayLayout`, pensada para su invariancia anti-deriva, ahi los
    /// desalinea). `internal` para testearla.
    static func gridLines(now: Double, width w: CGFloat, playheadX: CGFloat,
                          pxPerTick: CGFloat, ppq: Int,
                          beatsPerBar: Int) -> (beats: [CGFloat], bars: [CGFloat]) {
        let tMin = now + Double((0 - playheadX) / pxPerTick)
        let tMax = now + Double((w - playheadX) / pxPerTick)
        let firstBeat = Int((tMin / Double(ppq)).rounded(.up))
        let lastBeat = Int((tMax / Double(ppq)).rounded(.down))
        var beats: [CGFloat] = []
        var bars: [CGFloat] = []
        guard firstBeat <= lastBeat else { return ([], []) }
        let bpb = max(1, beatsPerBar)
        for b in firstBeat...lastBeat {
            let x = playheadX + CGFloat(Double(b * ppq) - now) * pxPerTick
            // modulo bien portado con negras negativas (b puede ser < 0)
            if ((b % bpb) + bpb) % bpb == 0 { bars.append(x) } else { beats.append(x) }
        }
        return (beats, bars)
    }

    // MARK: - rail del sample

    private func renderRail(_ frame: HighwayFrame?) {
        // el rail = el SAMPLE ENTERO, toda la franja de la autopista (0…hh). El
        // slider de amplitud solo cambia hasta donde llega el MOVIMIENTO dentro,
        // no estira ni encoge el sample de aqui.
        let hh = highwayHeight

        let ax = CGMutablePath()
        ax.move(to: CGPoint(x: railWidth / 2, y: 0))
        ax.addLine(to: CGPoint(x: railWidth / 2, y: hh))
        railAxis.path = ax

        if let s = sampleSprite {
            // pre-giro: el eje largo (tiempo) mide el alto de la zona; el corto,
            // el ancho del rail. Con `zRotation = .pi/2` queda vertical.
            s.position = CGPoint(x: railWidth / 2, y: hh / 2)
            s.size = CGSize(width: hh, height: railWidth)
        }

        // la aguja va a la MISMA altura que la linea de la autopista bajo el
        // cabezal: como el movimiento vive en `[yBottom, patternTopY≈2/3]`, la
        // aguja recorre esa parte de abajo del rail = "vas por 2/3 del sample".
        let y = min(hh, max(0, railMarkerY(frame, fallback: hh / 2)))
        let mk = CGMutablePath()
        mk.move(to: CGPoint(x: 0, y: y))
        mk.addLine(to: CGPoint(x: railWidth, y: y))
        sampleMarker.path = mk
    }

    /// Y (en coords de la zona de autopista) de la linea bajo el cabezal:
    /// donde esta el plato del usuario ahora (mismo mapeo lineal que la traza),
    /// y si aun no hay traza, la del fantasma (curva del disco).
    private func railMarkerY(_ frame: HighwayFrame?, fallback: CGFloat) -> CGFloat {
        if let layout, let last = userTrace().last {
            let (yb, yt) = geometry.curveBand
            let lo = layout.positionRange.lowerBound
            let span = max(1e-9, layout.positionRange.upperBound - lo)
            let hi = lo + span / AudioAsset.scratchPatternTopFraction
            let f = (last.position - lo) / (hi - lo)
            return yb + CGFloat(min(1.02, max(-0.02, f))) * (yt - yb)
        }
        guard let frame else { return fallback }
        var bestY = fallback
        var bestD = CGFloat.greatestFiniteMagnitude
        for pt in frame.discCurve {
            let d = abs(pt.x - frame.playheadX)
            if d < bestD { bestD = d; bestY = pt.y }
        }
        return bestY
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
