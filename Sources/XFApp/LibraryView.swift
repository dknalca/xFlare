// SPDX-License-Identifier: GPL-3.0-only

import SwiftUI
import XFDesign

/// El navegador de la librería (`docs/UI_DESIGN.md` §3.6). Dibuja un
/// `LibraryBrowser`; el filtrado lo hace él.
public struct LibraryView: View {

    private let browser: LibraryBrowser
    private let onSelect: (String) -> Void

    @State private var query = ""
    @State private var family: String?

    public init(browser: LibraryBrowser, onSelect: @escaping (String) -> Void = { _ in }) {
        self.browser = browser
        self.onSelect = onSelect
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: XFSpacing.md) {
            HStack {
                TextField("Buscar", text: $query).textFieldStyle(.roundedBorder).frame(width: 220)
                Picker("Familia", selection: $family) {
                    Text("Todas").tag(String?.none)
                    ForEach(browser.families, id: \.self) { Text($0).tag(String?.some($0)) }
                }
                .frame(width: 200)
            }

            // lista plana: todos los trucos, sin agrupar por nivel
            ScrollView {
                VStack(alignment: .leading, spacing: XFSpacing.xs) {
                    ForEach(entries) { entry in row(entry) }
                }
            }
        }
        .padding(XFSpacing.xl)
        .background(XFColor.bg)
    }

    private var entries: [LibraryEntry] {
        browser.filtered(query: query, family: family).sorted { $0.name < $1.name }
    }

    @ViewBuilder private func row(_ e: LibraryEntry) -> some View {
        LibraryRow(entry: e, onSelect: onSelect)
    }
}

/// Una fila de la librería, con realce al pasar el ratón.
private struct LibraryRow: View {
    let entry: LibraryEntry
    let onSelect: (String) -> Void
    @State private var hovering = false

    var body: some View {
        Button { onSelect(entry.scratchId) } label: {
            HStack {
                Text(entry.name).font(XFFont.bodyMedium(13))
                Text(entry.family).font(XFFont.body(11)).foregroundColor(XFColor.textMuted)
                Spacer()
                Text(entry.technique == "familia" ? "familia" : "\(entry.clickCount) clicks")
                    .font(XFFont.mono(11)).foregroundColor(XFColor.textMuted)
                if !entry.isUnlocked {
                    Image(systemName: "lock.fill").foregroundColor(XFColor.textMuted)
                }
                Image(systemName: "chevron.right")
                    .font(.system(size: 9))
                    .foregroundColor(hovering && entry.isUnlocked ? XFColor.accent : XFColor.textMuted)
            }
            .padding(.vertical, 7).padding(.horizontal, XFSpacing.sm)
            .background(RoundedRectangle(cornerRadius: XFRadius.control, style: .continuous)
                .fill(hovering && entry.isUnlocked ? XFColor.surface : .clear))
            .overlay(RoundedRectangle(cornerRadius: XFRadius.control, style: .continuous)
                .stroke(hovering && entry.isUnlocked ? XFColor.accent.opacity(0.6) : .clear, lineWidth: 1))
            .contentShape(Rectangle())
            .opacity(entry.isUnlocked ? 1 : 0.5)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: hovering)
    }
}
