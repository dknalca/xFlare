// SPDX-License-Identifier: GPL-3.0-only

import XFDesign

/// Un punto de la traza del usuario: dónde estaba el disco (`position`, en las
/// mismas unidades que el patrón) en un tick **absoluto de sesión** (no
/// envuelto: es una grabación en tiempo real).
///
/// `level` lo rellena `XFAnalysis` con el nivel de acierto en ese tramo. `nil`
/// = dentro de tolerancia (se dibuja en el color de acento). `XFRender` no
/// juzga: solo pinta lo que le dan.
public struct TracePoint: Equatable, Sendable {
    public var tick: Double
    public var position: Double
    public var level: HitLevel?

    public init(tick: Double, position: Double, level: HitLevel? = nil) {
        self.tick = tick
        self.position = position
        self.level = level
    }
}
