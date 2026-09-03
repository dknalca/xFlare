// SPDX-License-Identifier: GPL-3.0-only

import SwiftUI
import XFDesign

/// F.0 / ADR-027 — la pantalla de **calentamiento** (`docs/WARMUP.md`): el plan
/// de hoy (4-6 ejercicios dominados con una variante distinta cada día y el
/// motivo por el que entran), un pase por ejercicio, y un botón para saltarlo
/// entero. No puntúa; sí registra (`mode:.warmup`).
struct WarmupView: View {

    let rows: [WarmupRow]
    var onPractice: (WarmupRow) -> Void = { _ in }
    var onSkip: () -> Void = {}

    var body: some View {
        VStack(alignment: .leading, spacing: XFSpacing.md) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Calentamiento").font(XFFont.title(22))
                    Text("Cinco minutos repasando lo que ya dominas, con una variante distinta cada día. "
                         + "No cuenta para las estrellas.")
                        .font(XFFont.body(12)).foregroundColor(XFColor.textMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                Button("Saltar", action: onSkip).xfButton(.bordered)
            }

            if rows.isEmpty {
                Text("No se ha podido montar el calentamiento (¿falta el catálogo?).")
                    .font(XFFont.body(13)).foregroundColor(XFColor.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, XFSpacing.sm)
            } else {
                ScrollView {
                    VStack(spacing: XFSpacing.xs) {
                        ForEach(Array(rows.enumerated()), id: \.element.id) { idx, row in
                            HStack(spacing: XFSpacing.sm) {
                                Text("\(idx + 1)")
                                    .font(XFFont.mono(13)).foregroundColor(XFColor.textMuted)
                                    .frame(width: 20)
                                VStack(alignment: .leading, spacing: 2) {
                                    HStack(spacing: 6) {
                                        Text(row.name).font(XFFont.bodyMedium(14))
                                        if !row.variantName.isEmpty {
                                            Text(row.variantName)
                                                .font(XFFont.body(10)).foregroundColor(XFColor.accent)
                                        }
                                    }
                                    HStack(spacing: 6) {
                                        Text(row.reason)
                                        Text("·").foregroundColor(XFColor.stroke)
                                        Text(row.phraseSummary)
                                    }
                                    .font(XFFont.body(11)).foregroundColor(XFColor.textMuted)
                                }
                                Spacer()
                                Button("Practicar") { onPractice(row) }
                                    .xfButton(.filled)
                            }
                            .padding(.vertical, 8).padding(.horizontal, XFSpacing.sm)
                            .background(RoundedRectangle(cornerRadius: XFRadius.control, style: .continuous)
                                .fill(XFColor.surface))
                        }
                    }
                }
            }
        }
        .padding(XFSpacing.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(XFColor.bg)
    }
}
