// SPDX-License-Identifier: GPL-3.0-only

/// Un perfil de mesa listo para exportar como `.conf` (`docs/DEVICE_PROFILES.md`,
/// validador `tools/xf_profile.py`). Lo arma el asistente a partir de la
/// calibración; `ProfileExporter` lo serializa a INI.
public struct ExportableProfile: Equatable, Sendable {

    public enum Method: String, Sendable, CaseIterable {
        case midi
        case audioReturn = "audio_return"
        case hid
        case none
    }

    public var id: String
    public var name: String
    public var vendor: String
    public var revision: Int
    public var verified: Bool

    public var method: Method
    public var cutInLeft: Double
    public var cutInRight: Double
    public var hysteresis: Double
    public var reverseDefault: Bool

    // method == .midi
    public var midiChannel: Int?
    public var midiCC: Int?
    public var midiMin: Int?
    public var midiMax: Int?

    // method == .audioReturn
    public var pilotFrequency: Int?
    public var pilotLevelDb: Int?

    public init(id: String, name: String, vendor: String, revision: Int = 1,
                verified: Bool = false, method: Method,
                cutInLeft: Double = 0.05, cutInRight: Double = 0.95,
                hysteresis: Double = 0.03, reverseDefault: Bool = false,
                midiChannel: Int? = nil, midiCC: Int? = nil,
                midiMin: Int? = nil, midiMax: Int? = nil,
                pilotFrequency: Int? = nil, pilotLevelDb: Int? = nil) {
        self.id = id
        self.name = name
        self.vendor = vendor
        self.revision = revision
        self.verified = verified
        self.method = method
        self.cutInLeft = cutInLeft
        self.cutInRight = cutInRight
        self.hysteresis = hysteresis
        self.reverseDefault = reverseDefault
        self.midiChannel = midiChannel
        self.midiCC = midiCC
        self.midiMin = midiMin
        self.midiMax = midiMax
        self.pilotFrequency = pilotFrequency
        self.pilotLevelDb = pilotLevelDb
    }

    /// Un `id` que cumple la regla de `xf_profile.py`: minúsculas, sin espacios.
    public var sanitizedId: String {
        String(id.lowercased().map { $0 == " " ? "-" : $0 })
            .filter { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }
    }
}
