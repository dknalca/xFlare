// SPDX-License-Identifier: GPL-3.0-only

/// Una muestra del estado del crossfader en un instante. La produce cualquier
/// `FaderSource` (MIDI, retorno de audio con tono piloto, teclado, replay).
///
/// Campos segun `docs/ARCHITECTURE.md` §3.
public struct FaderSample: Equatable, Sendable {

    /// Instante de la muestra en el reloj del sistema (`mach_absolute_time`).
    public let hostTime: UInt64

    /// Posicion continua cruda del fader, `0..1`. Se guarda para analisis
    /// posterior aunque el scoring de clicks use `isOpen`.
    public let value: Float

    /// Estado binario ya resuelto con el *cut-in* calibrado e histeresis
    /// (ADR-017). `true` = suena, `false` = cortado.
    public let isOpen: Bool

    public init(hostTime: UInt64, value: Float, isOpen: Bool) {
        self.hostTime = hostTime
        self.value = value
        self.isOpen = isOpen
    }
}
