// SPDX-License-Identifier: GPL-3.0-only

import SwiftUI

/// El control `‹ 80 BPM ›` de la barra de práctica (UI_DESIGN §3.3). Número en
/// monoespaciada tabular para que no salte al cambiar. No decide el rango de la
/// escalera de tempo — eso es de `XFEngine`; aquí solo se respeta `range`.
public struct BPMStepper: View {

    @Binding private var bpm: Int
    private let range: ClosedRange<Int>
    private let step: Int

    public init(bpm: Binding<Int>, range: ClosedRange<Int> = 40...200, step: Int = 5) {
        self._bpm = bpm
        self.range = range
        self.step = step
    }

    public var body: some View {
        HStack(spacing: XFSpacing.sm) {
            arrow("chevron.left", enabled: bpm - step >= range.lowerBound) {
                bpm = max(range.lowerBound, bpm - step)
            }
            Text("\(bpm) BPM")
                .xfNumber(14)
                .foregroundColor(XFColor.text)
                .frame(minWidth: 68)
                .accessibilityLabel("\(bpm) pulsaciones por minuto")
            arrow("chevron.right", enabled: bpm + step <= range.upperBound) {
                bpm = min(range.upperBound, bpm + step)
            }
        }
        .padding(.horizontal, XFSpacing.sm)
        .padding(.vertical, XFSpacing.xxs)
        .background(
            RoundedRectangle(cornerRadius: XFRadius.control, style: .continuous)
                .fill(XFColor.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: XFRadius.control, style: .continuous)
                .stroke(XFColor.stroke, lineWidth: XFStroke.hairline)
        )
    }

    private func arrow(_ systemName: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(enabled ? XFColor.text : XFColor.textMuted.opacity(0.4))
                .frame(width: 22, height: 22)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }
}
