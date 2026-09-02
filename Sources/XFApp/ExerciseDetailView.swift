// SPDX-License-Identifier: GPL-3.0-only

import SwiftUI
import XFDesign

/// Ventana de detalle (`docs/UI_DESIGN.md` §3.6b). Al pinchar un truco (o una
/// familia) en la librería / el Home **no** se entra directo a practicar:
/// primero se ve esto.
///
/// - Truco suelto: izquierda el dibujo TTM + qué es + historia; arriba "Practicar".
/// - Familia (Flare, Transformer): izquierda el texto de la familia; derecha un
///   bloque por miembro (1-click, 2-click, orbit…) con su dibujo y su "Practicar".
///
/// Las **variantes** están desactivadas de momento (feedback 2026-09-02): la
/// ficha solo ofrece la base. Volverán con las puntuaciones.
public struct ExerciseDetailView: View {

    private let display: ExerciseDetailDisplay
    private let onPractice: (_ exerciseId: String, _ variantId: String) -> Void
    private let onBack: () -> Void

    public init(display: ExerciseDetailDisplay,
                onPractice: @escaping (_ exerciseId: String, _ variantId: String) -> Void = { _, _ in },
                onBack: @escaping () -> Void = {}) {
        self.display = display
        self.onPractice = onPractice
        self.onBack = onBack
    }

    public var body: some View {
        VStack(spacing: 0) {
            topBar
            Divider().background(XFColor.stroke)
            ScrollView {
                HStack(alignment: .top, spacing: XFSpacing.xl) {
                    leftColumn.frame(width: 380)
                    if !display.members.isEmpty {
                        membersColumn.frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(XFSpacing.xl)
            }
        }
        .background(XFColor.bg)
        .foregroundColor(XFColor.text)
    }

    // MARK: - barra superior

    private var topBar: some View {
        HStack(spacing: XFSpacing.md) {
            Button(action: onBack) { Image(systemName: "chevron.left") }
                .buttonStyle(.plain)
            Text(display.name).font(XFFont.bodyMedium(16))
            Spacer()
            // en una familia se practica por miembro; el botón global solo sale
            // para un truco suelto.
            if display.members.isEmpty {
                Button("Practicar") {
                    if let ex = display.exerciseId { onPractice(ex, "base") }
                }
                .xfButton(.filled)
                .disabled(display.exerciseId == nil)
            }
        }
        .padding(.horizontal, XFSpacing.lg)
        .padding(.vertical, XFSpacing.sm)
        .background(XFColor.surface)
    }

    // MARK: - izquierda: qué es y de dónde viene

    private var leftColumn: some View {
        VStack(alignment: .leading, spacing: XFSpacing.md) {
            if let thumb = display.thumbnail {
                TTMThumbnailView(thumbnail: thumb)
                    .frame(height: 140)
                    .padding(XFSpacing.sm)
                    .background(RoundedRectangle(cornerRadius: XFRadius.control).fill(XFColor.surface))
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(display.name).font(XFFont.bodyMedium(15))
                Text(subtitle).font(XFFont.body(11)).foregroundColor(XFColor.textMuted)
            }

            Text(display.description)
                .font(XFFont.body(13))
                .fixedSize(horizontal: false, vertical: true)

            if let history = display.history {
                Divider().background(XFColor.stroke)
                Text("Historia").font(XFFont.body(10)).foregroundColor(XFColor.textMuted)
                Text(history)
                    .font(XFFont.body(12)).foregroundColor(XFColor.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var subtitle: String {
        var s = ""
        if let l = display.level { s += "L\(l) · " }
        s += display.family
        if !display.technique.isEmpty, display.technique != "ninguna" {
            s += " · \(display.technique)"
        }
        return s
    }

    // MARK: - derecha: miembros de la familia

    private var membersColumn: some View {
        VStack(alignment: .leading, spacing: XFSpacing.sm) {
            Text("Trucos de la familia").font(XFFont.body(10)).foregroundColor(XFColor.textMuted)
            ForEach(display.members) { m in
                HStack(spacing: XFSpacing.md) {
                    if let thumb = m.thumbnail {
                        TTMThumbnailView(thumbnail: thumb)
                            .frame(width: 96, height: 54)
                            .background(RoundedRectangle(cornerRadius: XFRadius.control).fill(XFColor.surface))
                    }
                    Text(m.name).font(XFFont.bodyMedium(14))
                    Spacer()
                    Button("Practicar") {
                        if let ex = m.exerciseId { onPractice(ex, "base") }
                    }
                    .xfButton(.filled)
                    .disabled(m.exerciseId == nil)
                }
                .padding(XFSpacing.sm)
                .background(RoundedRectangle(cornerRadius: XFRadius.control).fill(XFColor.surface.opacity(0.4)))
            }
        }
    }
}
