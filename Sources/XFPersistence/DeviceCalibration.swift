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
    public var updatedAt: Date

    public static let databaseTableName = "deviceCalibration"

    public init(deviceKey: String, profileId: String, faderCutIn: Double,
                faderHysteresis: Double, hamster: Bool = false,
                latencyMs: Double? = nil, updatedAt: Date) {
        self.deviceKey = deviceKey
        self.profileId = profileId
        self.faderCutIn = faderCutIn
        self.faderHysteresis = faderHysteresis
        self.hamster = hamster
        self.latencyMs = latencyMs
        self.updatedAt = updatedAt
    }
}
