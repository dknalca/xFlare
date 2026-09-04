// SPDX-License-Identifier: GPL-3.0-only

/// Los cuatro pasos del asistente de calibración (`docs/UI_DESIGN.md` §3.1). El
/// orden importa: cada paso se apoya en el anterior.
public enum CalibrationStep: Int, CaseIterable, Sendable {
    case audio      // interfaz y salida, buffer
    case latency    // declarada por el driver (F.48/F.63), sin loopback
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
        case .latency:  return "Esto es lo que el dispositivo declara que tarda."
        case .timecode: return "Gira el plato despacio hacia delante."
        case .fader:    return "Haz diez cortes limpios con el crossfader."
        }
    }

    /// Aviso corto si el paso todavía no está conectado al motor de audio
    /// real (B4.2 — captura de entrada + timecode + detección de cortes,
    /// hardware en marcha ahora mismo): mientras tanto, la medida de verdad
    /// se hace con las herramientas de `docs/HW_BRINGUP.md`, no aquí. `nil` =
    /// el paso ya lee datos reales (audio con `AudioDeviceList`; latencia
    /// declarada con `AudioDeviceLatency`, F.63; timecode con
    /// `TimecodeMotionSource` de verdad, F.62).
    public var pendingNote: String? {
        switch self {
        case .audio:
            return nil
        case .latency:
            return nil
        case .timecode:
            return nil
        case .fader:
            return "Todavía no detecta los cortes sola. El crossfader de la Rane 72 se lee "
                 + "por MIDI (CC8/canal16, ADR-021 corregida 2026-09-03), no por tono piloto: "
                 + "usa el monitor MIDI de docs/HW_BRINGUP.md, paso 4."
        }
    }
}
