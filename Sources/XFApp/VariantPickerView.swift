// SPDX-License-Identifier: GPL-3.0-only

import SwiftUI
import XFDesign

/// Selector de variantes (`docs/UI_DESIGN.md` §3.15): muestra la **condición de
/// desbloqueo**, no solo el candado.
public struct VariantPickerView: View {

    private let options: [VariantOption]
    private let selected: String?
    private let onSelect: (String) -> Void

    public init(options: [VariantOption], selected: String? = nil,
                onSelect: @escaping (String) -> Void = { _ in }) {
        self.options = options
        self.selected = selected
        self.onSelect = onSelect
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: XFSpacing.xs) {
            ForEach(options) { opt in
                Button { if opt.isUnlocked { onSelect(opt.variantId) } } label: {
                    HStack {
                        Text(opt.name).font(XFFont.bodyMedium(13))
                        Text(String(format: "×%.2f", opt.difficulty))
                            .font(XFFont.mono(11)).foregroundColor(XFColor.textMuted)
                        Spacer()
                        switch opt.lock {
                        case .unlocked:
                            if opt.variantId == selected {
                                Image(systemName: "checkmark").foregroundColor(XFColor.accent)
                            }
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
                        .fill(opt.variantId == selected ? XFColor.surfaceRaised : XFColor.surface))
                    .opacity(opt.isUnlocked ? 1 : 0.6)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(XFSpacing.lg)
        .background(XFColor.bg)
    }
}
