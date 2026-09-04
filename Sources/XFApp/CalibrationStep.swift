// SPDX-License-Identifier: GPL-3.0-only

/// Los tres pasos del asistente de calibración (`docs/UI_DESIGN.md` §3.1). El
/// orden importa: cada paso se apoya en el anterior.
///
/// **Sin paso de latencia (2026-09-05, F.66):** hubo uno ("Prueba de
/// latencia", F.63) que mostraba la latencia DECLARADA por el driver — el
/// autor pidió quitarlo directamente, sin sustituto: no aportaba una acción
/// que tomar dentro del asistente. `AudioDeviceLatency` (F.48) sigue viva
/// para otros usos (compensar al puntuar, F.50); lo que desaparece es el
/// paso que solo mostraba el número.
public enum CalibrationStep: Int, CaseIterable, Sendable {
    case audio      // interfaz y salida, buffer
    case timecode   // "gira el plato despacio": señal, dirección, hamster
    case fader      // "haz diez cortes": cut-in y curva

    /// 1…3, para el indicador de progreso.
    public var number: Int { rawValue + 1 }

    public var title: String {
        switch self {
        case .audio:    return "Audio"
        case .timecode: return "Timecode"
        case .fader:    return "Fader"
        }
    }

    /// La instrucción de una línea que ve el usuario.
    public var instruction: String {
        switch self {
        case .audio:    return "Elige la interfaz de entrada y la salida."
        case .timecode: return "Gira el plato despacio hacia delante."
        case .fader:    return "Haz diez cortes limpios con el crossfader."
        }
    }

    /// Aviso corto si el paso todavía no está conectado al motor real. `nil`
    /// = el paso ya lee datos reales (audio con `AudioDeviceList`; timecode
    /// con `TimecodeMotionSource`, F.62; fader por MIDI real, con o sin
    /// aprender el CC, F.67). Ninguno lo necesita hoy — se deja el mecanismo
    /// por si un paso futuro vuelve a depender de algo que falte.
    public var pendingNote: String? {
        switch self {
        case .audio, .timecode, .fader:
            return nil
        }
    }
}
