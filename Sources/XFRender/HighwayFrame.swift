// SPDX-License-Identifier: GPL-3.0-only

import CoreGraphics

/// Todo lo que hay que pintar en un instante dado de la autopista, ya en
/// coordenadas de vista. Lo produce `HighwayLayout.frame(atTick:geometry:)` y lo
/// consume `HighwayScene` (o unos golden tests SVG en B7.6).
///
/// Es un **valor**: mismo `currentTick` ⇒ mismo `HighwayFrame`. Ahí está la
/// garantía de "sin deriva": el fotograma no depende de cuántas veces se haya
/// dibujado, solo del reloj de AUDIO que se le pasa.
public struct HighwayFrame: Equatable, Sendable {

    /// Polilínea de la curva del disco (posición de la mano), de izquierda a
    /// derecha.
    public var discCurve: [CGPoint]

    /// Puntos sobre la curva donde el fader **abre** (○, entra sonido).
    public var openMarks: [CGPoint]

    /// Puntos sobre la curva donde el fader **cierra** (●, el click / corte).
    public var closeMarks: [CGPoint]

    /// Tramos del carril de fader visibles, de izquierda a derecha.
    public var faderBands: [FaderBand]

    /// La curva del **usuario** (capa de acento), partida en tramos por el nivel
    /// de acierto que la tiñe. Vacía si no se pasó traza (B7.4).
    public var userSegments: [TintedPolyline]

    /// Marcas de los clicks con el resultado del usuario (color + forma). Vacío
    /// si no se pasaron `ClickHit` (B7.4).
    public var hitMarks: [TintedMark]

    /// X de la cabeza de lectura (constante para una geometría dada).
    public var playheadX: CGFloat

    public init(discCurve: [CGPoint], openMarks: [CGPoint], closeMarks: [CGPoint],
                faderBands: [FaderBand], playheadX: CGFloat,
                userSegments: [TintedPolyline] = [], hitMarks: [TintedMark] = []) {
        self.discCurve = discCurve
        self.openMarks = openMarks
        self.closeMarks = closeMarks
        self.faderBands = faderBands
        self.userSegments = userSegments
        self.hitMarks = hitMarks
        self.playheadX = playheadX
    }
}
