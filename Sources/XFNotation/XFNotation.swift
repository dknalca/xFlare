// SPDX-License-Identifier: GPL-3.0-only
//
// XFNotation — CAPA 1. El modelo XFN (xFlare Notation) en Swift y el compositor
// mano × fader. Puro: sin hardware, sin UI, sin red. Depende solo de XFClock.
//
// La idea (docs/NOTATION.md §3): un scratch NO se guarda dibujado, se COMPONE:
//     scratch = patron_de_mano × patron_de_fader × subdivision × ciclos
// Este modulo porta a Swift la referencia `tools/xfn_core.py` y se valida
// contra ella con un golden (B3.3).

/// Espacio de nombres y version del contrato publico de XFNotation.
public enum XFNotation {
    /// Sube con cualquier cambio incompatible de la API publica (requiere ADR
    /// y re-sellar el modulo).
    public static let apiVersion = 1
}
