// SPDX-License-Identifier: GPL-3.0-only

import SwiftUI
import XFDesign

/// El semáforo de la prueba de latencia (`docs/UI_DESIGN.md` §3.1, puertas de
/// ADR-024): verde ≤ 10 ms, ámbar ≤ 15 ms, rojo por encima.
public enum LatencyVerdict: Sendable, Equatable {
    case good        // ≤ 10 ms  — la máquina de referencia
    case acceptable  // ≤ 15 ms  — el MacBook Pro 2015 con buffer de 128
    case tooHigh     // > 15 ms  — hay que documentarlo como limitación

    public init(roundTripMs: Double) {
        if roundTripMs <= 10 { self = .good }
        else if roundTripMs <= 15 { self = .acceptable }
        else { self = .tooHigh }
    }

    /// `true` si el scratch se va a sentir bien (no "gomoso").
    public var passesGate: Bool { self != .tooHigh }

    public var color: Color {
        switch self {
        case .good:       return Color(hex: 0x8ED44A)
        case .acceptable: return Color(hex: 0xF5C542)
        case .tooHigh:    return Color(hex: 0xFF4D5E)
        }
    }

    public var label: String {
        switch self {
        case .good:       return "Dentro de presupuesto"
        case .acceptable: return "Aceptable"
        case .tooHigh:    return "Demasiada latencia"
        }
    }

    /// Qué tocar si no pasa.
    public var advice: String {
        switch self {
        case .good:
            return "El plato responde como un vinilo. Sigue."
        case .acceptable:
            return "Se nota un pelín, pero es jugable. Cierra otras apps de audio si quieres bajar."
        case .tooHigh:
            return "Sube el buffer a 128, usa la interfaz de la mesa en vez de la salida integrada, "
                 + "y cierra todo lo que use audio. Si no baja de 15 ms, la app lo dirá y seguirás igualmente."
        }
    }
}
