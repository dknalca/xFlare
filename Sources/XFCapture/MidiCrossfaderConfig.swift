// SPDX-License-Identifier: GPL-3.0-only

import XFProfiles

/// Configuración para leer el crossfader por **MIDI CC** (`method = midi` en el
/// perfil). En mesas de batalla es raro (ADR-021: el crossfader suele no mandar
/// MIDI), pero algunas mesas y muchos controladores sí lo hacen.
///
/// Los campos ya están modelados en `DeviceProfile.Crossfader`; esto los
/// desacopla de `XFProfiles` para la fuente.
public struct MidiCrossfaderConfig: Equatable, Sendable {

    /// Canal MIDI 1–16, o `nil` para aceptar cualquiera ("omni").
    public let channel: Int?
    /// Número de Control Change del crossfader (0–127).
    public let cc: Int
    /// Rango del valor crudo (normalmente 0–127), se normaliza a `0..1`.
    public let rawMin: Int
    public let rawMax: Int
    /// Invierte la posición (hamster / cableado al revés).
    public let invert: Bool

    public enum ConfigError: Error, Equatable, CustomStringConvertible {
        case notMIDIMethod
        case missing(String)

        public var description: String {
            switch self {
            case .notMIDIMethod:   return "el perfil no tiene crossfader.method = midi"
            case .missing(let k):  return "falta crossfader.\(k)"
            }
        }
    }

    public init(channel: Int? = nil, cc: Int, rawMin: Int = 0, rawMax: Int = 127,
                invert: Bool = false) {
        self.channel = channel
        self.cc = cc
        self.rawMin = rawMin
        self.rawMax = rawMax
        self.invert = invert
    }

    /// Construye a partir de un perfil ya resuelto. Lanza si `method` no es
    /// `midi` o falta `midi.cc`.
    public init(from profile: DeviceProfile) throws {
        guard profile.crossfader.method == .midi else { throw ConfigError.notMIDIMethod }
        let cf = profile.crossfader
        guard let cc = cf.midiCC else { throw ConfigError.missing("midi.cc") }
        self.channel = cf.midiChannel
        self.cc = cc
        self.rawMin = cf.midiMin ?? 0
        self.rawMax = cf.midiMax ?? 127
        self.invert = cf.midiInvert ?? false
    }

    /// Posición normalizada `0..1` a partir de un valor CC crudo, o `nil` si el
    /// rango es degenerado.
    public func value(fromCC raw: Int) -> Float? {
        let span = rawMax - rawMin
        guard span != 0 else { return nil }
        var v = Float(raw - rawMin) / Float(span)
        v = min(1, max(0, v))
        return invert ? 1 - v : v
    }

    /// `true` si un mensaje en `channel` (1–16) es para esta config.
    public func accepts(channel messageChannel: Int) -> Bool {
        channel == nil || channel == messageChannel
    }
}
