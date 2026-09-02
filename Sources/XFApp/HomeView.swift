// SPDX-License-Identifier: GPL-3.0-only

import SwiftUI
import XFDesign

/// El Home: el mapa de la matriz, la racha y "Continuar" (`docs/UI_DESIGN.md`
/// §3.2). Dibuja un `HomeSummary`; los datos los arma `XFApp`.
///
/// Sustituye a la maqueta inerte de `Sources/xFlare/HomeScaffoldView.swift`.
public struct HomeView: View {

    private let summary: HomeSummary
    private let onContinue: () -> Void
    private let onSelect: (String) -> Void

    public init(summary: HomeSummary,
                onContinue: @escaping () -> Void = {},
                onSelect: @escaping (String) -> Void = { _ in }) {
        self.summary = summary
        self.onContinue = onContinue
        self.onSelect = onSelect
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: XFSpacing.xl) {
                XFWordmark(size: 30)
                header
                if let target = summary.continueTarget { continueCard(target) }
                matrix
            }
            .padding(XFSpacing.xl)
        }
        .background(XFColor.bg)
    }

    private var header: some View {
        HStack(spacing: XFSpacing.xl) {
            stat("Racha", "\(summary.streakDays) d")
            stat("Hoy", "\(summary.minutesToday) min",
                 muted: !summary.meetsDailyMinimum())
            stat("Dominados", "\(summary.masteredCount) / \(summary.cells.count)")
        }
    }

    private func stat(_ label: String, _ value: String, muted: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(XFFont.body(12)).foregroundColor(XFColor.textMuted)
            Text(value).font(XFFont.mono(20))
                .foregroundColor(muted ? XFColor.textMuted : XFColor.text)
        }
    }

    private func continueCard(_ target: HomeSummary.ContinueTarget) -> some View {
        Button(action: onContinue) {
            XFCard(raised: true) {
                HStack {
                    VStack(alignment: .leading, spacing: XFSpacing.xs) {
                        Text("Continuar").font(XFFont.body(12)).foregroundColor(XFColor.textMuted)
                        Text(target.name).font(XFFont.title(22))
                        Text("\(target.bpm) BPM").font(XFFont.mono(14)).foregroundColor(XFColor.accent)
                    }
                    Spacer()
                    Image(systemName: "play.fill").foregroundColor(XFColor.accent)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private var matrix: some View {
        VStack(alignment: .leading, spacing: XFSpacing.lg) {
            ForEach(summary.cellsByLevel, id: \.level) { group in
                VStack(alignment: .leading, spacing: XFSpacing.sm) {
                    Text(group.level).font(XFFont.body(13)).foregroundColor(XFColor.textMuted)
                    LazyVGrid(columns: Array(repeating: GridItem(.fixed(96), spacing: XFSpacing.sm),
                                             count: 6),
                              spacing: XFSpacing.sm) {
                        ForEach(group.cells) { cell in
                            MatrixCellView(cell: cell, thumbnail: summary.thumbnails[cell.scratchId])
                                .onTapGesture { onSelect(cell.scratchId) }
                        }
                    }
                }
            }
        }
    }
}

/// Una celda de la rejilla.
struct MatrixCellView: View {
    let cell: MatrixCell
    /// Gráfico TTM debajo del nombre; solo en algunas celdas.
    var thumbnail: TTMThumbnail? = nil

    var body: some View {
        VStack(spacing: 3) {
            Text(cell.name)
                .font(XFFont.body(11))
                .lineLimit(thumbnail == nil ? 2 : 1)
                .multilineTextAlignment(.center)
            if let thumbnail {
                TTMThumbnailView(thumbnail: thumbnail)
                    .frame(height: 22)
                    .opacity(locked ? 0.4 : 0.9)
            }
            Text(badge).font(XFFont.mono(11)).foregroundColor(XFColor.accent)
        }
        .frame(width: 96, height: thumbnail == nil ? 64 : 88)
        .padding(4)
        .background(RoundedRectangle(cornerRadius: XFRadius.control).fill(XFColor.surface))
        .overlay(RoundedRectangle(cornerRadius: XFRadius.control)
            .stroke(XFColor.stroke, lineWidth: XFStroke.hairline))
        .opacity(locked ? 0.4 : 1)
    }

    private var locked: Bool { cell.state == .locked }
    private var badge: String {
        switch cell.state {
        case .locked:              return "🔒"
        case .available:           return "·"
        case .practiced(let s):    return String(repeating: "★", count: s)
        case .mastered:            return "★★★"
        }
    }
}
