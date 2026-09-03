// SPDX-License-Identifier: GPL-3.0-only

import Foundation
import CoreGraphics
import AVFoundation
import XFRender
import XFNotation
import XFClock
import XFCapture
import XFDesign   // HitLevel

/// F.4 — exporta una toma grabada (`.xfsession`) como **vídeo vertical 9:16**
/// para compartir: la autopista con el patrón fantasma y **tu línea** encima,
/// animada al tempo de la toma. Sin audio en esta versión (necesita un render
/// offline del motor; ver `TODO.md` F.4).
///
/// Todo lo puro (plan de fotogramas, conversión de la traza, rasterizado de un
/// `HighwayFrame`) es testeable; el `AVAssetWriter` es glue de plataforma.
enum TakeVideoExporter {

    struct Options {
        var width = 1080
        var height = 1920
        var fps = 30
        /// Ticks de cola tras el final del patrón (1 negra por defecto).
        var leadOutTicks: Double = 480
    }

    enum ExportError: Error { case sessionEmpty, writer, render }

    // MARK: - puro

    /// Los `currentTick` de cada fotograma, de 0 al final del patrón + la cola.
    static func framePlan(lengthTicks: Double, bpm: Double, ppq: Int,
                          fps: Int, leadOutTicks: Double = 480) -> [Double] {
        let ticksPerSecond = max(1e-6, bpm / 60 * Double(ppq))
        let totalTicks = max(1, lengthTicks) + max(0, leadOutTicks)
        let seconds = totalTicks / ticksPerSecond
        let n = max(1, Int((seconds * Double(max(1, fps))).rounded(.up)))
        let dt = totalTicks / Double(n)
        return (0...n).map { Double($0) * dt }
    }

    /// La traza del usuario a partir de una toma grabada, en el dominio de ticks
    /// del patrón (lista para `HighwayLayout.frame(userTrace:)`).
    static func trace(from session: XFSession, ppq: Int) -> [TracePoint] {
        guard let t0 = session.motion.first?.hostTime else { return [] }
        let hc = HostClock(numer: max(1, session.header.hostNumer),
                           denom: max(1, session.header.hostDenom))
        let bpm = session.header.tempoBPM > 0 ? session.header.tempoBPM : 90
        let tps = bpm / 60 * Double(max(1, ppq))
        return session.motion.map { m in
            let sec = m.hostTime > t0
                ? hc.nanoseconds(fromHostTicks: m.hostTime - t0) / 1_000_000_000 : 0
            return TracePoint(tick: sec * tps, position: m.position, level: nil)
        }
    }

    // MARK: - rasterizado de un HighwayFrame

    /// Dibuja `frame` en un bitmap de `pixelSize`. El espacio del layout
    /// (`g.size`) se escala al del vídeo. Y hacia arriba en los dos (como
    /// SpriteKit y como el bitmap de Core Graphics), así que no se voltea.
    static func render(_ frame: HighwayFrame, geometry g: HighwayGeometry,
                       pixelSize: CGSize) -> CGImage? {
        let cs = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: nil, width: Int(pixelSize.width), height: Int(pixelSize.height),
            bitsPerComponent: 8, bytesPerRow: 0, space: cs,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }

        ctx.scaleBy(x: pixelSize.width / max(1, g.size.width),
                    y: pixelSize.height / max(1, g.size.height))
        draw(frame, geometry: g, into: ctx)
        return ctx.makeImage()
    }

    private static func draw(_ frame: HighwayFrame, geometry g: HighwayGeometry,
                             into ctx: CGContext) {
        let W = g.size.width, H = g.size.height

        ctx.setFillColor(rgb(0x0B0D10))
        ctx.fill(CGRect(x: 0, y: 0, width: W, height: H))

        // carril de fader (tramos abiertos), franja inferior
        ctx.setFillColor(rgb(0xF2F5F7, 0.10))
        for band in frame.faderBands where band.isOpen {
            ctx.fill(CGRect(x: band.xRange.lowerBound, y: 0,
                            width: band.xRange.upperBound - band.xRange.lowerBound,
                            height: g.laneHeight))
        }

        // rejilla: negras y compás
        strokeVerticals(frame.beatLines, height: H, width: 1, color: rgb(0x3A444F), in: ctx)
        strokeVerticals(frame.barLines,  height: H, width: 2, color: rgb(0x232A32), in: ctx)

        // cabeza de lectura
        strokeVerticals([frame.playheadX], height: H, width: 1, color: rgb(0x3A444F), in: ctx)

        // curva del patrón (fantasma), partida por el fader si viene troceada
        ctx.setLineWidth(3); ctx.setLineJoin(.round)
        ctx.setStrokeColor(rgb(0x7A8794, 0.55))
        let ghost = frame.discSegments.isEmpty ? [frame.discCurve] : frame.discSegments
        for seg in ghost { strokePolyline(seg, in: ctx) }

        // TU línea, teñida por nivel de acierto (F.4: esto es lo que se comparte)
        ctx.setLineWidth(4)
        for poly in frame.userSegments {
            ctx.setStrokeColor(hitColor(poly.level))
            strokePolyline(poly.points, in: ctx)
        }

        // marcas de fader: ○ abre, ● cierra
        ctx.setLineWidth(2)
        for p in frame.openMarks {
            ctx.setStrokeColor(rgb(0x7A8794))
            ctx.strokeEllipse(in: CGRect(x: p.x - 5, y: p.y - 5, width: 10, height: 10))
        }
        ctx.setFillColor(rgb(0x34E1C4))
        for p in frame.closeMarks {
            ctx.fillEllipse(in: CGRect(x: p.x - 5, y: p.y - 5, width: 10, height: 10))
        }

        // phantom clicks: tick vertical corto sobre la curva
        ctx.setStrokeColor(rgb(0x7A8794, 0.6))
        for p in frame.phantomMarks {
            ctx.move(to: CGPoint(x: p.x, y: p.y - 5))
            ctx.addLine(to: CGPoint(x: p.x, y: p.y + 5))
            ctx.strokePath()
        }
    }

    // MARK: - export (glue AVFoundation)

    /// Renderiza el vídeo en `url` (mp4, H.264). `completion` en cola de fondo.
    static func export(session: XFSession, scratch: Scratch,
                       geometry g: HighwayGeometry, options o: Options = Options(),
                       to url: URL,
                       completion: @escaping (Result<URL, Error>) -> Void) {
        guard session.motion.count > 1 else { completion(.failure(ExportError.sessionEmpty)); return }

        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try? FileManager.default.removeItem(at: url)
                let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
                let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
                    AVVideoCodecKey: AVVideoCodecType.h264,
                    AVVideoWidthKey: o.width, AVVideoHeightKey: o.height,
                ])
                input.expectsMediaDataInRealTime = false
                let adaptor = AVAssetWriterInputPixelBufferAdaptor(
                    assetWriterInput: input,
                    sourcePixelBufferAttributes: [
                        kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                        kCVPixelBufferWidthKey as String: o.width,
                        kCVPixelBufferHeightKey as String: o.height,
                    ])
                guard writer.canAdd(input) else { throw ExportError.writer }
                writer.add(input)
                guard writer.startWriting() else { throw writer.error ?? ExportError.writer }
                writer.startSession(atSourceTime: .zero)

                let layout = HighwayLayout(scratch: scratch)
                let trace = trace(from: session, ppq: scratch.ppq)
                let bpm = session.header.tempoBPM > 0 ? session.header.tempoBPM : 90
                let ticks = framePlan(lengthTicks: Double(scratch.lengthTicks), bpm: bpm,
                                      ppq: scratch.ppq, fps: o.fps, leadOutTicks: o.leadOutTicks)
                let px = CGSize(width: o.width, height: o.height)

                for (i, tick) in ticks.enumerated() {
                    while !input.isReadyForMoreMediaData { Thread.sleep(forTimeInterval: 0.005) }
                    let frame = layout.frame(atTick: tick, geometry: g, userTrace: trace)
                    guard let img = render(frame, geometry: g, pixelSize: px),
                          let pool = adaptor.pixelBufferPool,
                          let buf = pixelBuffer(from: img, pool: pool) else { throw ExportError.render }
                    let time = CMTime(value: CMTimeValue(i), timescale: CMTimeScale(o.fps))
                    adaptor.append(buf, withPresentationTime: time)
                }

                input.markAsFinished()
                let done = DispatchSemaphore(value: 0)
                writer.finishWriting { done.signal() }
                done.wait()
                if writer.status == .completed {
                    completion(.success(url))
                } else {
                    completion(.failure(writer.error ?? ExportError.writer))
                }
            } catch {
                completion(.failure(error))
            }
        }
    }

    // MARK: - helpers

    private static func rgb(_ hex: Int, _ alpha: CGFloat = 1) -> CGColor {
        CGColor(red: CGFloat((hex >> 16) & 0xFF) / 255,
                green: CGFloat((hex >> 8) & 0xFF) / 255,
                blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
    }

    private static func hitColor(_ level: HitLevel?) -> CGColor {
        switch level {
        case .none, .perfect: return rgb(0x34E1C4)          // teal (bien / acento)
        case .great:          return rgb(0x5AD07A)          // verde
        case .good:           return rgb(0xF5C542)          // ámbar
        case .offbeat:        return rgb(0xF08A3C)          // naranja
        case .miss:           return rgb(0xFF4D5E)          // rojo
        @unknown default:     return rgb(0x34E1C4)
        }
    }

    private static func strokeVerticals(_ xs: [CGFloat], height: CGFloat, width: CGFloat,
                                        color: CGColor, in ctx: CGContext) {
        guard !xs.isEmpty else { return }
        ctx.setLineWidth(width); ctx.setStrokeColor(color)
        for x in xs {
            ctx.move(to: CGPoint(x: x, y: 0))
            ctx.addLine(to: CGPoint(x: x, y: height))
        }
        ctx.strokePath()
    }

    private static func strokePolyline(_ pts: [CGPoint], in ctx: CGContext) {
        guard pts.count >= 2 else { return }
        ctx.move(to: pts[0])
        for p in pts.dropFirst() { ctx.addLine(to: p) }
        ctx.strokePath()
    }

    private static func pixelBuffer(from image: CGImage, pool: CVPixelBufferPool) -> CVPixelBuffer? {
        var out: CVPixelBuffer?
        guard CVPixelBufferPoolCreatePixelBuffer(nil, pool, &out) == kCVReturnSuccess,
              let buf = out else { return nil }
        CVPixelBufferLockBaseAddress(buf, [])
        defer { CVPixelBufferUnlockBaseAddress(buf, []) }
        guard let ctx = CGContext(
            data: CVPixelBufferGetBaseAddress(buf),
            width: CVPixelBufferGetWidth(buf), height: CVPixelBufferGetHeight(buf),
            bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(buf),
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
                | CGBitmapInfo.byteOrder32Little.rawValue) else { return nil }
        ctx.draw(image, in: CGRect(x: 0, y: 0,
                                   width: CGFloat(CVPixelBufferGetWidth(buf)),
                                   height: CGFloat(CVPixelBufferGetHeight(buf))))
        return buf
    }
}
