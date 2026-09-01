// SPDX-License-Identifier: GPL-3.0-only

/// Compas: cuantas pulsaciones tiene y de que figura es cada una.
///
/// Para practicar scratch es casi siempre 4/4, pero el transporte necesita el
/// concepto de "compas" para la cuenta atras de N compases (B2.2), asi que se
/// modela explicito en vez de asumir 4/4 por todas partes.
public struct TimeSignature: Equatable, Sendable {

    /// Pulsaciones por compas (el numerador: el "4" de 4/4).
    public let beatsPerBar: Int

    /// Figura de cada pulsacion (el denominador: el "4" = negra, "8" = corchea).
    public let beatUnit: Int

    public init(beatsPerBar: Int, beatUnit: Int) {
        precondition(beatsPerBar > 0, "beatsPerBar debe ser > 0")
        precondition(beatUnit > 0 && (beatUnit & (beatUnit - 1)) == 0,
                     "beatUnit debe ser potencia de 2 (1, 2, 4, 8, 16...)")
        self.beatsPerBar = beatsPerBar
        self.beatUnit = beatUnit
    }

    /// 4/4, el valor por defecto para todo el gimnasio.
    public static let fourFour = TimeSignature(beatsPerBar: 4, beatUnit: 4)

    /// Ticks que dura una pulsacion. Una negra son PPQ ticks; una corchea, la
    /// mitad; una blanca, el doble. De ahi `ppq * 4 / beatUnit`.
    public var ticksPerBeat: Tick {
        XFClock.ppq * 4 / beatUnit
    }

    /// Ticks que dura un compas completo.
    public var ticksPerBar: Tick {
        beatsPerBar * ticksPerBeat
    }
}
