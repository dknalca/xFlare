// SPDX-License-Identifier: GPL-3.0-only

/// Valida un perfil `.conf`. Porta `check()` de `tools/xf_profile.py`: los mismos
/// errores y avisos sobre los mismos ficheros (criterio de B5b.3).
public enum ProfileValidator {

    /// Resultado: errores (el perfil no vale) y avisos (vale pero ojo).
    public struct Report: Equatable {
        public var errors: [String]
        public var warnings: [String]
        public var isValid: Bool { errors.isEmpty }
    }

    private static let requiredProfileKeys = ["id", "name", "vendor", "schema", "revision", "verified"]
    private static let boolKeys: [(section: String, key: String)] = [
        ("profile", "verified"),
        ("crossfader", "midi.invert"),
        ("crossfader", "reverse_default"),
    ]
    private static let methods = ["midi", "audio_return", "hid", "none"]
    private static let neededByMethod: [String: [String]] = [
        "midi": ["midi.channel", "midi.cc", "midi.min", "midi.max"],
        "audio_return": ["pilot.frequency", "pilot.level_db"],
        "hid": [], "none": [],
    ]

    /// - Parameters:
    ///   - raw: el INI **sin resolver** (tal cual el fichero).
    ///   - registry: todos los perfiles por id, para comprobar `extends` y resolver.
    ///   - filenameStem: nombre del fichero sin extension (para el aviso de id).
    ///   - isExample: `true` si el fichero es un `.example` (algunas reglas se relajan).
    public static func validate(raw: INIDocument,
                                registry: [String: INIDocument],
                                filenameStem: String,
                                isExample: Bool) -> Report {
        var errors: [String] = []
        var warnings: [String] = []

        // 1) extends: si apunta a algo que no existe, se corta aqui.
        let ext = raw.get("profile", "extends")
        if let ext = ext, registry[ext] == nil {
            return Report(errors: ["extends apunta a un perfil que no existe: \(ext)"], warnings: [])
        }

        // se valida el resultado RESUELTO, no el fichero en crudo.
        let resolved: INIDocument
        if ext != nil {
            guard let selfID = raw.get("profile", "id") else {
                return Report(errors: ["no se puede resolver: falta profile.id"], warnings: [])
            }
            var reg = registry
            reg[selfID] = raw            // el propio fichero, por si el registry trae otra version
            do {
                resolved = try ProfileResolver.resolve(id: selfID, in: reg)
            } catch {
                return Report(errors: ["\(error)"], warnings: [])
            }
        } else {
            resolved = raw
        }

        // 2) secciones y claves obligatorias
        if !resolved.hasSection("profile") {
            errors.append("falta la seccion [profile]")
        } else {
            for k in requiredProfileKeys where !resolved.hasOption("profile", k) {
                errors.append("falta profile.\(k)")
            }
        }

        // 3) el id: minusculas, sin espacios, y aviso si no cuadra con el fichero
        if let pid = resolved.get("profile", "id") {
            if filenameStem != pid && filenameStem != pid + ".conf" && !isExample {
                warnings.append("el id '\(pid)' no coincide con el nombre del fichero '\(filenameStem)'")
            }
            if pid != pid.lowercased() || pid.contains(" ") {
                errors.append("el id debe ir en minusculas y sin espacios")
            }
        }

        // 4) claves booleanas
        for b in boolKeys {
            if let v = resolved.get(b.section, b.key), v != "true", v != "false" {
                errors.append("\(b.section).\(b.key) debe ser true o false")
            }
        }

        // 5) crossfader
        if resolved.hasSection("crossfader") {
            let m = resolved.get("crossfader", "method")
            if let m = m, methods.contains(m) {
                for k in neededByMethod[m, default: []] where !resolved.hasOption("crossfader", k) {
                    errors.append("con method=\(m) hace falta crossfader.\(k)")
                }
            } else {
                errors.append("crossfader.method invalido: \(m.map { "'\($0)'" } ?? "nil") (usa \(methods.joined(separator: "/")))")
            }
            for k in ["cut_in.left", "cut_in.right", "hysteresis"] {
                if let v = resolved.get("crossfader", k) {
                    if let n = Double(v) {
                        if n < 0.0 || n > 1.0 { errors.append("crossfader.\(k) fuera de 0..1") }
                    } else {
                        errors.append("crossfader.\(k) no es numero")
                    }
                }
            }
            if let l = resolved.get("crossfader", "cut_in.left"), !l.isEmpty,
               let r = resolved.get("crossfader", "cut_in.right"), !r.isEmpty,
               let ln = Double(l), let rn = Double(r), ln >= rn {
                errors.append("cut_in.left debe ser menor que cut_in.right")
            }
        } else if !isExample {
            errors.append("falta la seccion [crossfader]")
        }

        // 6) aviso de perfil sin verificar (sobre el fichero en crudo)
        if (raw.get("profile", "verified") ?? "false") == "false" {
            warnings.append("perfil SIN VERIFICAR contra hardware real")
        }

        return Report(errors: errors, warnings: warnings)
    }
}
