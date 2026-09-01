// SPDX-License-Identifier: GPL-3.0-only

import CoreGraphics

/// La figura del scope ya en coordenadas de vista: la circunferencia de
/// referencia, el punto de la aguja, su rastro reciente y si la señal está
/// degradada. `docs/UI_DESIGN.md` §3.3: "el espejo del plato".
///
/// Con señal limpia el punto va sobre la circunferencia y el rastro dibuja un
/// arco regular; al ensuciar la aguja el punto se hunde hacia el centro y
/// `isDegraded` se pone a `true`.
public struct ScopeFigure: Equatable, Sendable {

    public var center: CGPoint
    /// Radio de la circunferencia de referencia.
    public var referenceRadius: CGFloat

    /// Punto actual de la aguja.
    public var dot: CGPoint
    /// Radio del punto como fracción del de referencia (= confianza recortada).
    /// `1` = señal limpia; `< 1` = hundido hacia el centro.
    public var dotRadiusFraction: CGFloat
    /// Ángulo de la aguja, normalizado a `0..<2π` (para la línea radial).
    public var angleRadians: CGFloat

    /// Rastro de las últimas lecturas, de la más vieja a la más nueva. El último
    /// punto coincide con `dot`.
    public var trail: [CGPoint]

    /// `true` cuando la confianza está por debajo del umbral: aguja levantada o
    /// señal sucia.
    public var isDegraded: Bool

    public init(center: CGPoint, referenceRadius: CGFloat, dot: CGPoint,
                dotRadiusFraction: CGFloat, angleRadians: CGFloat,
                trail: [CGPoint], isDegraded: Bool) {
        self.center = center
        self.referenceRadius = referenceRadius
        self.dot = dot
        self.dotRadiusFraction = dotRadiusFraction
        self.angleRadians = angleRadians
        self.trail = trail
        self.isDegraded = isDegraded
    }
}
