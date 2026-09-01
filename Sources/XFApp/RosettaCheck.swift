// SPDX-License-Identifier: GPL-3.0-only

import Foundation

/// Detecta si el proceso corre traducido por Rosetta (`sysctl.proc_translated`).
/// El aviso va en la calibración (`docs/UI_DESIGN.md`, B11.16): un binario x86_64
/// bajo Rosetta añade latencia y jitter, y hay versión universal nativa.
public enum RosettaCheck {

    /// `true` si este proceso está traducido. En Apple Silicon nativo o en Intel
    /// real devuelve `false`.
    public static var isTranslated: Bool {
        translated(reader: sysctlProcTranslated)
    }

    /// El aviso para la pantalla de calibración, o `nil` si no hay problema.
    public static var calibrationWarning: String? {
        isTranslated
            ? "xFlare está corriendo bajo Rosetta (traducido de Intel). Eso suma "
              + "latencia. Descarga la versión universal para tu Mac."
            : nil
    }

    // MARK: - testeable

    /// `-1` no disponible · `0` nativo · `1` traducido.
    static func translated(reader: () -> Int32) -> Bool {
        reader() == 1
    }

    private static func sysctlProcTranslated() -> Int32 {
        var value: Int32 = 0
        var size = MemoryLayout<Int32>.size
        let rc = sysctlbyname("sysctl.proc_translated", &value, &size, nil, 0)
        return rc == 0 ? value : -1
    }
}
