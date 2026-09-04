// SPDX-License-Identifier: GPL-3.0-only

import Foundation

/// Aritmética **pura** de la navegación por cues y regiones de loop de la
/// instrumental (F.22). Vive fuera de la vista para poder probar los casos de
/// borde (dar la vuelta, sin activa, un solo elemento) sin montar SwiftUI.
enum InstrumentalNav {

    /// Segundo del cue al que saltar desde `hereSeconds` en la dirección `dir`
    /// (`>= 0` = siguiente, `< 0` = anterior), dando la vuelta al llegar al
    /// extremo. `cues` no tiene por qué venir ordenado. `epsilon` evita
    /// re-disparar el cue en el que ya estás. `nil` si no hay cues.
    static func relativeCue(cues: [Double], hereSeconds here: Double,
                            dir: Int, epsilon: Double = 0.05) -> Double? {
        let sorted = cues.sorted()
        guard !sorted.isEmpty else { return nil }
        if dir >= 0 {
            return sorted.first { $0 > here + epsilon } ?? sorted[0]
        } else {
            return sorted.last { $0 < here - epsilon } ?? sorted[sorted.count - 1]
        }
    }

    /// Índice de región de loop tras pulsar «anterior/siguiente». Recorre
    /// `0..<count` en círculo. Si no había activa, la primera pulsación deja la
    /// 0 (siguiente) o la última (anterior). `nil` si no hay regiones.
    static func cycledLoopIndex(current: Int?, count: Int, dir: Int) -> Int? {
        guard count > 0 else { return nil }
        let cur = current ?? (dir >= 0 ? -1 : 0)
        return ((cur + dir) % count + count) % count
    }
}
