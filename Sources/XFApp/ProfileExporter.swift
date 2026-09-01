// SPDX-License-Identifier: GPL-3.0-only

/// Serializa un `ExportableProfile` a `.conf` (INI) y comprueba de antemano las
/// reglas de `tools/xf_profile.py`, para que el asistente de aportación
/// (`docs/UI_DESIGN.md` §3.11) no genere un fichero inválido.
public enum ProfileExporter {

    /// El texto `.conf`.
    public static func iniText(_ p: ExportableProfile) -> String {
        var lines: [String] = [
            "# \(p.name) — generado por xFlare",
            "# Perfil aportado por un usuario. Revisar antes de compartir.",
            "",
            "[profile]",
            "id       = \(p.sanitizedId)",
            "name     = \(p.name)",
            "vendor   = \(p.vendor)",
            "schema   = 1",
            "revision = \(p.revision)",
            "verified = \(p.verified ? "true" : "false")",
            "",
            "[crossfader]",
            "method          = \(p.method.rawValue)",
        ]
        switch p.method {
        case .midi:
            lines += [
                "midi.channel    = \(p.midiChannel ?? 1)",
                "midi.cc         = \(p.midiCC ?? 0)",
                "midi.min        = \(p.midiMin ?? 0)",
                "midi.max        = \(p.midiMax ?? 127)",
            ]
        case .audioReturn:
            lines += [
                "pilot.frequency = \(p.pilotFrequency ?? 19500)",
                "pilot.level_db  = \(p.pilotLevelDb ?? -40)",
            ]
        case .hid, .none:
            break
        }
        lines += [
            String(format: "cut_in.left     = %.2f", p.cutInLeft),
            String(format: "cut_in.right    = %.2f", p.cutInRight),
            String(format: "hysteresis      = %.2f", p.hysteresis),
            "reverse_default = \(p.reverseDefault ? "true" : "false")",
            "",
        ]
        return lines.joined(separator: "\n")
    }

    /// Errores que rechazaría `xf_profile.py`. Vacío = válido.
    public static func validationErrors(_ p: ExportableProfile) -> [String] {
        var errs: [String] = []

        if p.sanitizedId.isEmpty { errs.append("el id queda vacío tras limpiarlo") }
        if p.name.trimmingCharacters(in: .whitespaces).isEmpty { errs.append("falta profile.name") }
        if p.vendor.trimmingCharacters(in: .whitespaces).isEmpty { errs.append("falta profile.vendor") }

        switch p.method {
        case .midi:
            if p.midiChannel == nil { errs.append("con method=midi hace falta crossfader.midi.channel") }
            if p.midiCC == nil { errs.append("con method=midi hace falta crossfader.midi.cc") }
            if p.midiMin == nil { errs.append("con method=midi hace falta crossfader.midi.min") }
            if p.midiMax == nil { errs.append("con method=midi hace falta crossfader.midi.max") }
        case .audioReturn:
            if p.pilotFrequency == nil { errs.append("con method=audio_return hace falta crossfader.pilot.frequency") }
            if p.pilotLevelDb == nil { errs.append("con method=audio_return hace falta crossfader.pilot.level_db") }
        case .hid, .none:
            break
        }

        for (name, v) in [("cut_in.left", p.cutInLeft), ("cut_in.right", p.cutInRight),
                          ("hysteresis", p.hysteresis)] where v < 0 || v > 1 {
            errs.append("crossfader.\(name) fuera de 0..1")
        }
        if p.cutInLeft >= p.cutInRight { errs.append("cut_in.left debe ser menor que cut_in.right") }

        return errs
    }

    public static func isValid(_ p: ExportableProfile) -> Bool {
        validationErrors(p).isEmpty
    }
}
