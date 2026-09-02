// SPDX-License-Identifier: GPL-3.0-only

import SpriteKit

/// Escena SpriteKit para las dos tiras de onda (instrumental arriba, sample
/// abajo). Es `SKScene` **a propósito**: así comparte el mismo reloj de frame
/// (`update(_:)` síncrono por vsync) que `HighwayScene`, y la rejilla de la tira
/// de la instrumental cae en la MISMA X que la de la autopista sin desfase.
///
/// La onda va como **textura pre-renderizada** (`WaveformImage`); cada frame
/// solo se mueve el sprite → coste ~nulo.
final class WaveformScene: SKScene {

    enum Mode {
        /// Instrumental: hace loop cada `loopTicks`, con rejilla de compás/negra.
        case looping
        /// Sample: ventana que sigue a `progress` (0…1) bajo una aguja fija.
        case windowed
    }

    var mode: Mode = .windowed

    // --- parámetros looping ---
    var loopTicks: Double = 1
    var ppq: Int = 480
    var patternLen: Int = 1
    var beatsPerBar = 4
    var pixelsPerBeat: CGFloat = 120
    var playheadFraction: CGFloat = 0.30
    var currentTick: () -> Double = { 0 }

    // --- parámetros windowed ---
    var visibleFraction: CGFloat = 0.9
    var needleFraction: CGFloat = 0.30
    var progress: () -> Double = { 0 }

    /// Imagen de la onda entera (color por frecuencia). Al ponerla, se rehacen
    /// los sprites.
    var image: CGImage? { didSet { rebuildSprites() } }

    private var sprites: [SKSpriteNode] = []
    private var texture: SKTexture?
    private var beatPool: [SKShapeNode] = []
    private var barPool: [SKShapeNode] = []
    private let needleNode = SKShapeNode()
    private let axisNode = SKShapeNode()

    private let beatColor = SKColor(red: 0x3A/255, green: 0x44/255, blue: 0x4F/255, alpha: 1)
    private let barColor  = SKColor(red: 0x5A/255, green: 0x66/255, blue: 0x74/255, alpha: 1)
    private let needleCol = SKColor(red: 0x34/255, green: 0xE1/255, blue: 0xC4/255, alpha: 0.6)
    private let axisCol   = SKColor(red: 0x2A/255, green: 0x32/255, blue: 0x3B/255, alpha: 1)

    override init(size: CGSize) {
        super.init(size: size)
        scaleMode = .resizeFill
        backgroundColor = SKColor(red: 0x11/255, green: 0x14/255, blue: 0x18/255, alpha: 1)
        axisNode.strokeColor = axisCol
        axisNode.lineWidth = 1
        needleNode.strokeColor = needleCol
        needleNode.lineWidth = 1.5
        addChild(axisNode)
        addChild(needleNode)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    private func rebuildSprites() {
        sprites.forEach { $0.removeFromParent() }
        sprites = []
        guard let image else { texture = nil; return }
        let tex = SKTexture(cgImage: image)
        tex.filteringMode = .linear
        texture = tex
        let n = mode == .looping ? 3 : 1
        for _ in 0..<n {
            let s = SKSpriteNode(texture: tex)
            s.anchorPoint = CGPoint(x: 0, y: 0.5)
            s.zPosition = -1
            addChild(s)
            sprites.append(s)
        }
    }

    override func update(_ currentTime: TimeInterval) {
        let w = size.width, h = size.height
        guard w > 1, h > 4 else { return }

        // línea de reposo (solo en el sample)
        if mode == .windowed {
            let p = CGMutablePath()
            p.move(to: CGPoint(x: 0, y: h / 2)); p.addLine(to: CGPoint(x: w, y: h / 2))
            axisNode.path = p
        } else {
            axisNode.path = nil
        }

        switch mode {
        case .looping:
            let pxPerTick = pixelsPerBeat / CGFloat(max(1, ppq))
            let playheadX = w * playheadFraction
            let now = currentTick()
            let imgW = CGFloat(loopTicks) * pxPerTick
            var phase = now.truncatingRemainder(dividingBy: loopTicks)
            if phase < 0 { phase += loopTicks }
            let baseX = playheadX - CGFloat(phase) * pxPerTick
            for (i, s) in sprites.enumerated() {
                s.position = CGPoint(x: baseX + CGFloat(i - 1) * imgW, y: h / 2)
                s.size = CGSize(width: imgW, height: h)
            }
            layoutGrid(now: now, pxPerTick: pxPerTick, playheadX: playheadX, w: w, h: h)
            setNeedle(x: playheadX, h: h)

        case .windowed:
            if let s = sprites.first {
                let p = max(0, min(1, CGFloat(progress())))
                let f0 = p - needleFraction * visibleFraction
                let sw = w / max(0.01, visibleFraction)
                s.position = CGPoint(x: -f0 / max(0.01, visibleFraction) * w, y: h / 2)
                s.size = CGSize(width: sw, height: h)
            }
            hideGrid()
            setNeedle(x: (w * needleFraction).rounded(), h: h)
        }
    }

    // MARK: - rejilla

    private func layoutGrid(now: Double, pxPerTick: CGFloat, playheadX: CGFloat,
                            w: CGFloat, h: CGFloat) {
        let tMin = now + Double((0 - playheadX) / pxPerTick)
        let tMax = now + Double((w - playheadX) / pxPerTick)
        let bpb = max(1, beatsPerBar)
        let firstBeat = Int((tMin / Double(ppq)).rounded(.up))
        let lastBeat = Int((tMax / Double(ppq)).rounded(.down))

        var beats: [CGFloat] = []
        var bars: [CGFloat] = []
        if firstBeat <= lastBeat {
            for b in firstBeat...lastBeat {
                let t = Double(b * ppq)
                let m = t.truncatingRemainder(dividingBy: Double(patternLen))
                let beatInPattern = Int(m < 0 ? m + Double(patternLen) : m) / ppq
                let x = playheadX + CGFloat(t - now) * pxPerTick
                if beatInPattern % bpb == 0 { bars.append(x) } else { beats.append(x) }
            }
        }
        place(&beatPool, at: beats, color: beatColor, width: 1, h: h)
        place(&barPool, at: bars, color: barColor, width: 1.5, h: h)
    }

    private func hideGrid() {
        for n in beatPool { n.isHidden = true }
        for n in barPool { n.isHidden = true }
    }

    private func place(_ pool: inout [SKShapeNode], at xs: [CGFloat],
                       color: SKColor, width: CGFloat, h: CGFloat) {
        while pool.count < xs.count {
            let n = SKShapeNode()
            n.lineWidth = width
            n.strokeColor = color
            addChild(n)
            pool.append(n)
        }
        for (i, n) in pool.enumerated() {
            if i < xs.count {
                n.isHidden = false
                let p = CGMutablePath()
                p.move(to: CGPoint(x: xs[i].rounded(), y: 0))
                p.addLine(to: CGPoint(x: xs[i].rounded(), y: h))
                n.path = p
            } else {
                n.isHidden = true
            }
        }
    }

    private func setNeedle(x: CGFloat, h: CGFloat) {
        let p = CGMutablePath()
        p.move(to: CGPoint(x: x, y: 0)); p.addLine(to: CGPoint(x: x, y: h))
        needleNode.path = p
    }
}
