// SPDX-License-Identifier: GPL-3.0-only

/// El resultado del usuario en un click del patrón: el desfase con signo, en ms,
/// respecto al tick donde el patrón pide el corte. Lo produce `XFAnalysis`;
/// `XFRender` lo coloca sobre la curva teñido por `HitLevel(absOffsetMs:)`.
public struct ClickHit: Equatable, Sendable {
    /// Tick del patrón (sin envolver) donde ocurre el click objetivo.
    public var patternTick: Int
    /// Desfase del usuario en ms. `+` = tarde.
    public var offsetMs: Double

    public init(patternTick: Int, offsetMs: Double) {
        self.patternTick = patternTick
        self.offsetMs = offsetMs
    }
}
