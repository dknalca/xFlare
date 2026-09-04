// SPDX-License-Identifier: GPL-3.0-only

/// Los cuatro pasos del asistente de calibración (`docs/UI_DESIGN.md` §3.1). El
/// orden importa: cada paso se apoya en el anterior.
public enum CalibrationStep: Int, CaseIterable, Sendable {
    case audio      // interfaz y salida, buffer
    case latency    // round-trip real por loopback
    case timecode   // "gira el plato despacio": señal, dirección, hamster
    case fader      // "haz diez cortes": cut-in y curva

    /// 1…4, para el indicador de progreso.
    public var number: Int { rawValue + 1 }

    public var title: String {
        switch self {
        case .audio:    return "Audio"
        case .latency:  return "Prueba de latencia"
        case .timecode: return "Timecode"
        case .fader:    return "Fader"
        }
    }

    /// La instrucción de una línea que ve el usuario.
    public var instruction: String {
        switch self {
        case .audio:    return "Elige la interfaz de entrada y la salida."
        case .latency:  return "Mide la latencia real de ida y vuelta por loopback."
        case .timecode: return "Gira el plato despacio hacia delante."
        case .fader:    return "Haz diez cortes limpios con el crossfader."
        }
    }

    /// Aviso corto si el paso todavía no está conectado al motor de audio
    /// real (B4.2 — captura de entrada + timecode + detección de cortes,
    /// hardware en marcha ahora mismo): mientras tanto, la medida de verdad
    /// se hace con las herramientas de `docs/HW_BRINGUP.md`, no aquí. `nil` =
    /// el paso ya lee datos reales (hoy solo el de audio, con
    /// `AudioDeviceList`).
    public var pendingNote: String? {
        switch self {
        case .audio:
            return nil
        case .latency:
            return "Todavía no mide sola: hace falta el motor con captura de entrada (B4.2), en marcha. "
                 + "Mientras tanto, mide con tools/measure_latency.py (docs/HW_BRINGUP.md, paso 3)."
        case .timecode:
            return "Todavía no lee el vinilo aquí dentro. Mientras tanto, usa "
                 + "spike/b5-timecode/tcprobe (docs/HW_BRINGUP.md, paso 6)."
        case .fader:
            return "Todavía no detecta los cortes sola. Mientras tanto, usa "
                 + "spike/b1-pilot-fader/pilot_fader (docs/HW_BRINGUP.md, paso 4)."
        }
    }
}
