// SPDX-License-Identifier: GPL-3.0-only

import CoreGraphics
import XFDesign

/// Un tramo de la curva del usuario ya en coordenadas de vista, con el nivel de
/// acierto que lo tiñe. `level == nil` → dentro de tolerancia, se pinta en el
/// color de acento ("tú"). `level != nil` → fuera de tolerancia, se pinta con
/// `level.color` (`docs/UI_DESIGN.md` §3.3).
public struct TintedPolyline: Equatable, Sendable {
    public var points: [CGPoint]
    public var level: HitLevel?

    public init(points: [CGPoint], level: HitLevel?) {
        self.points = points
        self.level = level
    }
}
