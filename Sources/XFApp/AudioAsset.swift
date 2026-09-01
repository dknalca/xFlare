// SPDX-License-Identifier: GPL-3.0-only

import Foundation
import AVFoundation

/// Carga ficheros de audio (WAV, MP3, …) a **PCM mono float** a la frecuencia que
/// pide el motor. Decodifica y remezcla/reamuestrea de una vez con
/// `AVAudioConverter`; no es RT (se llama al preparar la sesión).
///
/// Rutas de los assets de la práctica rudimentaria:
///  - scratch: `Audio/Sample Scratchs/Ahh.wav`  (grabación propia del autor)
///  - base:    `Audio/Intrumental loops/080bpm_beat.wav`  (loop a 80 BPM)
/// En dev se leen del repo (`RepoContentLoader`); empaquetarlos en el `.app` es
/// parte de B12a.
public enum AudioAsset {

    public static let scratchRelPath = "Audio/Sample Scratchs/Ahh.wav"
    public static let instrumentalRelPath = "Audio/Intrumental loops/080bpm_beat.wav"
    /// Tempo al que está grabado el loop instrumental (va en el nombre).
    public static let instrumentalNativeBPM: Double = 80
    /// Parte útil del sample de scratch: del principio a esta fracción. El final
    /// suele quedar casi inaudible; no se scratchea más allá de aquí.
    public static let scratchUsableFraction: Double = 0.6

    /// Decodifica `url` a mono float a `sampleRate`. `nil` si no se puede abrir.
    public static func loadMono(_ url: URL, sampleRate: Double = 48_000) -> [Float]? {
        guard let file = try? AVAudioFile(forReading: url) else { return nil }
        let inFormat = file.processingFormat
        let inFrames = AVAudioFrameCount(file.length)
        guard inFrames > 0,
              let inBuf = AVAudioPCMBuffer(pcmFormat: inFormat, frameCapacity: inFrames),
              (try? file.read(into: inBuf)) != nil else { return nil }

        guard let outFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32,
                                            sampleRate: sampleRate, channels: 1,
                                            interleaved: false),
              let converter = AVAudioConverter(from: inFormat, to: outFormat) else { return nil }

        let ratio = sampleRate / inFormat.sampleRate
        let outCap = AVAudioFrameCount(Double(inBuf.frameLength) * ratio) + 4096
        guard let outBuf = AVAudioPCMBuffer(pcmFormat: outFormat, frameCapacity: outCap) else {
            return nil
        }

        var provided = false
        var convError: NSError?
        let status = converter.convert(to: outBuf, error: &convError) { _, inStatus in
            if provided { inStatus.pointee = .noDataNow; return nil }
            provided = true
            inStatus.pointee = .haveData
            return inBuf
        }
        guard status != .error, let ch = outBuf.floatChannelData, outBuf.frameLength > 0 else {
            return nil
        }
        return Array(UnsafeBufferPointer(start: ch[0], count: Int(outBuf.frameLength)))
    }

    /// Atajo: resuelve la ruta con el `ContentLoader` y decodifica.
    public static func loadMono(_ relativePath: String, from content: ContentLoader,
                                sampleRate: Double = 48_000) -> [Float]? {
        guard let u = content.url(relativePath) else { return nil }
        return loadMono(u, sampleRate: sampleRate)
    }
}
