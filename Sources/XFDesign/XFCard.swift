// SPDX-License-Identifier: GPL-3.0-only

import SwiftUI

/// Contenedor estándar: fondo de superficie, radio de tarjeta, borde de 1 px.
/// Sin sombra — la jerarquía se marca con el color de superficie (UI_DESIGN §2).
public struct XFCard<Content: View>: View {

    private let raised: Bool
    private let padding: CGFloat
    private let content: Content

    /// - Parameters:
    ///   - raised: usa `surfaceRaised` (modales/menús) en vez de `surface`.
    ///   - padding: relleno interior (por defecto `md` = 16).
    public init(raised: Bool = false,
                padding: CGFloat = XFSpacing.md,
                @ViewBuilder content: () -> Content) {
        self.raised = raised
        self.padding = padding
        self.content = content()
    }

    public var body: some View {
        content
            .padding(padding)
            .background(
                RoundedRectangle(cornerRadius: XFRadius.card, style: .continuous)
                    .fill(raised ? XFColor.surfaceRaised : XFColor.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: XFRadius.card, style: .continuous)
                    .stroke(XFColor.stroke, lineWidth: XFStroke.hairline)
            )
    }
}
