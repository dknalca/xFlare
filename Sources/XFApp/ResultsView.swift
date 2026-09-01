// SPDX-License-Identifier: GPL-3.0-only

import SwiftUI
import XFDesign

/// La pantalla de resultados con diagnóstico (`docs/UI_DESIGN.md` §3.4): las tres
/// estrellas con animación escalonada, la puntuación sobre el máximo, y debajo el
/// diagnóstico. Las estrellas apagadas **dicen su condición**.
public struct ResultsView: View {

    private let summary: ResultsSummary
    private let onRetry: () -> Void
    private let onContinue: () -> Void

    public init(summary: ResultsSummary,
                onRetry: @escaping () -> Void = {},
                onContinue: @escaping () -> Void = {}) {
        self.summary = summary
        self.onRetry = onRetry
        self.onContinue = onContinue
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: XFSpacing.xl) {
                header
                diagnosisBlock
                HStack {
                    Button("Otra vez", action: onRetry).xfButton(.bordered)
                    Button("Siguiente", action: onContinue).xfButton(.filled)
                }
            }
            .padding(XFSpacing.xl)
        }
        .background(XFColor.bg)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: XFSpacing.md) {
            HStack(spacing: XFSpacing.sm) {
                ForEach(Array(summary.stars.enumerated()), id: \.offset) { i, row in
                    Image(systemName: row.filled ? "star.fill" : "star")
                        .font(.system(size: 28))
                        .foregroundColor(row.filled ? XFColor.accent : XFColor.stroke)
                        .transition(.scale)
                        .animation(.easeOut(duration: 0.18).delay(Double(i) * 0.18), value: row.filled)
                }
            }
            HStack(alignment: .firstTextBaseline, spacing: XFSpacing.sm) {
                Text(summary.scoreText).font(XFFont.mono(30))
                Text("\(summary.accuracyPercent)%").foregroundColor(XFColor.textMuted)
                if summary.isBestScore {
                    Text("Record").font(XFFont.body(12)).foregroundColor(XFColor.accent)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(XFColor.accent, lineWidth: 1))
                }
            }

            // estrellas apagadas: su condición escrita
            ForEach(Array(summary.stars.enumerated()), id: \.offset) { _, row in
                if let condition = row.condition {
                    Text("\(row.title): \(condition)")
                        .font(XFFont.body(12))
                        .foregroundColor(XFColor.textMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var diagnosisBlock: some View {
        VStack(alignment: .leading, spacing: XFSpacing.sm) {
            ForEach(Array(summary.diagnostics.enumerated()), id: \.offset) { _, phrase in
                XFCard {
                    Text(phrase).font(XFFont.body(14))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}
