// SPDX-License-Identifier: GPL-3.0-only

import Foundation
import CoreGraphics
import AVFoundation
import XFRender
import XFNotation
import XFClock
import XFCapture
import XFDesign   // HitLevel

/// F.4 — exporta una toma grabada (`.xfsession`) como vídeo para compartir: la
/// autopista con el patrón fantasma y **tu línea** encima, animada al tempo de la
/// toma, **con el audio** (el `xf_engine` reproducido offline siguiendo el
/// movimiento grabado). El vídeo sale con la **misma proporción que la ventana
/// de práctica** (`Options.pixelSize(for:)`), no estirado a 9:16.
///
/// Todo lo puro (plan de fotogramas, conversión de la traza, rasterizado de un
/// `HighwayFrame`) es testeable; el `AVAssetWriter` es glue de plataforma.
enum TakeVideoExporter {

    struct Options {
        /// Resolución del vídeo en píxeles. `nil` = **proporcional a la geometría
        /// de la autopista** (`longSide` marca el lado mayor). Antes se forzaba
        /// 1080×1920 vertical sobre un layout apaisado y todo salía estirado.
        var width: Int? = nil
        var height: Int? = nil
        /// Lado mayor del vídeo cuando la resolución se deriva de la geometría.
        var longSide: Int = 1600
        var fps = 30
        /// Ticks de cola tras el final del patrón (1 negra por defecto).
        var leadOutTicks: Double = 480

        /// Tamaño final: el explícito si se dio `width` **y** `height`; si no,
        /// uno con la misma proporción que `g.size` y el lado mayor = `longSide`.
        /// Los dos lados se redondean a par (lo pide el codec H.264).
        func pixelSize(for g: HighwayGeometry) -> CGSize {
            if let w = width, let h = height {
                return CGSize(width: even(w), height: even(h))
            }
            let gw = max(1, g.size.width), gh = max(1, g.size.height)
            let scale = CGFloat(longSide) / max(gw, gh)
            return CGSize(width: even(Int((gw * scale).rounded())),
                          height: even(Int((gh * scale).rounded())))
        }
        private func even(_ v: Int) -> Int { let n = max(2, v); return n - (n % 2) }
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
    ///
    /// Los puntos con el **fader cerrado** (según el carril grabado) se marcan
    /// con nivel `.miss`: `HighwayLayout` los devuelve como tramo aparte y el
    /// rasterizado los pinta apagados — igual que en la práctica en vivo. Sin
    /// esto el vídeo salía todo teal, sin reflejar los cortes.
    static func trace(from session: XFSession, ppq: Int) -> [TracePoint] {
        guard let t0 = session.motion.first?.hostTime else { return [] }
        let hc = HostClock(numer: max(1, session.header.hostNumer),
                           denom: max(1, session.header.hostDenom))
        let bpm = session.header.tempoBPM > 0 ? session.header.tempoBPM : 90
        let tps = bpm / 60 * Double(max(1, ppq))

        // carril de fader grabado (cambios de estado, escaso): estado en `ht` =
        // el del último cambio con `hostTime <= ht`; antes del primero, abierto.
        let fader = session.fader.sorted { $0.hostTime < $1.hostTime }
        func closed(atHostTime ht: UInt64) -> Bool {
            var open = true
            for f in fader where f.hostTime <= ht { open = f.isOpen }
            return !open
        }

        return session.motion.map { m in
            let sec = m.hostTime > t0
                ? hc.nanoseconds(fromHostTicks: m.hostTime - t0) / 1_000_000_000 : 0
            return TracePoint(tick: sec * tps, position: m.position,
                              level: closed(atHostTime: m.hostTime) ? .miss : nil)
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

        // TU línea (F.4: esto es lo que se comparte). Sin scoring offline, el
        // único "nivel" que llega es `.miss` = fader cerrado: ese tramo va gris y
        // a trazos, el resto teal y lleno (como en vivo y en la miniatura).
        ctx.setLineJoin(.round)
        for poly in frame.userSegments {
            let cut = poly.level == .miss
            ctx.setStrokeColor(cut ? rgb(0x9AA5B1, 0.7) : rgb(0x34E1C4))
            ctx.setLineWidth(cut ? 2.5 : 4)
            ctx.setLineDash(phase: 0, lengths: cut ? [5, 5] : [])
            strokePolyline(poly.points, in: ctx)
        }
        ctx.setLineDash(phase: 0, lengths: [])   // restaura para lo que siga

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

    /// Renderiza el vídeo en `url` (mp4, H.264). Si se pasa `scratchPCM` (y
    /// opcionalmente `instrumental`), **añade el audio** de la toma: el
    /// `xf_engine` reproducido offline siguiendo el movimiento grabado (F.4).
    /// `progress` (0…1) y `completion` se llaman en cola de fondo.
    static func export(session: XFSession, scratch: Scratch,
                       geometry g: HighwayGeometry, options o: Options = Options(),
                       scratchPCM: [Float]? = nil,
                       instrumental: (pcm: [Float], nativeBPM: Double)? = nil,
                       to url: URL,
                       progress: ((Double) -> Void)? = nil,
                       completion: @escaping (Result<URL, Error>) -> Void) {
        guard session.motion.count > 1 else { completion(.failure(ExportError.sessionEmpty)); return }

        DispatchQueue.global(qos: .userInitiated).async {
            let tmp = FileManager.default.temporaryDirectory
            let tmpVideo = tmp.appendingPathComponent("xflare-vid-\(UUID().uuidString).mp4")
            let tmpAudio = tmp.appendingPathComponent("xflare-aud-\(UUID().uuidString).caf")
            defer {
                try? FileManager.default.removeItem(at: tmpVideo)
                try? FileManager.default.removeItem(at: tmpAudio)
            }
            do {
                let bpm = session.header.tempoBPM > 0 ? session.header.tempoBPM : 90
                let ticks = framePlan(lengthTicks: Double(scratch.lengthTicks), bpm: bpm,
                                      ppq: scratch.ppq, fps: o.fps, leadOutTicks: o.leadOutTicks)
                let seconds = ticks.last! / (bpm / 60 * Double(scratch.ppq))

                // 1) vídeo mudo a un temporal (el 90 % del progreso)
                try writeVideo(session: session, scratch: scratch, geometry: g, options: o,
                               ticks: ticks, to: tmpVideo,
                               progress: { progress?($0 * 0.9) })

                // 2) si hay sample, render de audio + mux -> url final
                try? FileManager.default.removeItem(at: url)
                if let s = scratchPCM, s.count > 1 {
                    let a = TakeAudioRenderer.render(session: session, scratch: scratch,
                                                    scratchPCM: s, instrumental: instrumental,
                                                    durationSeconds: seconds)
                    try writeCAF(a, to: tmpAudio)
                    progress?(0.95)
                    try mux(video: tmpVideo, audio: tmpAudio, to: url)
                } else {
                    try FileManager.default.moveItem(at: tmpVideo, to: url)
                }
                progress?(1)
                completion(.success(url))
            } catch {
                completion(.failure(error))
            }
        }
    }

    /// El bucle de fotogramas: escribe el vídeo mudo en `dst`.
    private static func writeVideo(session: XFSession, scratch: Scratch,
                                   geometry g: HighwayGeometry, options o: Options,
                                   ticks: [Double], to dst: URL,
                                   progress: (Double) -> Void) throws {
        let size = o.pixelSize(for: g)
        let pw = Int(size.width), ph = Int(size.height)
        let writer = try AVAssetWriter(outputURL: dst, fileType: .mp4)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: pw, AVVideoHeightKey: ph,
        ])
        input.expectsMediaDataInRealTime = false
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: pw,
                kCVPixelBufferHeightKey as String: ph,
            ])
        guard writer.canAdd(input) else { throw ExportError.writer }
        writer.add(input)
        guard writer.startWriting() else { throw writer.error ?? ExportError.writer }
        writer.startSession(atSourceTime: .zero)

        let layout = HighwayLayout(scratch: scratch)
        let fullTrace = trace(from: session, ppq: scratch.ppq)
        let px = size
        // ventana de traza visible: pasado reciente hasta "ahora". Sin esto se
        // pintaba la linea entera desde el fotograma 1 y el video parecia una
        // foto larga desplazandose, no una captura en vivo.
        let historyTicks = Double(scratch.ppq) * 12

        let total = max(1, ticks.count)
        for (i, tick) in ticks.enumerated() {
            while !input.isReadyForMoreMediaData { Thread.sleep(forTimeInterval: 0.005) }
            let visible = fullTrace.filter { $0.tick <= tick && $0.tick >= tick - historyTicks }
            let frame = layout.frame(atTick: tick, geometry: g, userTrace: visible)
            guard let img = render(frame, geometry: g, pixelSize: px),
                  let pool = adaptor.pixelBufferPool,
                  let buf = pixelBuffer(from: img, pool: pool) else { throw ExportError.render }
            adaptor.append(buf, withPresentationTime:
                CMTime(value: CMTimeValue(i), timescale: CMTimeScale(o.fps)))
            progress(Double(i + 1) / Double(total))
        }

        input.markAsFinished()
        let done = DispatchSemaphore(value: 0)
        writer.finishWriting { done.signal() }
        done.wait()
        guard writer.status == .completed else { throw writer.error ?? ExportError.writer }
    }

    /// Escribe el PCM del render a un CAF float32 estereo.
    private static func writeCAF(_ a: TakeAudioRenderer.Rendered, to url: URL) throws {
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: a.sampleRate,
            AVNumberOfChannelsKey: 2,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsNonInterleaved: true,
        ]
        let file = try AVAudioFile(forWriting: url, settings: settings,
                                   commonFormat: .pcmFormatFloat32, interleaved: false)
        guard let buf = AVAudioPCMBuffer(pcmFormat: file.processingFormat,
                                         frameCapacity: AVAudioFrameCount(a.frames)) else {
            throw ExportError.writer
        }
        buf.frameLength = AVAudioFrameCount(a.frames)
        if let ch = buf.floatChannelData {
            let bytes = a.frames * MemoryLayout<Float>.size
            a.left.withUnsafeBufferPointer { src in _ = memcpy(ch[0], src.baseAddress, bytes) }
            a.right.withUnsafeBufferPointer { src in _ = memcpy(ch[1], src.baseAddress, bytes) }
        }
        try file.write(from: buf)
    }

    /// Combina la pista de vídeo de `video` y la de audio de `audio` en un mp4.
    private static func mux(video: URL, audio: URL, to out: URL) throws {
        let comp = AVMutableComposition()
        let vAsset = AVURLAsset(url: video)
        let aAsset = AVURLAsset(url: audio)
        guard let vSrc = vAsset.tracks(withMediaType: .video).first,
              let vDst = comp.addMutableTrack(withMediaType: .video,
                                              preferredTrackID: kCMPersistentTrackID_Invalid) else {
            throw ExportError.writer
        }
        try vDst.insertTimeRange(CMTimeRange(start: .zero, duration: vAsset.duration),
                                 of: vSrc, at: .zero)
        if let aSrc = aAsset.tracks(withMediaType: .audio).first,
           let aDst = comp.addMutableTrack(withMediaType: .audio,
                                           preferredTrackID: kCMPersistentTrackID_Invalid) {
            let d = min(vAsset.duration, aAsset.duration)
            try aDst.insertTimeRange(CMTimeRange(start: .zero, duration: d), of: aSrc, at: .zero)
        }
        guard let ex = AVAssetExportSession(asset: comp,
                                            presetName: AVAssetExportPresetHighestQuality) else {
            throw ExportError.writer
        }
        ex.outputURL = out
        ex.outputFileType = .mp4
        let sem = DispatchSemaphore(value: 0)
        ex.exportAsynchronously { sem.signal() }
        sem.wait()
        guard ex.status == .completed else { throw ex.error ?? ExportError.writer }
    }

    // MARK: - helpers

    private static func rgb(_ hex: Int, _ alpha: CGFloat = 1) -> CGColor {
        CGColor(red: CGFloat((hex >> 16) & 0xFF) / 255,
                green: CGFloat((hex >> 8) & 0xFF) / 255,
                blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
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
