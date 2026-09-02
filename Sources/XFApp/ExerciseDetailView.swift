// SPDX-License-Identifier: GPL-3.0-only

import SwiftUI
import XFDesign

/// Ventana de detalle (`docs/UI_DESIGN.md` §3.6b). Al pinchar un truco (o una
/// familia) en la librería / el Home **no** se entra directo a practicar:
/// primero se ve esto.
///
/// - Truco suelto: izquierda el dibujo TTM + qué es + historia; derecha las
///   variantes con la puntuación sacada.
/// - Familia (Flare, Transformer): izquierda el texto de la familia; derecha un
///   bloque por miembro (1-click, 2-click, orbit…) con su dibujo, sus variantes
///   y su propio botón "Practicar".
public struct ExerciseDetailView: View {

    private let display: ExerciseDetailDisplay
    private let onPractice: (_ exerciseId: String, _ variantId: String) -> Void
    private let onBack: () -> Void

    /// Variante elegida por miembro (o `"__self__"` para la ficha de un truco).
    @State private var selectedByMember: [String: String]

    private static let selfKey = "__self__"

    public init(display: ExerciseDetailDisplay,
                onPractice: @escaping (_ exerciseId: String, _ variantId: String) -> Void = { _, _ in },
                onBack: @escaping () -> Void = {}) {
        self.display = display
        self.onPractice = onPractice
        self.onBack = onBack

        var sel: [String: String] = [:]
        // punto de entrada del gym (1 compás) si está desbloqueado, si no la
        // primera variante abierta, si no "base".
        func entry(_ rows: [ExerciseDetailDisplay.VariantRow]) -> String {
            rows.first { $0.option.variantId == "sub-1-2" && $0.option.isUnlocked }?.option.variantId
                ?? rows.first { $0.option.isUnlocked }?.option.variantId
                ?? "base"
        }
        if display.members.isEmpty {
            sel[Self.selfKey] = entry(display.variants)
        } else {
            for m in display.members { sel[m.scratchId] = entry(m.variants) }
        }
        _selectedByMember = State(initialValue: sel)
    }

    public var body: some View {
        VStack(spacing: 0) {
            topBar
            Divider().background(XFColor.stroke)
            ScrollView {
                HStack(alignment: .top, spacing: XFSpacing.xl) {
                    leftColumn.frame(width: 380)
                    rightColumn.frame(maxWidth: .infinity, alignment: .leading)
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
                    if let ex = display.exerciseId {
                        onPractice(ex, selectedByMember[Self.selfKey] ?? "base")
                    }
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

    // MARK: - derecha: variantes (truco suelto) o miembros (familia)

    @ViewBuilder private var rightColumn: some View {
        if display.members.isEmpty {
            VStack(alignment: .leading, spacing: XFSpacing.xs) {
                Text("Variantes").font(XFFont.body(10)).foregroundColor(XFColor.textMuted)
                if display.variants.isEmpty {
                    Text("Este truco todavía no tiene ejercicio en el currículo.")
                        .font(XFFont.body(12)).foregroundColor(XFColor.textMuted)
                } else {
                    ForEach(display.variants) { row in
                        variantRow(row, memberKey: Self.selfKey)
                    }
                }
            }
        } else {
            VStack(alignment: .leading, spacing: XFSpacing.lg) {
                ForEach(display.members) { member in memberBlock(member) }
            }
        }
    }

    @ViewBuilder private func memberBlock(_ m: ExerciseDetailDisplay.MemberBlock) -> some View {
        VStack(alignment: .leading, spacing: XFSpacing.xs) {
            HStack(spacing: XFSpacing.md) {
                if let thumb = m.thumbnail {
                    TTMThumbnailView(thumbnail: thumb)
                        .frame(width: 96, height: 54)
                        .background(RoundedRectangle(cornerRadius: XFRadius.control).fill(XFColor.surface))
                }
                Text(m.name).font(XFFont.bodyMedium(14))
                Spacer()
                Button("Practicar") {
                    if let ex = m.exerciseId {
                        onPractice(ex, selectedByMember[m.scratchId] ?? "base")
                    }
                }
                .xfButton(.filled)
                .disabled(m.exerciseId == nil)
            }
            ForEach(m.variants) { row in variantRow(row, memberKey: m.scratchId) }
        }
        .padding(XFSpacing.sm)
        .background(RoundedRectangle(cornerRadius: XFRadius.control).fill(XFColor.surface.opacity(0.4)))
    }

    @ViewBuilder private func variantRow(_ row: ExerciseDetailDisplay.VariantRow,
                                         memberKey: String) -> some View {
        let isSel = selectedByMember[memberKey] == row.option.variantId
        Button {
            if row.option.isUnlocked { selectedByMember[memberKey] = row.option.variantId }
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
