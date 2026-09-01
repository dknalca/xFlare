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

            ScrollView {
                VStack(alignment: .leading, spacing: XFSpacing.lg) {
                    ForEach(groups, id: \.level) { group in
                        VStack(alignment: .leading, spacing: XFSpacing.xs) {
                            Text("L\(group.level)").font(XFFont.body(13)).foregroundColor(XFColor.textMuted)
                            ForEach(group.entries) { entry in
                                row(entry)
                            }
                        }
                    }
                }
            }
        }
        .padding(XFSpacing.xl)
        .background(XFColor.bg)
    }

    private var groups: [(level: Int, entries: [LibraryEntry])] {
        browser.groupedByLevel(query: query, family: family)
    }

    private func row(_ e: LibraryEntry) -> some View {
        Button { onSelect(e.scratchId) } label: {
            HStack {
                Text(e.name).font(XFFont.bodyMedium(13))
                Text(e.family).font(XFFont.body(11)).foregroundColor(XFColor.textMuted)
                Spacer()
                Text("\(e.clickCount) clicks").font(XFFont.mono(11)).foregroundColor(XFColor.textMuted)
                if !e.isUnlocked { Image(systemName: "lock.fill").foregroundColor(XFColor.textMuted) }
            }
            .padding(.vertical, 4)
            .opacity(e.isUnlocked ? 1 : 0.5)
        }
        .buttonStyle(.plain)
    }
}
