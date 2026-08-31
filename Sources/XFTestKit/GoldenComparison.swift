// SPDX-License-Identifier: GPL-3.0-only
//
// Comparacion de goldens tolerante a la arquitectura (ADR-028).
//
// Por que existe (B0.8): un golden numerico comparado byte a byte FALLA entre
// x86_64 y arm64 aunque el codigo sea correcto — el orden de operaciones, la
// contraccion a FMA y el trato de denormales difieren en los ultimos bits.
// Regla del proyecto: los goldens numericos se serializan REDONDEADOS A 4
// DECIMALES y las comparaciones de valores usan TOLERANCIA 1e-9.
//
// Estas funciones se definen ahora, ANTES de escribir el primer golden (B3.3 en
// XFNotation, B7.6 en XFRender), para que todos los golden tests las usen y
// ninguno vuelva a comparar texto crudo. Sus tests viven en el bloque B3.

import Foundation

public enum Golden {

    /// Tolerancia estandar para comparar dos valores de coma flotante entre
    /// arquitecturas. Ver ADR-028 y docs/ARCHITECTURES.md seccion 3.2.
    public static let tolerance: Double = 1e-9

    /// Redondea a 4 decimales, que es la precision a la que se serializa un
    /// golden. Se aplica SIEMPRE antes de escribir un valor de referencia.
    public static func round4(_ x: Double) -> Double {
        // rint sobre x*1e4 evita el sesgo de `rounded(.toNearestOrAwayFromZero)`
        // en los .5 exactos y da el mismo resultado en las dos arquitecturas.
        (x * 10_000).rounded(.toNearestOrEven) / 10_000
    }

    /// true si `a` y `b` estan dentro de `tolerance` (por defecto 1e-9).
    /// NaN nunca es aproximadamente igual a nada, ni a otro NaN.
    public static func approxEqual(_ a: Double, _ b: Double,
                                   tolerance: Double = Golden.tolerance) -> Bool {
        if a.isNaN || b.isNaN { return false }
        if a == b { return true } // cubre +0/-0 e infinitos del mismo signo
        return abs(a - b) <= tolerance
    }

    /// Compara dos secuencias de dobles elemento a elemento con tolerancia.
    /// Devuelve el primer indice que difiere, o nil si son equivalentes.
    public static func firstMismatch(_ lhs: [Double], _ rhs: [Double],
                                     tolerance: Double = Golden.tolerance) -> Int? {
        if lhs.count != rhs.count { return min(lhs.count, rhs.count) }
        for i in lhs.indices where !approxEqual(lhs[i], rhs[i], tolerance: tolerance) {
            return i
        }
        return nil
    }
}
