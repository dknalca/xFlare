// SPDX-License-Identifier: GPL-3.0-only

import XFPrimitives

/// Convierte la posicion continua del crossfader (`0..1`) en el estado binario
/// `isOpen` con el **punto de corte calibrado** y **histeresis** (ADR-017).
///
/// La histeresis es un disparador de Schmitt: para pasar a "abierto" hay que
/// superar `cutIn + banda/2`, y para volver a "cortado" hay que bajar de
/// `cutIn − banda/2`. Entre esos dos valores el estado no cambia — asi un fader
/// quieto con ruido cerca del umbral no genera eventos fantasma.
public struct FaderBinarizer {

    /// Posicion donde el sonido empieza a oirse (del perfil `.conf` o de la
    /// calibracion del usuario).
    public let cutIn: Float
    /// Ancho de la banda muerta alrededor de `cutIn`.
    public let hysteresis: Float
    /// Fader invertido (hamster / reverse): el autor corta en reverse (ADR-008).
    /// Con `true`, "abierto" es la zona por DEBAJO del corte.
    public let hamster: Bool

    private var open: Bool

    public init(cutIn: Float, hysteresis: Float, hamster: Bool = false, initiallyOpen: Bool = false) {
        precondition(cutIn >= 0 && cutIn <= 1, "cutIn debe estar en 0..1")
        precondition(hysteresis >= 0, "la histeresis no puede ser negativa")
        self.cutIn = cutIn
        self.hysteresis = hysteresis
        self.hamster = hamster
        self.open = initiallyOpen
    }

    /// Actualiza con una lectura cruda y devuelve el estado resuelto.
    public mutating func update(rawValue value: Float) -> Bool {
        let half = hysteresis / 2
        // "señal" = cuanto de abierto esta, ya teniendo en cuenta el hamster.
        let signal = hamster ? (1 - value) : value
        if !open, signal > cutIn + half {
            open = true
        } else if open, signal < cutIn - half {
            open = false
        }
        return open
    }

    /// Estado actual sin actualizar.
    public var isOpen: Bool { open }

    /// Binariza un tramo de lecturas crudas `(hostTime, value)` a `FaderSample`s,
    /// una por lectura, con el estado ya resuelto. El binarizador conserva su
    /// estado entre llamadas.
    public mutating func binarize(_ raw: [(hostTime: UInt64, value: Float)]) -> [FaderSample] {
        raw.map { r in
            let o = update(rawValue: r.value)
            return FaderSample(hostTime: r.hostTime, value: r.value, isOpen: o)
        }
    }
}
