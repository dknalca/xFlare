// SPDX-License-Identifier: GPL-3.0-only

import Foundation
import GRDB

/// La calibración guardada de un dispositivo concreto. `docs/DEVICE_PROFILES.md`.
///
/// `deviceKey` es el identificador estable del hardware: el UID del dispositivo
/// de audio o el nombre del puerto MIDI. `profileId` es el perfil de
/// `XFProfiles` que se está usando con él; el resto son los ajustes que el
/// asistente de calibración deja afinados para esta mesa.
public struct DeviceCalibration: Codable, Equatable, Sendable,
                                 FetchableRecord, PersistableRecord {

    public var deviceKey: String
    public var profileId: String
    /// Punto del fader donde empieza a oírse (`0...1`), calibrado a oído.
    public var faderCutIn: Double
    /// Banda de histéresis alrededor del cut-in (ADR-017).
    public var faderHysteresis: Double
    /// Crossfader invertido (ADR-008).
    public var hamster: Bool
    /// Latencia round-trip medida en esta máquina con este dispositivo, ms.
    public var latencyMs: Double?
    /// CC MIDI del crossfader **aprendido** por el asistente (F.67,
    /// `MidiFaderLearner`), no el que declare el perfil `.conf` — que puede no
    /// traerlo, o traer uno equivocado (B5.5). Los cuatro `nil` si no se ha
    /// aprendido nunca para este dispositivo (columnas `v2`, ADR-077).
    public var faderMidiChannel: Int?
    public var faderMidiCC: Int?
    public var faderMidiRawMin: Int?
    public var faderMidiRawMax: Int?
    public var updatedAt: Date

    public static let databaseTableName = "deviceCalibration"

    public init(deviceKey: String, profileId: String, faderCutIn: Double,
                faderHysteresis: Double, hamster: Bool = false,
                latencyMs: Double? = nil,
                faderMidiChannel: Int? = nil, faderMidiCC: Int? = nil,
                faderMidiRawMin: Int? = nil, faderMidiRawMax: Int? = nil,
                updatedAt: Date) {
        self.deviceKey = deviceKey
        self.profileId = profileId
        self.faderCutIn = faderCutIn
        self.faderHysteresis = faderHysteresis
        self.hamster = hamster
        self.latencyMs = latencyMs
        self.faderMidiChannel = faderMidiChannel
        self.faderMidiCC = faderMidiCC
        self.faderMidiRawMin = faderMidiRawMin
        self.faderMidiRawMax = faderMidiRawMax
        self.updatedAt = updatedAt
    }
}
