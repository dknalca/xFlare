// SPDX-License-Identifier: GPL-3.0-only

import SwiftUI
import XFDesign

/// F.0 / ADR-027 — la pantalla de **calentamiento** (`docs/WARMUP.md`).
///
/// La app **sugiere** un plan (histórico si lo hay; si no, la rutina de arranque
/// Forward Cut → Reverse Cut → Chirp → Transformer) pero el usuario **manda**:
/// puede borrar una fila que no le apetezca, doblar o partir su duración con
/// ×2 / ÷2, y añadir ejercicios de la librería con "+". "Empezar calentamiento"
/// arranca UNA sola sesión con la lista ya editada, en "repite conmigo", y
/// `LivePracticeView` encadena el resto. No puntúa; sí registra (`mode:.warmup`).
struct WarmupView: View {

    let rows: [WarmupRow]
    let library: [WarmupPickable]
    var onStart: ([WarmupRow]) -> Void = { _ in }
    var onSkip: () -> Void = {}

    // La lista viva que se edita. Se siembra una vez desde `rows` en `.onAppear`
    // (el patrón seguro: un `@State` sembrado desde un parámetro en el `init` no
    // se actualizaría si el padre pasa otro valor, ver CLAUDE.md §convenciones).
    @State private var edited: [WarmupRow] = []
    @State private var seeded = false

    private let minPhrases = 2
    private let maxPhrases = 32

    var body: some View {
        VStack(alignment: .leading, spacing: XFSpacing.md) {
            header

            if edited.isEmpty && library.isEmpty {
                Text("No se ha podido montar el calentamiento (¿falta el catálogo?).")
                    .font(XFFont.body(13)).foregroundColor(XFColor.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, XFSpacing.sm)
            } else {
                ScrollView {
                    VStack(spacing: XFSpacing.xs) {
                        ForEach(Array(edited.enumerated()), id: \.element.id) { idx, row in
                            rowView(idx: idx, row: row)
                        }
                        addRow
                    }
                }
                totalLine
            }
        }
        .padding(XFSpacing.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(XFColor.bg)
        .onAppear {
            if !seeded { edited = rows; seeded = true }
        }
    }

    // MARK: - cabecera

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Calentamiento").font(XFFont.title(22))
                Text("La app sugiere el plan; ajústalo a tu gusto (borra, sube o baja la "
                     + "duración, añade ejercicios) y dale a empezar. No cuenta para las estrellas.")
                    .font(XFFont.body(12)).foregroundColor(XFColor.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            HStack(spacing: XFSpacing.sm) {
                Button("Saltar", action: onSkip).xfButton(.bordered)
                Button("Empezar calentamiento") { onStart(edited) }
                    .xfButton(.filled)
                    .disabled(edited.isEmpty)
            }
        }
    }

    // MARK: - fila

    private func rowView(idx: Int, row: WarmupRow) -> some View {
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

            // ÷2 / ×2 sobre el nº de frases (la duración del ejercicio).
            HStack(spacing: 2) {
                iconButton("divide", enabled: row.phraseCount > minPhrases) {
                    setPhrases(idx, max(minPhrases, row.phraseCount / 2))
                }
                Text("\(row.phraseCount)×\(row.phraseBars)")
                    .font(XFFont.mono(11)).foregroundColor(XFColor.textMuted)
                    .frame(width: 34)
                iconButton("multiply", enabled: row.phraseCount < maxPhrases) {
                    setPhrases(idx, min(maxPhrases, row.phraseCount * 2))
                }
            }

            iconButton("trash", enabled: true) { edited.remove(at: idx) }
        }
        .padding(.vertical, 8).padding(.horizontal, XFSpacing.sm)
        .background(RoundedRectangle(cornerRadius: XFRadius.control, style: .continuous)
            .fill(XFColor.surface))
    }

    // Botón "+" con el menú de la librería (agrupado por familia, sin repetir el
    // encabezado). Añade una fila nueva de 8 frases de 2 compases.
    private var addRow: some View {
        Menu {
            ForEach(library) { pick in
                Button(pick.familyName.isEmpty ? pick.name : "\(pick.name)  ·  \(pick.familyName)") {
                    addExercise(pick)
                }
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "plus.circle")
                Text("Añadir ejercicio").font(XFFont.body(12))
                Spacer()
            }
            .foregroundColor(XFColor.accent)
            .padding(.vertical, 8).padding(.horizontal, XFSpacing.sm)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: XFRadius.control, style: .continuous)
                .strokeBorder(XFColor.stroke, style: StrokeStyle(lineWidth: 1, dash: [3, 3])))
        }
        .menuStyle(.borderlessButton)
        .disabled(library.isEmpty)
    }

    private var totalLine: some View {
        let bars = edited.reduce(0) { $0 + $1.totalBars }
        return Text("\(edited.count) ejercicio\(edited.count == 1 ? "" : "s") · \(bars) compases en total")
            .font(XFFont.body(11)).foregroundColor(XFColor.textMuted)
    }

    // MARK: - edición

    private func setPhrases(_ idx: Int, _ n: Int) {
        guard edited.indices.contains(idx) else { return }
        edited[idx].phraseCount = n
    }

    private func addExercise(_ pick: WarmupPickable) {
        edited.append(WarmupRow(exerciseId: pick.exerciseId, variantId: "base",
                                name: pick.name, variantName: "",
                                reason: "Añadido a mano", phraseBars: 2, phraseCount: 8))
    }

    private func iconButton(_ systemName: String, enabled: Bool,
                            _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 12))
                .frame(width: 24, height: 24)
                .foregroundColor(enabled ? XFColor.text : XFColor.textMuted.opacity(0.4))
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }
}
