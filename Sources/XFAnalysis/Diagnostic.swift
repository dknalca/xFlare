// SPDX-License-Identifier: GPL-3.0-only

/// Una frase de diagnostico accionable. El resultado principal del gym es esto,
/// no un porcentaje (ADR-018). Distingue **sesgo** (sistematico, se corrige
/// moviendo el gesto) de **dispersion** (irregular, se corrige practicando).
public struct Diagnostic: Equatable, Sendable {

    public enum Kind: String, Sendable {
        case timingBias        // llegas tarde/pronto de forma sistematica
        case timingSpread      // tu timing es irregular
        case missedClicks      // se te han caido clicks
        case amplitude         // recorrido corto o largo
        case pitchContour      // el contorno de tono no sigue el patron
        case good              // algo que esta bien, para reforzar
    }

    public let kind: Kind
    /// Texto ya listo para mostrar al usuario, en espanol, concreto y con numeros.
    public let text: String

    public init(_ kind: Kind, _ text: String) {
        self.kind = kind
        self.text = text
    }
}
