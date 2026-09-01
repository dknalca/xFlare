// SPDX-License-Identifier: GPL-3.0-only

/// La condición para desbloquear una variante, tal y como está en
/// `data/curriculum/variants.json` (`unlock: { variant, stars }`).
///
/// XFPersistence no lee ese fichero: el llamante (XFEngine / XFApp) construye
/// estas reglas desde el catálogo y se las pasa a
/// `XFDatabase.evaluateUnlocks(exerciseId:rules:at:)`.
public struct VariantUnlockRule: Equatable, Sendable {

    /// La variante que se desbloquea.
    public let variantId: String
    /// La variante cuyas estrellas hay que mirar (a menudo `"base"`).
    public let requiresVariant: String
    /// Estrellas necesarias en `requiresVariant`.
    public let requiresStars: Int

    public init(variantId: String, requiresVariant: String, requiresStars: Int) {
        self.variantId = variantId
        self.requiresVariant = requiresVariant
        self.requiresStars = requiresStars
    }
}
