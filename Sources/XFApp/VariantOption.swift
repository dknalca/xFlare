// SPDX-License-Identifier: GPL-3.0-only

/// Una opción del selector de variantes (`docs/UI_DESIGN.md` §3.15). Muestra la
/// **condición de desbloqueo**, no solo el candado.
public struct VariantOption: Equatable, Sendable, Identifiable {

    public enum Lock: Equatable, Sendable {
        case unlocked
        /// Bloqueada, con la condición escrita ("2★ en base", "3★ en base"…).
        case locked(condition: String)
    }

    public var variantId: String
    public var name: String
    public var difficulty: Double
    public var lock: Lock

    public var id: String { variantId }
    public var isUnlocked: Bool { lock == .unlocked }

    public init(variantId: String, name: String, difficulty: Double, lock: Lock) {
        self.variantId = variantId
        self.name = name
        self.difficulty = difficulty
        self.lock = lock
    }

    /// Construye la opción a partir de la regla de `data/curriculum/variants.json`
    /// y de las estrellas que tiene el usuario en la variante requerida.
    ///
    /// - Parameters:
    ///   - requires: `nil` para la base (siempre desbloqueada), o
    ///     `(variantId, stars)` como en `variants.json`.
    ///   - starsInRequired: estrellas del usuario en `requires.variantId`.
    ///   - requiredVariantName: nombre legible de la variante requerida.
    public static func build(variantId: String, name: String, difficulty: Double,
                             requires: (variantId: String, stars: Int)?,
                             starsInRequired: Int,
                             requiredVariantName: String) -> VariantOption {
        let lock: Lock
        if let req = requires {
            lock = starsInRequired >= req.stars
                ? .unlocked
                : .locked(condition: "\(stars(req.stars)) en \(requiredVariantName)")
        } else {
            lock = .unlocked
        }
        return VariantOption(variantId: variantId, name: name, difficulty: difficulty, lock: lock)
    }

    private static func stars(_ n: Int) -> String { String(repeating: "★", count: max(1, n)) }
}
