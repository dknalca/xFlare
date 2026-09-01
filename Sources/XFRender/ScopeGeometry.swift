// SPDX-License-Identifier: GPL-3.0-only

import CoreGraphics

/// El encuadre del scope circular: un cuadro donde cabe la circunferencia de
/// referencia con un margen.
public struct ScopeGeometry: Equatable, Sendable {

    public var size: CGSize
    /// Margen entre el borde del cuadro y la circunferencia de referencia.
    public var padding: CGFloat

    public init(size: CGSize, padding: CGFloat = 12) {
        self.size = size
        self.padding = padding
    }

    public var center: CGPoint {
        CGPoint(x: size.width / 2, y: size.height / 2)
    }

    /// Radio de la circunferencia de referencia (señal limpia a nivel nominal).
    public var referenceRadius: CGFloat {
        max(0, min(size.width, size.height) / 2 - padding)
    }
}
