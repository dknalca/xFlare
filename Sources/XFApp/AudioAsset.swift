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
    /// Dónde cae el **pico del patrón** dentro del sample: el punto más alto de
    /// la curva del baby mapea a esta fracción del sample. El plato puede seguir
    /// scratcheando más allá, hasta el final del sample (`posHi`).
    ///
    /// La CURVA del patrón, en cambio, llena la autopista de arriba abajo
    /// (`HighwayGeometry.patternFill` = 1.0; revisado 2026-09-02: antes 2/3, con
    /// el tercio de arriba reservado — ADR-041 — que se leía como un techo y
    /// dejaba mucho hueco vacío). Pasarse del pico lleva la traza por encima del
    /// borde superior, que se recorta, como en un vinilo de verdad.
    public static let scratchPatternTopFraction: Double = 2.0 / 3.0

    /// Duración **máxima** del sample de scratch, en segundos. El movimiento del
    /// plato mapea a una fracción del sample entero (`normalizedPosition`), así
    /// que un fichero largo (una canción de 3 min) haría que el mismo gesto
    /// barriera minutos de audio — "se va todo". Se recorta la carga a esta
    /// ventana para que cualquier sample se scratchee como el `Ahh` de ejemplo
    /// (~1 s) y el rail muestre siempre los mismos segundos.
    public static let scratchMaxSeconds: Double = 2.0

    /// Recorta `pcm` a `scratchMaxSeconds` (deja igual lo que ya sea más corto).
    /// Se aplica al cargar un sample de scratch para que un fichero largo no
    /// mapee minutos de audio al recorrido del plato.
    public static func capScratch(_ pcm: [Float], sampleRate: Double) -> [Float] {
        let cap = max(1, Int(scratchMaxSeconds * sampleRate))
        return pcm.count > cap ? Array(pcm.prefix(cap)) : pcm
    }

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
