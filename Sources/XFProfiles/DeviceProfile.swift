// SPDX-License-Identifier: GPL-3.0-only

import Foundation

/// Un perfil de mesa ya resuelto (con `extends` aplicado) y tipado.
///
/// Describe **el modelo de mesa** (canales, metodo de captura, CC), nunca la
/// calibracion personal del usuario — eso vive en `XFPersistence`
/// (docs/DEVICE_PROFILES.md §6).
public struct DeviceProfile: Equatable, Sendable {

    // [profile]
    public let id: String
    public let name: String
    public let vendor: String
    public let schema: Int
    public let revision: Int
    public let author: String?
    public let verified: Bool
    public let notes: String?
    /// Id del perfil padre, si el `.conf` declaraba `extends` (se conserva tras
    /// resolver, como en `tools/xf_profile.py`).
    public let ancestorID: String?

    public let match: Match
    public let audio: Audio
    public let crossfader: Crossfader
    public let keyboard: Keyboard?

    /// El INI resuelto entero, por si algo (p. ej. `[quirks]`, `[linefader.*]`)
    /// no esta modelado explicitamente.
    public let raw: INIDocument

    /// `[match]` — como reconocer la mesa por el nombre de sus puertos.
    public struct Match: Equatable, Sendable {
        public let midiPort: String?      // glob, p. ej. "*Seventy-Two*"
        public let audioDevice: String?   // glob
        public var isEmpty: Bool { midiPort == nil && audioDevice == nil }
    }

    /// `[audio]`.
    public struct Audio: Equatable, Sendable {
        public let samplerate: Int
        public let bufferFrames: Int?
        public let outputMainCh: [Int]?
        public let returnCh: [Int]?
        public let timecodeDeck1Ch: [Int]?
        public let timecodeDeck2Ch: [Int]?
    }

    /// `[crossfader]`.
    public struct Crossfader: Equatable, Sendable {
        public let method: CrossfaderMethod
        // method = midi
        public let midiChannel: Int?
        public let midiCC: Int?
        public let midiMin: Int?
        public let midiMax: Int?
        public let midiInvert: Bool?
        // method = audio_return
        public let pilotFrequency: Double?
        public let pilotLevelDb: Double?
        // comunes
        public let cutInLeft: Double?
        public let cutInRight: Double?
        public let hysteresis: Double?
        public let reverseDefault: Bool?
    }

    /// `[keyboard]` — solo en el perfil de modo sin mesa.
    public struct Keyboard: Equatable, Sendable {
        public let motionForward: String
        public let motionBack: String
        public let faderToggle: String
    }

    public enum ParseError: Error, Equatable, CustomStringConvertible {
        case missing(String)
        case notAnInteger(String)
        case notANumber(String)

        public var description: String {
            switch self {
            case .missing(let k):      return "falta \(k)"
            case .notAnInteger(let k): return "\(k) no es un entero"
            case .notANumber(let k):   return "\(k) no es un numero"
            }
        }
    }

    /// Construye un `DeviceProfile` a partir de un INI **ya resuelto**. Es
    /// tolerante: solo `profile.id` y `profile.name` son obligatorios aqui; el
    /// resto de comprobaciones (metodo valido, cut-in en rango, etc.) las hace
    /// `ProfileValidator`.
    public static func parse(resolved ini: INIDocument) throws -> DeviceProfile {

        func str(_ s: String, _ k: String) -> String? { ini.get(s, k) }
        func int(_ s: String, _ k: String) throws -> Int? {
            guard let v = ini.get(s, k) else { return nil }
            guard let n = Int(v) else { throw ParseError.notAnInteger("\(s).\(k)") }
            return n
        }
        func dbl(_ s: String, _ k: String) throws -> Double? {
            guard let v = ini.get(s, k) else { return nil }
            guard let n = Double(v) else { throw ParseError.notANumber("\(s).\(k)") }
            return n
        }
        func bool(_ s: String, _ k: String) -> Bool? {
            guard let v = ini.get(s, k) else { return nil }
            return v == "true" ? true : (v == "false" ? false : nil)
        }
        func channels(_ s: String, _ k: String) -> [Int]? {
            guard let v = ini.get(s, k) else { return nil }
            let parts = v.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
            let nums = parts.compactMap { Int($0) }
            return nums.count == parts.count ? nums : nil
        }

        guard let id = str("profile", "id") else { throw ParseError.missing("profile.id") }
        guard let name = str("profile", "name") else { throw ParseError.missing("profile.name") }

        let match = Match(midiPort: str("match", "midi.port"),
                          audioDevice: str("match", "audio.device"))

        let audio = Audio(
            samplerate: (try int("audio", "samplerate")) ?? 48_000,
            bufferFrames: try int("audio", "buffer.frames"),
            outputMainCh: channels("audio", "output.main.ch"),
            returnCh: channels("audio", "return.ch"),
            timecodeDeck1Ch: channels("audio", "timecode.deck1.ch"),
            timecodeDeck2Ch: channels("audio", "timecode.deck2.ch")
        )

        let methodRaw = str("crossfader", "method") ?? "none"
        let method = CrossfaderMethod(rawValue: methodRaw) ?? .none
        let cf = Crossfader(
            method: method,
            midiChannel: try int("crossfader", "midi.channel"),
            midiCC: try int("crossfader", "midi.cc"),
            midiMin: try int("crossfader", "midi.min"),
            midiMax: try int("crossfader", "midi.max"),
            midiInvert: bool("crossfader", "midi.invert"),
            pilotFrequency: try dbl("crossfader", "pilot.frequency"),
            pilotLevelDb: try dbl("crossfader", "pilot.level_db"),
            cutInLeft: try dbl("crossfader", "cut_in.left"),
            cutInRight: try dbl("crossfader", "cut_in.right"),
            hysteresis: try dbl("crossfader", "hysteresis"),
            reverseDefault: bool("crossfader", "reverse_default")
        )

        var keyboard: Keyboard? = nil
        if ini.hasSection("keyboard"),
           let f = str("keyboard", "motion.forward"),
           let b = str("keyboard", "motion.back"),
           let t = str("keyboard", "fader.toggle") {
            keyboard = Keyboard(motionForward: f, motionBack: b, faderToggle: t)
        }

        return DeviceProfile(
            id: id, name: name,
            vendor: str("profile", "vendor") ?? "-",
            schema: (try int("profile", "schema")) ?? 1,
            revision: (try int("profile", "revision")) ?? 1,
            author: str("profile", "author"),
            verified: bool("profile", "verified") ?? false,
            notes: str("profile", "notes"),
            ancestorID: str("profile", "extends"),
            match: match, audio: audio, crossfader: cf, keyboard: keyboard,
            raw: ini
        )
    }
}
