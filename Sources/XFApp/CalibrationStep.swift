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
}
