// SPDX-License-Identifier: GPL-3.0-only

/// Perfil de velocidad dentro de una fase de movimiento del disco. La pendiente
/// de la curva ES el tono que se oye (docs/NOTATION.md §2.2).
///
/// `u` entra normalizado 0..1 (el avance dentro de la fase) y sale la fraccion
/// de recorrido cubierta, tambien 0..1. Portado literal de `CURVES` en
/// `tools/xfn_core.py`.
public enum Curve: String, Codable, Sendable, CaseIterable {
    /// Velocidad constante -> tono plano.
    case lin
    /// Lento-rapido-lento (`3u²-2u³`), el gesto natural de muneca.
    case bell
    /// Acelera (`u²`) -> el tono sube.
    case acc
    /// Frena (`1-(1-u)²`) -> el tono baja.
    case dec
    /// Sin movimiento -> silencio / parada del tear.
    case hold

    /// Evalua la curva en `u` (se asume 0..1; no se recorta a proposito, igual
    /// que la referencia Python).
    public func value(_ u: Double) -> Double {
        switch self {
        case .lin:  return u
        case .bell: return u * u * (3.0 - 2.0 * u)
        case .acc:  return u * u
        case .dec:  return 1.0 - (1.0 - u) * (1.0 - u)
        case .hold: return 0.0
        }
    }
}

/// Sentido de una fase de movimiento del disco.
public enum Direction: String, Codable, Sendable {
    case fwd   // adelante
    case rev   // atras
    case hold  // disco parado
}

/// Estado del crossfader como evento discreto (docs/NOTATION.md §2.3).
public enum FaderState: String, Codable, Sendable {
    case open
    case closed
}
