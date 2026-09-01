// SPDX-License-Identifier: GPL-3.0-only

import CoreGraphics

/// Escala de espaciado y radios (docs/UI_DESIGN.md §2). Escala 4/8/12/16/24/32/48.
public enum XFSpacing {
    public static let xxs: CGFloat = 4
    public static let xs:  CGFloat = 8
    public static let sm:  CGFloat = 12
    public static let md:  CGFloat = 16
    public static let lg:  CGFloat = 24
    public static let xl:  CGFloat = 32
    public static let xxl: CGFloat = 48
}

/// Radios de esquina.
public enum XFRadius {
    /// Controles (botones, steppers).
    public static let control: CGFloat = 10
    /// Tarjetas.
    public static let card: CGFloat = 16
    /// Modales.
    public static let modal: CGFloat = 24
}

/// Grosor estándar de borde.
public enum XFStroke {
    public static let hairline: CGFloat = 1
}
