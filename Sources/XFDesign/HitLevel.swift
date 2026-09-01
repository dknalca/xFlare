// SPDX-License-Identifier: GPL-3.0-only

import SwiftUI

/// Escala de acierto de un click (docs/UI_DESIGN.md §2). **Nunca solo color**:
/// cada nivel lleva forma e icono distintos, por daltonismo. Las ventanas en ms
/// coinciden con `docs/SCORING.md` (aquí son de presentación; XFAnalysis puntúa).
public enum HitLevel: CaseIterable, Sendable {
    case perfect     // ±20 ms
    case great       // ±40 ms
    case good        // ±70 ms
    case offbeat     // ±110 ms
    case miss        // fuera

    /// Clasifica un desfase absoluto (ms) en un nivel.
    public init(absOffsetMs: Double) {
        switch absOffsetMs {
        case ..<20:  self = .perfect
        case ..<40:  self = .great
        case ..<70:  self = .good
        case ..<110: self = .offbeat
        default:     self = .miss
        }
    }

    public var color: Color {
        switch self {
        case .perfect: return Color(hex: 0x34E1C4)
        case .great:   return Color(hex: 0x8ED44A)
        case .good:    return Color(hex: 0xF5C542)
        case .offbeat: return Color(hex: 0xFF7A45)
        case .miss:    return Color(hex: 0xFF4D5E)
        }
    }

    /// Forma distintiva (para leerlo sin depender del color).
    public enum Shape: Sendable { case filledCircle, circle, diamond, triangle, cross }
    public var shape: Shape {
        switch self {
        case .perfect: return .filledCircle
        case .great:   return .circle
        case .good:    return .diamond
        case .offbeat: return .triangle
        case .miss:    return .cross
        }
    }

    /// Nombre corto para VoiceOver y etiquetas.
    public var label: String {
        switch self {
        case .perfect: return "Perfecto"
        case .great:   return "Muy bien"
        case .good:    return "Bien"
        case .offbeat: return "Tarde o pronto"
        case .miss:    return "Fallo"
        }
    }
}
