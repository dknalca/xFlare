// SPDX-License-Identifier: GPL-3.0-only

import SwiftUI
import XFDesign

/// "Mi mesa" (`docs/UI_DESIGN.md` §3.8). Lista de perfiles con insignias; el
/// "probar en vivo" y la (re)calibración se disparan con los callbacks.
public struct MyTableView: View {

    private let table: MyTable
    private let onActivate: (String) -> Void
    private let onTestLive: (String) -> Void
    private let onCalibrate: (String) -> Void

    public init(table: MyTable,
                onActivate: @escaping (String) -> Void = { _ in },
                onTestLive: @escaping (String) -> Void = { _ in },
                onCalibrate: @escaping (String) -> Void = { _ in }) {
        self.table = table
        self.onActivate = onActivate
        self.onTestLive = onTestLive
        self.onCalibrate = onCalibrate
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: XFSpacing.sm) {
                ForEach(table.sorted) { row in
                    XFCard {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: XFSpacing.xs) {
                                    Text(row.name).font(XFFont.bodyMedium(14))
                                    if row.profileId == table.activeProfileId {
                                        badge("Activo", XFColor.accent)
                                    }
                                    badge(row.verified ? "Verificado" : "Sin verificar",
                                          row.verified ? XFColor.accent : XFColor.textMuted)
                                }
                                Text(row.source == .user ? "Perfil tuyo" : "De fábrica")
                                    .font(XFFont.body(11)).foregroundColor(XFColor.textMuted)
                                if let ms = row.latencyMs {
                                    Text(String(format: "%.1f ms", ms))
                                        .font(XFFont.mono(11)).foregroundColor(XFColor.textMuted)
                                }
                            }
                            Spacer()
                            Button("Probar") { onTestLive(row.profileId) }.xfButton(.bordered)
                            Button(row.hasCalibration ? "Recalibrar" : "Calibrar") {
                                onCalibrate(row.profileId)
                            }.xfButton(.bordered)
                            Button("Usar") { onActivate(row.profileId) }.xfButton(.filled)
                        }
                    }
                }
            }
            .padding(XFSpacing.xl)
        }
        .background(XFColor.bg)
    }

    private func badge(_ text: String, _ color: Color) -> some View {
        Text(text).font(XFFont.body(10)).foregroundColor(color)
            .padding(.horizontal, 5).padding(.vertical, 1)
            .overlay(RoundedRectangle(cornerRadius: 5).stroke(color, lineWidth: 1))
    }
}
