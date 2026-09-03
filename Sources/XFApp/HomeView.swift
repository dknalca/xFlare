// SPDX-License-Identifier: GPL-3.0-only

import SwiftUI
import XFDesign

/// El Home: el mapa de la matriz, la racha y "Continuar" (`docs/UI_DESIGN.md`
/// §3.2). Dibuja un `HomeSummary`; los datos los arma `XFApp`.
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
            HStack(alignment: .top, spacing: XFSpacing.xl) {
                VStack(alignment: .leading, spacing: XFSpacing.xl) {
                    HStack(alignment: .center) {
                        XFWordmark(size: 30)
                        Spacer()
                        header
                    }
                    if let target = summary.continueTarget { continueCard(target) }
                    matrix
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                legend
                    .frame(width: 214)
            }
            .padding(XFSpacing.xl)
            .frame(maxWidth: 1040, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(XFColor.bg)
    }

    // MARK: - leyenda: cómo leer el gráfico TTM

    private var legend: some View {
        VStack(alignment: .leading, spacing: XFSpacing.sm) {
            Text("CÓMO LEER EL GRÁFICO").font(XFFont.body(9)).kerning(0.6)
                .foregroundColor(XFColor.textMuted)

            legendExample

            Text("El trazo es el movimiento del vinilo. Sube = empujas hacia "
                 + "delante; baja = tiras hacia atrás. Se muestra un ciclo del gesto.")
                .font(XFFont.body(11)).foregroundColor(XFColor.textMuted)
                .fixedSize(horizontal: false, vertical: true)

            legendKey(color: XFColor.text, lineWidth: 2.4, dashed: false,
                      title: "Suena", detail: "fader abierto")
            legendKey(color: XFColor.textMuted, lineWidth: 1.8, dashed: true,
                      title: "Cortado", detail: "fader cerrado, silencio")
        }
        .padding(XFSpacing.md)
        .background(RoundedRectangle(cornerRadius: XFRadius.card, style: .continuous)
            .fill(XFColor.surface))
        .overlay(RoundedRectangle(cornerRadius: XFRadius.card, style: .continuous)
            .stroke(XFColor.stroke, lineWidth: XFStroke.hairline))
    }

    /// Una curva de ejemplo (baby con un corte) para que la leyenda enseñe los
    /// dos colores tal cual salen en las celdas.
    private var legendExample: some View {
        let mid: CGFloat = 0.5
        func seg(_ xs: ClosedRange<CGFloat>, sounding: Bool) -> TTMThumbnail.Segment {
            // media onda triangular en el rango pedido
            let steps = 12
            let pts = (0...steps).map { i -> CGPoint in
                let f = CGFloat(i) / CGFloat(steps)
                let x = xs.lowerBound + (xs.upperBound - xs.lowerBound) * f
                let tri = x < mid ? x / mid : (1 - x) / mid
                return CGPoint(x: x, y: 0.1 + 0.8 * tri)
            }
            return TTMThumbnail.Segment(points: pts, sounding: sounding)
        }
        let example = TTMThumbnail(segments: [
            seg(0.0...0.62, sounding: true),
            seg(0.62...1.0, sounding: false),
        ])
        return TTMThumbnailView(thumbnail: example)
            .frame(height: 40)
            .padding(.vertical, 2)
    }

    private func legendKey(color: Color, lineWidth: CGFloat, dashed: Bool,
                           title: String, detail: String) -> some View {
        HStack(spacing: XFSpacing.xs) {
            // muestra de trazo (lleno o a rayas, igual que en el gráfico)
            Path { p in
                p.move(to: CGPoint(x: 0, y: lineWidth / 2))
                p.addLine(to: CGPoint(x: 22, y: lineWidth / 2))
            }
            .stroke(color, style: StrokeStyle(lineWidth: lineWidth,
                                              dash: dashed ? [2.5, 2.5] : []))
            .frame(width: 22, height: lineWidth)
            Text(title).font(XFFont.bodyMedium(11)).foregroundColor(XFColor.text)
            Text(detail).font(XFFont.body(10)).foregroundColor(XFColor.textMuted)
            Spacer(minLength: 0)
        }
    }

    // MARK: - cabecera: racha / hoy / dominados en pastillas

    private var header: some View {
        HStack(spacing: XFSpacing.sm) {
            statPill("Racha", "\(summary.streakDays)", unit: "días")
            statPill("Hoy", "\(summary.minutesToday)", unit: "min",
                     muted: !summary.meetsDailyMinimum())
            statPill("Dominados", "\(summary.masteredCount)", unit: "/ \(summary.cells.count)")
        }
    }

    private func statPill(_ label: String, _ value: String, unit: String,
                          muted: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label.uppercased()).font(XFFont.body(9)).kerning(0.5)
                .foregroundColor(XFColor.textMuted)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value).font(XFFont.mono(18))
                    .foregroundColor(muted ? XFColor.textMuted : XFColor.text)
                Text(unit).font(XFFont.body(10)).foregroundColor(XFColor.textMuted)
            }
        }
        .padding(.horizontal, XFSpacing.sm)
        .padding(.vertical, XFSpacing.xs)
        .background(RoundedRectangle(cornerRadius: XFRadius.control, style: .continuous)
            .fill(XFColor.surface))
        .overlay(RoundedRectangle(cornerRadius: XFRadius.control, style: .continuous)
            .stroke(XFColor.stroke, lineWidth: XFStroke.hairline))
    }

    // MARK: - Continuar

    private func continueCard(_ target: HomeSummary.ContinueTarget) -> some View {
        Button(action: onContinue) {
            HStack(spacing: XFSpacing.md) {
                RoundedRectangle(cornerRadius: 2).fill(XFColor.accent).frame(width: 3, height: 44)
                VStack(alignment: .leading, spacing: 3) {
                    Text("CONTINUAR").font(XFFont.body(9)).kerning(0.6)
                        .foregroundColor(XFColor.textMuted)
                    Text(target.name).font(XFFont.title(22))
                    Text("\(target.bpm) BPM").font(XFFont.mono(13)).foregroundColor(XFColor.accent)
                }
                Spacer()
                Image(systemName: "play.circle.fill")
                    .font(.system(size: 34)).foregroundColor(XFColor.accent)
            }
            .padding(XFSpacing.md)
            .background(RoundedRectangle(cornerRadius: XFRadius.card, style: .continuous)
                .fill(XFColor.surfaceRaised))
            .overlay(RoundedRectangle(cornerRadius: XFRadius.card, style: .continuous)
                .stroke(XFColor.accent.opacity(0.35), lineWidth: XFStroke.hairline))
        }
        .buttonStyle(.plain)
    }

    // MARK: - matriz por niveles

    private var matrix: some View {
        VStack(alignment: .leading, spacing: XFSpacing.xl) {
            ForEach(summary.cellsByLevel, id: \.level) { group in
                VStack(alignment: .leading, spacing: XFSpacing.sm) {
                    HStack(spacing: XFSpacing.xs) {
                        Text("Nivel " + String(group.level.dropFirst()))
                            .font(XFFont.bodyMedium(13)).foregroundColor(XFColor.text)
                        Rectangle().fill(XFColor.stroke).frame(height: 1)
                    }
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 104), spacing: XFSpacing.sm)],
                              alignment: .leading, spacing: XFSpacing.sm) {
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

    @State private var hovering = false
    private var hot: Bool { hovering && !locked }

    var body: some View {
        VStack(spacing: 4) {
            HStack(spacing: 4) {
                Text(cell.name)
                    .font(XFFont.bodyMedium(11))
                    .lineLimit(1).truncationMode(.tail)
                if cell.isFamily {
                    Image(systemName: "square.stack.3d.up")
                        .font(.system(size: 8)).foregroundColor(XFColor.textMuted)
                }
                Spacer(minLength: 0)
            }
            if let thumbnail {
                TTMThumbnailView(thumbnail: thumbnail)
                    .frame(height: 26)
                    .opacity(locked ? 0.35 : 0.9)
            }
            HStack {
                badge
                Spacer(minLength: 0)
            }
        }
        .frame(height: thumbnail == nil ? 60 : 92)
        .padding(XFSpacing.xs)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: XFRadius.control, style: .continuous)
            .fill(hot ? XFColor.surfaceRaised
                  : mastered ? XFColor.accent.opacity(0.08) : XFColor.surface))
        .overlay(RoundedRectangle(cornerRadius: XFRadius.control, style: .continuous)
            .stroke(hot ? XFColor.accent : borderColor, lineWidth: hot ? 1.5 : XFStroke.hairline))
        .shadow(color: XFColor.accent.opacity(hot ? 0.25 : 0), radius: 6)
        .opacity(locked ? 0.5 : 1)
        .scaleEffect(hot ? 1.025 : 1)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: hovering)
    }

    private var locked: Bool { cell.state == .locked }
    private var mastered: Bool { cell.state == .mastered }

    private var borderColor: Color {
        switch cell.state {
        case .locked:              return XFColor.stroke
        case .available:           return XFColor.textMuted.opacity(0.4)
        case .practiced:           return XFColor.accent.opacity(0.5)
        case .mastered:            return XFColor.accent
        }
    }

    @ViewBuilder private var badge: some View {
        switch cell.state {
        case .locked:
            Image(systemName: "lock.fill").font(.system(size: 9)).foregroundColor(XFColor.textMuted)
        case .available:
            Text("nuevo").font(XFFont.body(9)).foregroundColor(XFColor.textMuted)
        case .practiced(let s):
            Text(String(repeating: "★", count: s) + String(repeating: "☆", count: max(0, 3 - s)))
                .font(XFFont.mono(10)).foregroundColor(XFColor.accent)
        case .mastered:
            Text("★★★").font(XFFont.mono(10)).foregroundColor(XFColor.accent)
        }
    }
}
