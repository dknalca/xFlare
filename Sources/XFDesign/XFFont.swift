// SPDX-License-Identifier: GPL-3.0-only

import SwiftUI

/// Tipografía (docs/UI_DESIGN.md §2). El sistema en macOS ya es SF Pro; los
/// números van en monoespaciada con cifras tabulares para que no bailen al
/// actualizarse 60 veces por segundo.
public enum XFFont {

    /// Títulos: SF Pro Display Semibold.
    public static func title(_ size: CGFloat = 22) -> Font {
        .system(size: size, weight: .semibold, design: .default)
    }

    /// Texto normal.
    public static func body(_ size: CGFloat = 13) -> Font {
        .system(size: size, weight: .regular, design: .default)
    }

    public static func bodyMedium(_ size: CGFloat = 13) -> Font {
        .system(size: size, weight: .medium, design: .default)
    }

    /// Números (BPM, ms, precisión). El `design: .monospaced` ya deja TODOS los
    /// glifos —dígitos incluidos— a ancho fijo, así que no bailan al
    /// actualizarse. (`Text.monospacedDigit()` es macOS 12; aquí el mínimo es 11.)
    public static func mono(_ size: CGFloat = 13) -> Font {
        .system(size: size, weight: .medium, design: .monospaced)
    }
}

public extension Text {
    /// Aplica la fuente de números (monoespaciada, cifras a ancho fijo).
    func xfNumber(_ size: CGFloat = 13) -> Text {
        self.font(XFFont.mono(size))
    }
}
