// SPDX-License-Identifier: GPL-3.0-only

import SwiftUI

/// Estilo de botón de xFlare. Dos variantes: `filled` (acción principal, relleno
/// de acento) y `bordered` (secundaria). Radio de control (10), transición de
/// 180 ms sin rebote (UI_DESIGN §2).
public struct XFButtonStyle: ButtonStyle {

    public enum Variant { case filled, bordered }

    private let variant: Variant
    public init(_ variant: Variant = .filled) { self.variant = variant }

    public func makeBody(configuration: Configuration) -> some View {
        let pressed = configuration.isPressed
        return configuration.label
            .font(XFFont.bodyMedium(13))
            .foregroundColor(variant == .filled ? XFColor.bg : XFColor.text)
            .padding(.horizontal, XFSpacing.md)
            .padding(.vertical, XFSpacing.xs)
            .background(
                RoundedRectangle(cornerRadius: XFRadius.control, style: .continuous)
                    .fill(variant == .filled ? XFColor.accent : XFColor.surfaceRaised)
                    .opacity(pressed ? 0.75 : 1)
            )
            .overlay(
                RoundedRectangle(cornerRadius: XFRadius.control, style: .continuous)
                    .stroke(XFColor.stroke, lineWidth: variant == .bordered ? XFStroke.hairline : 0)
            )
            .animation(.easeOut(duration: 0.18), value: pressed)
    }
}

public extension View {
    /// Atajo: `.buttonStyle(.xf())` / `.xf(.bordered)`.
    func xfButton(_ variant: XFButtonStyle.Variant = .filled) -> some View {
        buttonStyle(XFButtonStyle(variant))
    }
}
