// SPDX-License-Identifier: GPL-3.0-only

import Foundation

/// Recorte que el usuario ha hecho sobre un sample de scratch en el **editor**
/// (`SampleEditorView`): dónde empieza la parte útil y cuánto dura. Se guarda por
/// ruta de fichero (`SampleEditStore`).
///
/// Para que el scratch responda bien, el sample tiene que ser **corto** (el
/// movimiento del plato mapea a una fracción del sample entero). `length` se
/// acota siempre a `AudioAsset.scratchMaxSeconds`.
public struct SampleEdit: Codable, Equatable {

    /// Segundo del fichero donde empieza la parte que se usa.
    public var startSeconds: Double
    /// Duración de la parte que se usa, en segundos (desde `startSeconds`).
    public var lengthSeconds: Double

    public init(startSeconds: Double = 0,
                lengthSeconds: Double = AudioAsset.scratchMaxSeconds) {
        self.startSeconds = max(0, startSeconds)
        // mínimo 50 ms, máximo la ventana de scratch.
        self.lengthSeconds = min(AudioAsset.scratchMaxSeconds, max(0.05, lengthSeconds))
    }

    public var endSeconds: Double { startSeconds + lengthSeconds }

    /// `true` si es el recorte por defecto (empieza en 0 y dura el máximo) — no
    /// aporta nada sobre la detección automática, así que no se guarda.
    public var isDefault: Bool {
        startSeconds < 1e-6 && abs(lengthSeconds - AudioAsset.scratchMaxSeconds) < 1e-6
    }

    /// El rango en **frames** para un PCM de `frameCount` a `sampleRate`, ya
    /// acotado al fichero. `nil` si no hay solape útil.
    public func frameRange(frameCount n: Int, sampleRate sr: Double) -> Range<Int>? {
        guard n > 1, sr > 0 else { return nil }
        let a = min(n - 1, max(0, Int(startSeconds * sr)))
        let b = min(n, max(a + 1, Int(endSeconds * sr)))
        return b - a >= 2 ? a..<b : nil
    }
}
