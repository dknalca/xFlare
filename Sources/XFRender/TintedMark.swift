// SPDX-License-Identifier: GPL-3.0-only

import CoreGraphics
import XFDesign

/// Una marca de click con el resultado del usuario: en `point` (sobre la curva
/// del patrón, donde el corte debía ocurrir), con `level` para el color y la
/// forma (`HitLevel.shape`, legible sin color por daltonismo).
public struct TintedMark: Equatable, Sendable {
    public var point: CGPoint
    public var level: HitLevel
    /// `true` si el evento del patrón es un cierre (●), `false` si es apertura (○).
    public var closes: Bool

    public init(point: CGPoint, level: HitLevel, closes: Bool) {
        self.point = point
        self.level = level
        self.closes = closes
    }
}
