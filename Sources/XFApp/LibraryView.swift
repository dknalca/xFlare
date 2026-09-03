// SPDX-License-Identifier: GPL-3.0-only

import SwiftUI
import XFDesign

/// El navegador de **Trucos** (`docs/UI_DESIGN.md` §3.6). Antes se llamaba
/// "Librería"; ahora "Librería" es la de medios (instrumentales + samples).
/// Cada truco es una **tarjeta** con su nombre / familia / nº de clicks a la
/// izquierda y su **notación TTM** a la derecha.
public struct LibraryView: View {

    private let browser: LibraryBrowser
    private let onSelect: (String) -> Void

    @State private var query = ""
    @State private var family: String?

    public init(browser: LibraryBrowser, onSelect: @escaping (String) -> Void = { _ in }) {
        self.browser = browser
        self.onSelect = onSelect
    }

    // dos columnas de tarjetas: se ve más de un vistazo
    private let cols = [GridItem(.adaptive(minimum: 320), spacing: XFSpacing.md)]

    public var body: some View {
        VStack(alignment: .leading, spacing: XFSpacing.md) {
            HStack {
                Text("Trucos").font(XFFont.title(22))
                Spacer()
                TextField("Buscar", text: $query).textFieldStyle(.roundedBorder).frame(width: 200)
                Picker("Familia", selection: $family) {
                    Text("Todas").tag(String?.none)
                    ForEach(browser.families, id: \.self) { Text($0).tag(String?.some($0)) }
                }
                .frame(width: 180)
            }

            ScrollView {
                LazyVGrid(columns: cols, alignment: .leading, spacing: XFSpacing.md) {
                    ForEach(entries) { entry in
                        TrickCard(entry: entry, onSelect: onSelect)
                    }
                }
                .padding(.bottom, XFSpacing.xl)
            }
        }
        .padding(XFSpacing.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(XFColor.bg)
    }

    private var entries: [LibraryEntry] {
        browser.filtered(query: query, family: family)
            .sorted { ($0.level, $0.name) < ($1.level, $1.name) }
    }
}

/// Una tarjeta de truco: datos a la izquierda, notación TTM a la derecha.
private struct TrickCard: View {
    let entry: LibraryEntry
    let onSelect: (String) -> Void
    @State private var hovering = false

    private var subtitle: String {
        let clicks = entry.technique == "familia" ? "familia" : "\(entry.clickCount) clicks"
        return "\(entry.family) · N\(entry.level) · \(clicks)"
    }

    var body: some View {
        Button { if entry.isUnlocked { onSelect(entry.scratchId) } } label: {
            HStack(spacing: XFSpacing.sm) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 5) {
                        Text(entry.name).font(XFFont.bodyMedium(14)).lineLimit(1)
                        if !entry.isUnlocked {
                            Image(systemName: "lock.fill").font(.system(size: 9))
                                .foregroundColor(XFColor.textMuted)
                        }
                    }
                    Text(subtitle).font(XFFont.body(10)).foregroundColor(XFColor.textMuted)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    Text(hovering && entry.isUnlocked ? "Abrir ficha →" : " ")
                        .font(XFFont.body(9)).foregroundColor(XFColor.accent)
                }
                Spacer(minLength: XFSpacing.xs)
                Group {
                    if let thumb = entry.thumbnail {
                        TTMThumbnailView(thumbnail: thumb,
                                         soundingColor: entry.isUnlocked ? XFColor.text : XFColor.textMuted)
                    } else {
                        Color.clear
                    }
                }
                .frame(width: 132, height: 62)
                .background(RoundedRectangle(cornerRadius: 6).fill(XFColor.bg))
            }
            .padding(XFSpacing.sm)
            .frame(height: 92)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: XFRadius.control, style: .continuous)
                .fill(hovering && entry.isUnlocked ? XFColor.surfaceRaised : XFColor.surface))
            .overlay(RoundedRectangle(cornerRadius: XFRadius.control, style: .continuous)
                .stroke(hovering && entry.isUnlocked ? XFColor.accent.opacity(0.6) : XFColor.stroke,
                        lineWidth: 1))
            .contentShape(Rectangle())
            .opacity(entry.isUnlocked ? 1 : 0.55)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: hovering)
    }
}
