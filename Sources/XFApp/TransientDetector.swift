// SPDX-License-Identifier: GPL-3.0-only

import Foundation

/// Detector **puro** de transitorios (onsets) de un PCM mono. Para el editor de
/// samples: propone dónde empieza cada golpe / sílaba para poder poner ahí el
/// inicio del recorte y luego afinar a mano.
///
/// Método sencillo (sin FFT, así es barato y fácil de leer): envolvente de
/// energía en tramos de ~5 ms, flujo positivo (subidas de energía), umbral
/// adaptativo con la media local y elección de picos con separación mínima. No
/// pretende marcar cada micro-transitorio de una batería — un sample de scratch
/// suele ser una frase con unos pocos ataques claros, y eso es lo que interesa.
enum TransientDetector {

    /// Onsets en **segundos** desde el inicio del PCM. `sensitivity` (0,5…2):
    /// más alto = umbral más bajo = más onsets. Devuelve `[]` si el audio es
    /// demasiado corto o está en silencio.
    static func onsets(_ pcm: [Float], sampleRate sr: Double,
                       sensitivity: Double = 1.0) -> [Double] {
        guard sr > 0, pcm.count > Int(sr * 0.05) else { return [] }

        let hop = max(1, Int(sr * 0.005))          // ~5 ms entre tramos
        let win = hop * 2                          // ventana de energía (solapada)
        let frames = (pcm.count - win) / hop + 1
        guard frames > 4 else { return [] }

        // log-energía por tramo: el log comprime el rango y hace que una subida
        // relativa cuente igual en pasajes fuertes y flojos.
        var energy = [Double](repeating: 0, count: frames)
        for k in 0..<frames {
            let s = k * hop
            let end = s + win
            var acc = 0.0
            var i = s
            while i < end { let v = Double(pcm[i]); acc += v * v; i += 1 }
            energy[k] = log(1e-8 + acc / Double(win))
        }

        // flujo positivo: solo nos interesan las SUBIDAS de energía (ataques).
        var flux = [Double](repeating: 0, count: frames)
        for k in 1..<frames { flux[k] = max(0, energy[k] - energy[k - 1]) }

        // umbral adaptativo: media local del flujo · factor + un piso pequeño.
        // Con `sensitivity` alto el factor baja y salen más onsets.
        let half = max(3, Int(0.12 * sr / Double(hop)))            // ventana ~±120 ms
        let factor = 1.6 / max(0.3, min(3.0, sensitivity))
        let minGap = max(1, Int(0.04 * sr / Double(hop)))          // 40 ms entre onsets

        var out: [Double] = []
        var lastPick = -minGap - 1
        for k in 1..<frames {
            let lo = max(0, k - half), hi = min(frames - 1, k + half)
            var mean = 0.0
            for j in lo...hi { mean += flux[j] }
            mean /= Double(hi - lo + 1)
            let thr = mean * factor + 1e-4

            let isPeak = flux[k] >= flux[k - 1] && (k + 1 >= frames || flux[k] >= flux[k + 1])
            if flux[k] > thr, isPeak, k - lastPick >= minGap {
                out.append(Double(k * hop) / sr)
                lastPick = k
            }
        }
        return out
    }
}
