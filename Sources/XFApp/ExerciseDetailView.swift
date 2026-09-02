// SPDX-License-Identifier: GPL-3.0-only

import SwiftUI
import XFDesign

/// Ventana de detalle de un truco (`docs/UI_DESIGN.md` §3.6b). Al pinchar un
/// truco en la librería **no** se entra directo a practicar: primero se ve esto.
///
/// Izquierda: el dibujo TTM, qué es y de dónde viene. Derecha: las variantes con
/// la puntuación / estrellas que se llevan sacadas. El botón "Practicar" lanza la
/// variante seleccionada.
public struct ExerciseDetailView: View {

    private let display: ExerciseDetailDisplay
    private let onPractice: (_ variantId: String) -> Void
    private let onBack: () -> Void

    @State private var selected: String

    public init(display: ExerciseDetailDisplay,
                onPractice: @escaping (_ variantId: String) -> Void = { _ in },
                onBack: @escaping () -> Void = {}) {
        self.display = display
        self.onPractice = onPractice
        self.onBack = onBack
        // arranca en la primera variante desbloqueada (la base siempre lo está)
        _selected = State(initialValue:
            display.variants.first(where: { $0.option.isUnlocked })?.option.variantId ?? "base")
    }

    public var body: some View {
        VStack(spacing: 0) {
            topBar
            Divider().background(XFColor.stroke)
            HStack(alignment: .top, spacing: XFSpacing.xl) {
                leftColumn.frame(width: 380)
                rightColumn.frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(XFSpacing.xl)
            Spacer(minLength: 0)
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
            Button("Practicar") { onPractice(selected) }
                .xfButton(.filled)
                .disabled(display.exerciseId == nil)
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

    // MARK: - derecha: variantes con su marca

    private var rightColumn: some View {
        VStack(alignment: .leading, spacing: XFSpacing.xs) {
            Text("Variantes").font(XFFont.body(10)).foregroundColor(XFColor.textMuted)
            if display.variants.isEmpty {
                Text("Este truco todavía no tiene ejercicio en el currículo.")
                    .font(XFFont.body(12)).foregroundColor(XFColor.textMuted)
            } else {
                ForEach(display.variants) { row in variantRow(row) }
            }
        }
    }

    @ViewBuilder private func variantRow(_ row: ExerciseDetailDisplay.VariantRow) -> some View {
        let isSel = row.option.variantId == selected
        Button {
            if row.option.isUnlocked { selected = row.option.variantId }
        } label: {
            HStack(spacing: XFSpacing.sm) {
                Text(row.option.name).font(XFFont.bodyMedium(13))
                Text(String(format: "×%.2f", row.option.difficulty))
                    .font(XFFont.mono(10)).foregroundColor(XFColor.textMuted)
                Spacer()
                switch row.option.lock {
                case .unlocked:
                    Text(stars(row.stars)).font(XFFont.body(12)).foregroundColor(XFColor.accent)
                    Text(row.bestScore)
                        .font(XFFont.mono(11)).foregroundColor(XFColor.textMuted)
                        .frame(width: 52, alignment: .trailing)
                case .locked(let condition):
                    HStack(spacing: 4) {
                        Image(systemName: "lock.fill")
                        Text("Necesitas \(condition)").font(XFFont.body(11))
                    }
                    .foregroundColor(XFColor.textMuted)
                }
            }
            .padding(.vertical, 6).padding(.horizontal, XFSpacing.sm)
            .background(RoundedRectangle(cornerRadius: XFRadius.control)
                .fill(isSel ? XFColor.surfaceRaised : XFColor.surface))
            .opacity(row.option.isUnlocked ? 1 : 0.6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// "★★☆" — llenas hasta `n`, huecas hasta 3.
    private func stars(_ n: Int) -> String {
        let f = max(0, min(3, n))
        return String(repeating: "★", count: f) + String(repeating: "☆", count: 3 - f)
    }
}
