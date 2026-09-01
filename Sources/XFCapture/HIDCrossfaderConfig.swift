// SPDX-License-Identifier: GPL-3.0-only

import Foundation
import XFProfiles

/// Configuración para leer la posición del crossfader por **HID** (`method = hid`
/// en el perfil). Muchas mesas de battle (Rane 72, DJM-S11) hablan HID con
/// Serato y **no** exponen el fader por MIDI (ADR-021); esto es la ruta de
/// respaldo.
///
/// Las claves viven en el `[crossfader]` del `.conf`, con prefijo `hid.`. Se leen
/// del `DeviceProfile.raw` (no están modeladas en `XFProfiles`, que está sellado
/// y ya expone `raw` justo para esto). `docs/DEVICE_PROFILES.md` §3 documenta las
/// claves.
public struct HIDCrossfaderConfig: Equatable, Sendable {

    /// Para casar el dispositivo (IOHIDManager). `usagePage`/`usage` opcionales.
    public let vendorID: Int
    public let productID: Int
    public let usagePage: Int?
    public let usage: Int?

    /// `hid.report_id` (0 = el dispositivo no usa report IDs).
    public let reportID: Int
    /// Offset del valor del fader dentro de los **datos** del report (sin contar
    /// el byte de report ID, que IOHID entrega aparte).
    public let byteOffset: Int
    /// 1 (valor de 8 bits) o 2 (16 bits).
    public let byteLength: Int
    /// Para `byteLength == 2`: orden de bytes. HID suele ser little-endian.
    public let bigEndian: Bool
    /// Rango del valor crudo, se normaliza a 0..1.
    public let rawMin: Int
    public let rawMax: Int
    /// Invierte la posición (hamster / cableado al revés).
    public let invert: Bool

    public enum ConfigError: Error, Equatable, CustomStringConvertible {
        case notHIDMethod
        case missing(String)
        case invalid(String)

        public var description: String {
            switch self {
            case .notHIDMethod:      return "el perfil no tiene crossfader.method = hid"
            case .missing(let k):    return "falta crossfader.\(k)"
            case .invalid(let k):    return "crossfader.\(k) no es válido"
            }
        }
    }

    public init(vendorID: Int, productID: Int, usagePage: Int? = nil, usage: Int? = nil,
                reportID: Int = 0, byteOffset: Int, byteLength: Int = 1, bigEndian: Bool = false,
                rawMin: Int = 0, rawMax: Int = 255, invert: Bool = false) {
        self.vendorID = vendorID
        self.productID = productID
        self.usagePage = usagePage
        self.usage = usage
        self.reportID = reportID
        self.byteOffset = byteOffset
        self.byteLength = byteLength
        self.bigEndian = bigEndian
        self.rawMin = rawMin
        self.rawMax = rawMax
        self.invert = invert
    }

    /// Construye a partir de un perfil ya resuelto. Lanza si `method` no es `hid`
    /// o si falta alguna clave obligatoria.
    public init(from profile: DeviceProfile) throws {
        guard profile.crossfader.method == .hid else { throw ConfigError.notHIDMethod }
        let ini = profile.raw

        func intVal(_ key: String) throws -> Int {
            guard let s = ini.get("crossfader", "hid.\(key)") else { throw ConfigError.missing("hid.\(key)") }
            guard let n = HIDCrossfaderConfig.parseInt(s) else { throw ConfigError.invalid("hid.\(key)") }
            return n
        }
        func optInt(_ key: String) -> Int? {
            ini.get("crossfader", "hid.\(key)").flatMap(HIDCrossfaderConfig.parseInt)
        }
        func boolVal(_ key: String, default def: Bool) -> Bool {
            switch ini.get("crossfader", "hid.\(key)") {
            case "true": return true
            case "false": return false
            default: return def
            }
        }

        self.vendorID = try intVal("vendor_id")
        self.productID = try intVal("product_id")
        self.usagePage = optInt("usage_page")
        self.usage = optInt("usage")
        self.reportID = optInt("report_id") ?? 0
        self.byteOffset = try intVal("byte_offset")
        let len = optInt("byte_length") ?? 1
        guard len == 1 || len == 2 else { throw ConfigError.invalid("hid.byte_length") }
        self.byteLength = len
        self.bigEndian = boolVal("big_endian", default: false)
        self.rawMin = optInt("min") ?? 0
        self.rawMax = optInt("max") ?? (len == 2 ? 65535 : 255)
        self.invert = boolVal("invert", default: false)
    }

    /// Extrae la posición normalizada `0..1` de los **datos** de un input report
    /// (sin el byte de report ID). `nil` si el report es más corto de lo esperado.
    public func value(fromReport data: [UInt8]) -> Float? {
        guard byteOffset >= 0, data.count >= byteOffset + byteLength else { return nil }
        let raw: Int
        if byteLength == 1 {
            raw = Int(data[byteOffset])
        } else {
            let hi = Int(data[byteOffset])
            let lo = Int(data[byteOffset + 1])
            raw = bigEndian ? (hi << 8 | lo) : (lo << 8 | hi)
        }
        let span = rawMax - rawMin
        guard span != 0 else { return nil }
        var v = Float(raw - rawMin) / Float(span)
        v = min(1, max(0, v))
        return invert ? 1 - v : v
    }

    /// Acepta decimal (`128`) y hexadecimal (`0x1FB4`).
    static func parseInt(_ s: String) -> Int? {
        let t = s.trimmingCharacters(in: .whitespaces)
        if t.lowercased().hasPrefix("0x") { return Int(t.dropFirst(2), radix: 16) }
        return Int(t)
    }
}
