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
    /// **Amplitud** del slider (`0.3…1.0`; `2/3` por defecto). A que fraccion de
    /// la banda llega el pico del patron. Escala IGUAL la onda fantasma y la
    /// traza del usuario: asi en "repite conmigo" el teal auto-generado cae
    /// EXACTAMENTE sobre la onda gris. La traza NO se recorta arriba: si el plato
    /// se pasa del pico (n > 1/amplitud) sigue subiendo y se sale.
    var patternAmplitude: CGFloat = 2.0 / 3.0

    /// En **Freestyle** no hay patron que seguir: se oculta la onda fantasma
    /// (curva gris + sus marcas). La rejilla, el carril de fader y la traza del
    /// usuario siguen visibles.
    var showGhost = true

    /// Desplazamiento MANUAL de la rejilla respecto a la instrumental, en ticks
    /// (botones ◀ / ▶). Se suma a `now` cada fotograma -> mueve rejilla + onda
    /// fantasma + traza a la vez, sin tocar el reloj de la sesion. `+` mueve la
    /// rejilla a la izquierda, `-` a la derecha.
    var gridShift: Double = 0

    /// Cabezal de la base como fracción 0…1 del bucle (o < 0 si no hay base). La
    /// tira de la instrumental se dibuja pegada a esto, no a `now mod loop`: así
    /// no se descuadra del audio al cambiar el tempo (TAP, ÷2/×2), que altera
    /// `instrumentalLoopTicks` sin mover el reloj.
    var instrumentalHeadFraction: () -> Double = { -1 }

    /// Se llama (en el hilo principal) con el tamaño de la **zona de autopista**
    /// cada vez que se recalcula el encuadre. Lo usa `LivePracticeView` para
    /// exportar el vídeo con la misma proporción que la ventana.
    var onHighwaySize: ((CGSize) -> Void)?

    /// Overlay de fotogramas por segundo (diagnóstico B7.2b). Lo enciende el
    /// ajuste "Mostrar FPS".
    var showFPS = false {
        didSet { fpsLabel.isHidden = !showFPS }
    }
    private var fpsMeter = FrameRateMeter()
    private let fpsLabel = SKLabelNode(fontNamed: "Menlo")
    private var fpsRefresh = 0

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
    /// Números de compás.subdivisión ("1.1", "1.2"…) encima de cada línea de la
    /// rejilla, arriba del todo. Pequeños y discretos; se mueven con la rejilla
    /// (usan el mismo `now` desplazado por `gridShift`).
    private var gridLabelPool: [SKLabelNode] = []

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
    private var openMarkPool: [SKShapeNode] = []
    private var closeMarkPool: [SKShapeNode] = []
    private var phantomPool: [SKShapeNode] = []
    private var userPool: [SKShapeNode] = []
    private var hitPool: [SKShapeNode] = []

    // Formas CONSTANTES: se calculan una vez y los nodos solo se mueven por
    // `position`. Reasignar `SKShapeNode.path` re-tesela en CPU cada frame; era
    // el grueso del coste de la práctica.
    private static let dotPath      = CGPath(ellipseIn: CGRect(x: -5, y: -5, width: 10, height: 10), transform: nil)
    private static let hitDotPath   = CGPath(ellipseIn: CGRect(x: -6, y: -6, width: 12, height: 12), transform: nil)
    private static let phantomTick  : CGPath = {
        let p = CGMutablePath(); p.move(to: CGPoint(x: 0, y: -5)); p.addLine(to: CGPoint(x: 0, y: 5)); return p
    }()
    /// Alto con el que se construyeron las líneas verticales (rejilla/cabezal);
    /// se rehace su `path` solo cuando cambia.
    private var vlineHeight: CGFloat = -1
    /// Ancho de imagen de la instrumental con el que están dimensionados los
    /// sprites de la tira; evita setear `.size` cada frame.
    private var lastStripImgW: CGFloat = -1

    // Estado del último frame dibujado, para saltarse el redibujo si nada cambió.
    private var lastRenderNow: Double = .nan
    private var lastRenderTraceN = -1
    private var lastRenderGridShift: Double = .nan
    private var lastRenderAmplitude: CGFloat = -1

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

        fpsLabel.fontSize = 10
        fpsLabel.fontColor = NSColor(white: 0.85, alpha: 0.9)
        fpsLabel.horizontalAlignmentMode = .right
        fpsLabel.verticalAlignmentMode = .top
        fpsLabel.zPosition = 100
        fpsLabel.isHidden = true
        addChild(fpsLabel)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("PracticeScene se crea en codigo") }

    // MARK: - sprites de onda

    private func rebuildInstrSprites() {
        instrSprites.forEach { $0.removeFromParent() }
        instrSprites = []
        lastStripImgW = -1   // fuerza el redimensionado en el próximo `renderStrip`
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

        // eje del rail: forma fija salvo al redimensionar (aquí, no cada frame)
        let ax = CGMutablePath()
        ax.move(to: CGPoint(x: railWidth / 2, y: 0))
        ax.addLine(to: CGPoint(x: railWidth / 2, y: hh))
        railAxis.path = ax
        // marca de la aguja: línea horizontal local; el frame solo mueve su Y
        if sampleMarker.path == nil {
            let mk = CGMutablePath()
            mk.move(to: .zero); mk.addLine(to: CGPoint(x: railWidth, y: 0))
            sampleMarker.path = mk
        }
        lastLaidOut = size

        // avisa del tamaño real de la autopista (para que el vídeo salga con la
        // misma proporción que la ventana, no estirado)
        let highwaySize = geometry.size
        DispatchQueue.main.async { [weak self] in self?.onHighwaySize?(highwaySize) }
    }

    override func didChangeSize(_ oldSize: CGSize) {
        super.didChangeSize(oldSize)
        layoutContainers()
    }

    // MARK: - fotograma

    override func update(_ currentTime: TimeInterval) {
        guard size.width > railWidth + 8, size.height > stripHeight + 8 else { return }
        let didLayout = size != lastLaidOut
        if didLayout { layoutContainers() }

        // medidor de fps: se alimenta SIEMPRE (para tener dato al encenderlo);
        // el texto solo se rehace ~5 veces/s y solo si el overlay esta visible.
        fpsMeter.tick(currentTime)
        if showFPS {
            fpsRefresh += 1
            if fpsRefresh >= 12 {
                fpsRefresh = 0
                let target = Double((view?.preferredFramesPerSecond ?? 60) > 0
                                    ? view!.preferredFramesPerSecond : 60)
                fpsLabel.text = fpsMeter.summary(targetFPS: target)
                fpsLabel.fontColor = fpsMeter.averageFPS >= target - 5
                    ? NSColor(white: 0.85, alpha: 0.9)
                    : NSColor(red: 1, green: 0.3, blue: 0.37, alpha: 0.95)
            }
            fpsLabel.position = CGPoint(x: size.width - 6, y: size.height - 4)
        }

        // `gridShift` (botones ◀/▶) desplaza la REJILLA + la onda fantasma + la
        // traza respecto a la instrumental. La onda de la instrumental (tira de
        // arriba) NO se mueve: es la referencia con la que hay que cuadrar.
        let rawNow = currentTick()
        let now = rawNow + gridShift

        // Si NADA se ha movido (congelado, o el refresco va más rápido que el
        // reloj) no rehacemos la geometría: SpriteKit sigue componiendo lo ya
        // dibujado a coste casi cero.
        let traceN = userTrace().count
        if !didLayout, now == lastRenderNow, traceN == lastRenderTraceN,
           gridShift == lastRenderGridShift, patternAmplitude == lastRenderAmplitude {
            return
        }
        lastRenderNow = now; lastRenderTraceN = traceN
        lastRenderGridShift = gridShift; lastRenderAmplitude = patternAmplitude

        let frame = layout?.frame(atTick: now, geometry: geometry)

        if let frame { renderHighway(frame, height: geometry.size.height) }

        // En "tu turno" del call & response se atenúa **solo el fantasma gris**
        // (imitas de memoria); tu traza teal y el carril de fader siguen a plena
        // luz — antes se oscurecía todo (`highwayContainer.alpha`) y no se veía.
        highwayContainer.alpha = 1

        // escala vertical de la onda fantasma alrededor del borde inferior de la
        // banda. `HighwayLayout` la dibuja con `patternFill = 2/3`; para que su
        // pico quede a `patternAmplitude` de la banda hace falta yScale =
        // amplitud / (2/3) = 1.5·amplitud. (La traza usa el mismo factor en
        // `traceY`, asi coinciden.)
        ghostContainer.isHidden = !showGhost
        ghostContainer.alpha = ghostDimmed ? 0.3 : 1
        let yb = geometry.curveBand.bottom
        let s = max(0.1, 1.5 * patternAmplitude)
        ghostContainer.yScale = s
        ghostContainer.position = CGPoint(x: 0, y: yb * (1 - s))

        renderFullGrid(now: now)
        // La traza va con `rawNow` (NO con `gridShift`): representa lo que estás
        // tocando AHORA, así que su punto bajo el cabezal es lo que suena. Lo que
        // `gridShift` mueve es la rejilla y la onda fantasma (para cuadrarlas con
        // la instrumental); la fantasma se mueve también en el audio (la sesión
        // usa `gridPhaseTicks`), así que traza y fantasma siguen coincidiendo.
        renderUserTrace(now: rawNow)
        renderStrip(now: rawNow)   // la instrumental no se desplaza con `gridShift`
        renderRail(frame)
    }

    /// Y de una posicion de plato en la autopista. **Mismo mapeo que la onda
    /// fantasma**: `n=0` (pico bajo del patron) -> `yb`; `n=1` (pico alto del
    /// patron) -> `yb + amplitud·(yt-yb)`. Asi en "repite conmigo" la traza
    /// auto-generada cae EXACTAMENTE sobre la gris. Si el plato se pasa del pico
    /// del patron (`n > 1`) la traza SIGUE subiendo -> a `n = 1/amplitud` llega
    /// al borde y de ahi para arriba se sale (lo recorta el `SKCropNode`).
    private func traceY(_ position: Double) -> CGFloat {
        guard let layout else { return geometry.curveBand.bottom }
        let (yb, yt) = geometry.curveBand
        let lo = layout.positionRange.lowerBound
        let span = max(1e-9, layout.positionRange.upperBound - lo)
        let n = (position - lo) / span
        return yb + CGFloat(min(4.0, max(-0.1, n)) * Double(patternAmplitude)) * (yt - yb)
    }

    /// Dibuja la traza del usuario. Los tramos con el fader cerrado (`.miss`) se
    /// pintan apagados.
    private func renderUserTrace(now: Double) {
        guard layout != nil else {
            for n in userPool { n.isHidden = true }
            return
        }
        let pts = userTrace()
        let ppq = CGFloat(max(1, patternPPQ))
        let pxPerTick = geometry.pixelsPerBeat / ppq
        let playheadX = geometry.playheadX

        // parte la polilinea donde cambia el nivel (nil <-> .miss)
        var runs: [(muted: Bool, pts: [CGPoint])] = []
        var cur: (muted: Bool, pts: [CGPoint])?
        for tp in pts {
            let muted = (tp.level == .miss)
            let pt = CGPoint(x: playheadX + CGFloat(tp.tick - now) * pxPerTick, y: traceY(tp.position))
            if cur == nil || cur!.muted != muted {
                if var c = cur { c.pts.append(pt); runs.append(c) }   // punto de corte compartido
                cur = (muted, [pt])
            } else {
                cur!.pts.append(pt)
            }
        }
        if let c = cur { runs.append(c) }

        ensureShapePool(&userPool, count: runs.count, into: userLayer) { n in
            n.lineWidth = 3; n.lineJoin = .round; n.fillColor = .clear; n.position = .zero
        }
        for (i, node) in userPool.enumerated() {
            guard i < runs.count, runs[i].pts.count >= 2 else { node.isHidden = true; continue }
            node.isHidden = false
            let path = CGMutablePath()
            path.addLines(between: runs[i].pts)
            node.path = path
            let c = runs[i].muted ? mutedTraceColor : accentColor
            if node.strokeColor != c { node.strokeColor = c }
        }
    }

    private let mutedTraceColor = SKColor(red: 0x9A/255, green: 0xA5/255, blue: 0xB1/255, alpha: 1)

    // MARK: - rejilla + cabezal de altura completa (tira + autopista)

    private func renderFullGrid(now: Double) {
        let pxPerTick = geometry.pixelsPerTick(ppq: max(1, patternPPQ))
        let playheadX = geometry.playheadX
        let (beats, bars) = Self.gridLines(
            now: now, width: geometry.size.width, playheadX: playheadX,
            pxPerTick: pxPerTick, ppq: max(1, patternPPQ),
            beatsPerBar: max(1, geometry.beatsPerBar))

        // Las líneas verticales tienen forma CONSTANTE (0→alto de escena): su
        // `path` solo se rehace si cambia el alto; cada frame solo se mueven en X.
        let h = size.height
        if vlineHeight != h {
            vlineHeight = h
            let vp = Self.vline(h)
            for n in fullBeatPool { n.path = vp }
            for n in fullBarPool { n.path = vp }
            fullPlayhead.path = vp
        }
        moveVLines(pool: &fullBeatPool, xs: beats, color: gridBeatColor, width: 1)
        moveVLines(pool: &fullBarPool, xs: bars, color: gridBarColor, width: 2)
        fullPlayhead.position = CGPoint(x: (railWidth + playheadX).rounded(), y: 0)

        // números "compás.subdivisión" arriba de cada línea (solo del "1" en
        // adelante; antes del arranque no se etiqueta).
        let labels = Self.gridLabels(
            now: now, width: geometry.size.width, playheadX: playheadX,
            pxPerTick: pxPerTick, ppq: max(1, patternPPQ),
            beatsPerBar: max(1, geometry.beatsPerBar))
        moveGridLabels(labels)
    }

    private func moveGridLabels(_ items: [(x: CGFloat, text: String)]) {
        while gridLabelPool.count < items.count {
            let l = SKLabelNode(fontNamed: "Menlo")
            l.fontSize = 8
            l.fontColor = SKColor(red: 0x7A/255, green: 0x87/255, blue: 0x94/255, alpha: 0.5)
            l.horizontalAlignmentMode = .left
            l.verticalAlignmentMode = .top
            l.zPosition = 8            // sobre la autopista, discreto
            fullGridLayer.addChild(l)
            gridLabelPool.append(l)
        }
        // arriba del todo de la autopista (justo bajo la tira de instrumental).
        let yTop = geometry.size.height - 2
        for (i, l) in gridLabelPool.enumerated() {
            if i < items.count {
                l.isHidden = false
                l.text = items[i].text
                l.position = CGPoint(x: (railWidth + items[i].x + 2).rounded(), y: yTop)
            } else {
                l.isHidden = true
            }
        }
    }

    private func moveVLines(pool: inout [SKShapeNode], xs: [CGFloat],
                            color: SKColor, width: CGFloat) {
        while pool.count < xs.count {
            let n = SKShapeNode()
            n.path = Self.vline(vlineHeight > 0 ? vlineHeight : size.height)
            n.strokeColor = color
            n.lineWidth = width
            fullGridLayer.addChild(n)
            pool.append(n)
        }
        for (i, n) in pool.enumerated() {
            if i < xs.count {
                n.isHidden = false
                n.position = CGPoint(x: (railWidth + xs[i]).rounded(), y: 0)
            } else {
                n.isHidden = true
            }
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

        // Bandas del carril (rectángulos): cambian de ancho cada frame, así que
        // el `path` se rehace, pero los colores son constantes (solo al crear).
        let laneH = geometry.laneHeight
        ensureShapePool(&bandPool, count: frame.faderBands.count, into: laneLayer) { n in
            n.fillColor = self.laneOpenColor; n.strokeColor = .clear
        }
        for (i, node) in bandPool.enumerated() {
            guard i < frame.faderBands.count else { node.isHidden = true; continue }
            let band = frame.faderBands[i]
            node.isHidden = !band.isOpen
            if band.isOpen {
                node.path = CGPath(rect: CGRect(x: band.xRange.lowerBound, y: 0,
                                                width: band.xRange.upperBound - band.xRange.lowerBound,
                                                height: laneH), transform: nil)
            }
        }

        // Marcas ○ (abre) y ● (cierra): forma y color CONSTANTES → solo `position`.
        ensureShapePool(&openMarkPool, count: frame.openMarks.count, into: marksLayer) { n in
            n.path = Self.dotPath; n.fillColor = .clear; n.strokeColor = self.openColor; n.lineWidth = 2
        }
        for (i, node) in openMarkPool.enumerated() {
            if i < frame.openMarks.count { node.isHidden = false; node.position = frame.openMarks[i] }
            else { node.isHidden = true }
        }
        ensureShapePool(&closeMarkPool, count: frame.closeMarks.count, into: marksLayer) { n in
            n.path = Self.dotPath; n.fillColor = self.closeColor; n.strokeColor = self.closeColor; n.lineWidth = 2
        }
        for (i, node) in closeMarkPool.enumerated() {
            if i < frame.closeMarks.count { node.isHidden = false; node.position = frame.closeMarks[i] }
            else { node.isHidden = true }
        }

        // Phantom clicks: tick vertical CONSTANTE.
        ensureShapePool(&phantomPool, count: frame.phantomMarks.count, into: phantomLayer) { n in
            n.path = Self.phantomTick; n.strokeColor = self.phantomColor; n.fillColor = .clear; n.lineWidth = 2
        }
        for (i, node) in phantomPool.enumerated() {
            if i < frame.phantomMarks.count { node.isHidden = false; node.position = frame.phantomMarks[i] }
            else { node.isHidden = true }
        }

        // la traza del usuario la pinta `renderUserTrace` (mapeo lineal propio,
        // sin techo), no esta capa.

        // Hit marks: forma CONSTANTE; el color sí varía con el nivel de acierto.
        ensureShapePool(&hitPool, count: frame.hitMarks.count, into: hitLayer) { n in
            n.path = Self.hitDotPath; n.lineWidth = 2
        }
        for (i, node) in hitPool.enumerated() {
            guard i < frame.hitMarks.count else { node.isHidden = true; continue }
            let mark = frame.hitMarks[i]
            node.isHidden = false
            node.position = mark.point
            let c = color(for: mark.level)
            node.strokeColor = c
            node.fillColor = mark.closes ? c : .clear
        }
        _ = h
    }

    private func color(for level: HitLevel?) -> SKColor {
        guard let level else { return accentColor }
        return SKColor(level.color)
    }

    private func drawDiscSegments(_ segments: [[CGPoint]]) {
        ensureShapePool(&curvePool, count: segments.count, into: curveLayer) { n in
            n.strokeColor = self.ghostColor; n.lineWidth = 3; n.lineJoin = .round; n.fillColor = .clear
        }
        for (i, node) in curvePool.enumerated() {
            guard i < segments.count, segments[i].count >= 2 else { node.isHidden = true; continue }
            node.isHidden = false
            let path = CGMutablePath()
            path.addLines(between: segments[i])
            node.path = path
        }
    }

    // MARK: - tira de la instrumental

    private func renderStrip(now: Double) {
        let ppq = CGFloat(max(1, patternPPQ))
        let pxPerTick = geometry.pixelsPerBeat / ppq
        let playheadX = geometry.playheadX
        let loop = max(1, instrumentalLoopTicks)
        let imgW = CGFloat(loop) * pxPerTick

        // Fase de la tira: si hay base, la del CABEZAL DEL AUDIO (0…1 del bucle),
        // así la onda que se ve es literalmente donde está sonando y no se
        // descuadra al cambiar el tempo. Sin base, el reloj de ticks.
        let headFrac = instrumentalHeadFraction()
        var phase: Double
        if headFrac >= 0 {
            phase = headFrac * loop
        } else {
            phase = now.truncatingRemainder(dividingBy: loop)
            if phase < 0 { phase += loop }
        }
        let baseX = playheadX - CGFloat(phase) * pxPerTick
        let resize = imgW != lastStripImgW
        if resize { lastStripImgW = imgW }
        for (i, s) in instrSprites.enumerated() {
            s.position = CGPoint(x: baseX + CGFloat(i - 1) * imgW, y: stripHeight / 2)
            if resize { s.size = CGSize(width: imgW, height: stripHeight) }
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

    /// Etiquetas "compás.subdivisión" (`1.1`, `1.2`, …, `2.1`, …) para cada línea
    /// de negra visible. El "1" absoluto (tick 0) es el compás 1, negra 1. No se
    /// etiqueta antes del arranque (negras < 0). Misma X que `gridLines`.
    static func gridLabels(now: Double, width w: CGFloat, playheadX: CGFloat,
                           pxPerTick: CGFloat, ppq: Int,
                           beatsPerBar: Int) -> [(x: CGFloat, text: String)] {
        let tMin = now + Double((0 - playheadX) / pxPerTick)
        let tMax = now + Double((w - playheadX) / pxPerTick)
        let firstBeat = Int((tMin / Double(ppq)).rounded(.up))
        let lastBeat = Int((tMax / Double(ppq)).rounded(.down))
        guard firstBeat <= lastBeat else { return [] }
        let bpb = max(1, beatsPerBar)
        var out: [(x: CGFloat, text: String)] = []
        for b in firstBeat...lastBeat where b >= 0 {
            let x = playheadX + CGFloat(Double(b * ppq) - now) * pxPerTick
            let bar = b / bpb + 1
            let sub = b % bpb + 1
            out.append((x, "\(bar).\(sub)"))
        }
        return out
    }

    // MARK: - rail del sample

    private func renderRail(_ frame: HighwayFrame?) {
        // el rail = el SAMPLE ENTERO, toda la franja de la autopista (0…hh). El
        // eje y la marca tienen forma FIJA (se crean en `layoutContainers`); aquí
        // solo se mueve la aguja en Y y se recoloca el sprite si cambió de tamaño.
        let hh = highwayHeight

        if let s = sampleSprite {
            let target = CGSize(width: hh, height: railWidth)
            if s.size != target { s.size = target }
            let pos = CGPoint(x: railWidth / 2, y: hh / 2)
            if s.position != pos { s.position = pos }
        }

        // la aguja sigue al TEAL: misma Y que la traza del usuario bajo el
        // cabezal (mismo `traceY`), y sube por encima del rail si el plato se
        // pasa del final del sample. Si aun no hay traza, la del fantasma.
        let y = min(size.height, max(-4, railMarkerY(frame, fallback: hh / 2)))
        sampleMarker.position = CGPoint(x: 0, y: y)
    }

    private func railMarkerY(_ frame: HighwayFrame?, fallback: CGFloat) -> CGFloat {
        if let last = userTrace().last { return traceY(last.position) }
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

    /// Como `ensurePool` pero `onCreate` corre UNA vez por nodo nuevo: ahí se fija
    /// la forma y los colores constantes, para que el frame solo mueva `position`.
    private func ensureShapePool(_ pool: inout [SKShapeNode], count: Int,
                                 into parent: SKNode, onCreate: (SKShapeNode) -> Void) {
        while pool.count < count {
            let node = SKShapeNode()
            onCreate(node)
            pool.append(node)
            parent.addChild(node)
        }
    }

    /// Línea vertical local `(0,0)→(0,h)` para rejilla / cabezal (se mueven por X).
    private static func vline(_ h: CGFloat) -> CGPath {
        let p = CGMutablePath(); p.move(to: .zero); p.addLine(to: CGPoint(x: 0, y: h)); return p
    }
}
