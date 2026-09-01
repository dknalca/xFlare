// SPDX-License-Identifier: GPL-3.0-only

import CoreGraphics

/// Los parámetros de encuadre de la autopista: tamaño del lienzo, dónde va la
/// cabeza de lectura y a qué escala se dibuja el tiempo. Es la parte que decide
/// `XFApp` según el tamaño de la ventana; `HighwayLayout` la traduce a geometría.
///
/// Convención de ejes: coordenadas de vista con **origen abajo-izquierda** (como
/// SpriteKit). La X crece hacia la derecha; lo que **viene** está a la derecha de
/// la cabeza de lectura y se desplaza hacia ella (`docs/UI_DESIGN.md` §3.3).
public struct HighwayGeometry: Equatable, Sendable {

    /// Tamaño del lienzo en puntos.
    public var size: CGSize

    /// Posición de la cabeza de lectura, como fracción del ancho (`0...1`).
    /// `docs/UI_DESIGN.md` §3.3: fija al 30 %.
    public var playheadFraction: CGFloat

    /// Ancho en puntos que ocupa una negra. Fija la velocidad de scroll.
    public var pixelsPerBeat: CGFloat

    /// Alto en puntos del carril de fader, pegado al borde inferior.
    public var laneHeight: CGFloat

    /// Margen vertical (arriba y sobre el carril) para que la curva no toque los
    /// bordes.
    public var curveInset: CGFloat

    /// Negras por compás para la rejilla (ADR-038). El modelo XFN no lleva
    /// compás de tiempo; la práctica de scratch es 4/4 salvo que se diga otra cosa.
    public var beatsPerBar: Int

    public init(size: CGSize,
                playheadFraction: CGFloat = 0.30,
                pixelsPerBeat: CGFloat = 120,
                laneHeight: CGFloat = 40,
                curveInset: CGFloat = 16,
                beatsPerBar: Int = 4) {
        self.size = size
        self.playheadFraction = playheadFraction
        self.pixelsPerBeat = pixelsPerBeat
        self.laneHeight = laneHeight
        self.curveInset = curveInset
        self.beatsPerBar = max(1, beatsPerBar)
    }

    /// X de la cabeza de lectura, en puntos.
    public var playheadX: CGFloat { size.width * playheadFraction }

    /// Puntos por tick, dado el PPQ del patrón.
    public func pixelsPerTick(ppq: Int) -> CGFloat {
        pixelsPerBeat / CGFloat(ppq)
    }

    /// Banda vertical [y inferior, y superior] donde vive la curva del disco.
    public var curveBand: (bottom: CGFloat, top: CGFloat) {
        (laneHeight + curveInset, max(laneHeight + curveInset, size.height - curveInset))
    }
}
