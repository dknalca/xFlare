// SPDX-License-Identifier: GPL-3.0-only

import SwiftUI

public extension Color {
    /// Crea un `Color` sRGB desde un entero hexadecimal `0xRRGGBB`.
    init(hex: UInt32, opacity: Double = 1.0) {
        self.init(.sRGB,
                  red:   Double((hex >> 16) & 0xFF) / 255.0,
                  green: Double((hex >> 8) & 0xFF) / 255.0,
                  blue:  Double(hex & 0xFF) / 255.0,
                  opacity: opacity)
    }
}

/// La paleta de xFlare (docs/UI_DESIGN.md §2). Oscura, con un unico acento
/// saturado. Nunca `#000000` puro (vibra en OLED y cansa).
public enum XFColor {
    /// Fondo de ventana.
    public static let bg            = Color(hex: 0x0B0D10)
    /// Tarjetas y paneles.
    public static let surface       = Color(hex: 0x14181D)
    /// Modales y menus.
    public static let surfaceRaised = Color(hex: 0x1E242B)
    /// Bordes de 1 px.
    public static let stroke        = Color(hex: 0x2A323B)
    /// Texto principal.
    public static let text          = Color(hex: 0xF2F5F7)
    /// Texto secundario.
    public static let textMuted     = Color(hex: 0x9AA5B1)
    /// **Tú**: tu curva, tu fader, el foco.
    public static let accent        = Color(hex: 0x34E1C4)
    /// El patrón objetivo (gris al 35 %).
    public static let ghost         = Color(hex: 0x7A8794, opacity: 0.35)
    /// Rejilla de compás.
    public static let grid          = Color(hex: 0x232A32)
    /// Línea de negra.
    public static let gridBeat      = Color(hex: 0x3A444F)
}
