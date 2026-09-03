// SPDX-License-Identifier: GPL-3.0-only

import Foundation

/// Detección del **punto cero** de un sample que trae el usuario (F.3): dónde
/// empieza el sonido de verdad, para que la práctica arranque limpia.
///
/// Dos problemas al cargar un WAV cualquiera:
///  1. Suele traer silencio (o ruido de fondo) por delante y por detrás. La
///     posición 0 del patrón y el cue 1 deben caer en el **ataque**, no en el
///     hueco.
///  2. Si el recorte cae a mitad de una onda, al scratchear desde ahí se oye un
///     *click*. Hay que **cuadrar a un cruce por cero**.
///
/// Todo puro (sin audio en vivo, sin UI): se llama al preparar la sesión, igual
/// que `AudioAsset.loadMono`.
enum SampleTrim {

    /// Primer frame con sonido: se busca la primera ventana cuyo RMS supera
    /// `silenceDBFS`, se retrocede `lookbackMs` para no morder el transitorio y
    /// se cuadra al cruce por cero anterior. `0` si el sample es todo silencio o
    /// ya empieza sonando.
    static func detectStart(_ pcm: [Float], sampleRate: Double,
                            silenceDBFS: Float = -45, lookbackMs: Double = 8) -> Int {
        guard pcm.count > 1, sampleRate > 0 else { return 0 }
        let win = max(1, Int(sampleRate * 0.005))               // ~5 ms
        let thresh = powf(10, silenceDBFS / 20)                 // dBFS -> lineal

        var attack = pcm.count
        var i = 0
        while i + win <= pcm.count {
            if windowRMS(pcm, i, win) >= thresh { attack = i; break }
            i += win
        }
        if attack >= pcm.count { return 0 }                     // todo por debajo del umbral

        let lookback = Int(sampleRate * lookbackMs / 1000)
        let target = max(0, attack - lookback)
        return zeroCrossingAtOrBefore(pcm, target, limit: win * 2)
    }

    /// Último frame con sonido (simétrico a `detectStart`). `pcm.count` si el
    /// final ya suena o todo es silencio.
    static func detectEnd(_ pcm: [Float], sampleRate: Double,
                          silenceDBFS: Float = -45, tailMs: Double = 8) -> Int {
        guard pcm.count > 1, sampleRate > 0 else { return pcm.count }
        let win = max(1, Int(sampleRate * 0.005))
        let thresh = powf(10, silenceDBFS / 20)

        var release = -1
        var i = pcm.count - win
        while i >= 0 {
            if windowRMS(pcm, i, win) >= thresh { release = i + win; break }
            i -= win
        }
        if release < 0 { return pcm.count }

        let tail = Int(sampleRate * tailMs / 1000)
        let target = min(pcm.count, release + tail)
        return zeroCrossingAtOrAfter(pcm, target, limit: win * 2)
    }

    /// Recorta silencio de cabeza y cola, cuadrado a cruces por cero. Devuelve el
    /// PCM recortado y el `startFrame` (offset original, por si hay que mapear
    /// tiempos). Si el recorte no deja nada útil, devuelve el original sin tocar.
    static func trimmed(_ pcm: [Float], sampleRate: Double) -> (pcm: [Float], startFrame: Int) {
        let s = detectStart(pcm, sampleRate: sampleRate)
        let e = detectEnd(pcm, sampleRate: sampleRate)
        guard s < e, e - s >= Int(sampleRate * 0.02) else { return (pcm, 0) }   // < 20 ms: no fiarse
        if s == 0 && e == pcm.count { return (pcm, 0) }
        return (Array(pcm[s..<e]), s)
    }

    // MARK: - interno

    private static func windowRMS(_ pcm: [Float], _ start: Int, _ len: Int) -> Float {
        var acc: Float = 0
        for k in start..<(start + len) { acc += pcm[k] * pcm[k] }
        return (acc / Float(len)).squareRoot()
    }

    /// Cruce por cero en `[from - limit, from]`, prefiriendo el más cercano a
    /// `from`. Si no hay ninguno, `from` acotado a `[0, count)`.
    private static func zeroCrossingAtOrBefore(_ pcm: [Float], _ from: Int, limit: Int) -> Int {
        let hi = min(from, pcm.count - 1)
        let lo = max(1, hi - limit)
        if hi <= 0 { return 0 }
        var j = hi
        while j > lo {
            if pcm[j] == 0 || (pcm[j - 1] < 0) != (pcm[j] < 0) { return j }
            j -= 1
        }
        return max(0, from)
    }

    private static func zeroCrossingAtOrAfter(_ pcm: [Float], _ from: Int, limit: Int) -> Int {
        let lo = max(1, min(from, pcm.count - 1))
        let hi = min(pcm.count - 1, lo + limit)
        var j = lo
        while j < hi {
            if pcm[j] == 0 || (pcm[j - 1] < 0) != (pcm[j] < 0) { return j }
            j += 1
        }
        return min(pcm.count, from)
    }
}
