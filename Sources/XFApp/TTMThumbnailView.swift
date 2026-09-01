// SPDX-License-Identifier: GPL-3.0-only

import SwiftUI
import XFDesign

/// Dibuja una `TTMThumbnail` escalada al tamaño disponible: la curva del disco
/// (línea) y, pegada abajo, la barrita de los tramos con el fader cerrado.
struct TTMThumbnailView: View {

    let thumbnail: TTMThumbnail
    /// Alto de la barrita de fader, en puntos.
    private let laneHeight: CGFloat = 3

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let curveH = max(1, h - laneHeight - 1)

            ZStack(alignment: .bottomLeading) {
                // fader cerrado
                ForEach(Array(thumbnail.faderClosed.enumerated()), id: \.offset) { _, range in
                    Rectangle()
                        .fill(XFColor.accent.opacity(0.55))
                        .frame(width: max(1, (range.upperBound - range.lowerBound) * w),
                               height: laneHeight)
                        .offset(x: range.lowerBound * w)
                }

                // curva del disco (y invertida: 1 = arriba)
                Path { path in
                    guard let first = thumbnail.curve.first else { return }
                    func point(_ c: CGPoint) -> CGPoint {
                        CGPoint(x: c.x * w, y: (1 - c.y) * curveH)
                    }
                    path.move(to: point(first))
                    for c in thumbnail.curve.dropFirst() { path.addLine(to: point(c)) }
                }
                .stroke(XFColor.textMuted,
                        style: StrokeStyle(lineWidth: 1.2, lineCap: .round, lineJoin: .round))
                .padding(.bottom, laneHeight + 1)
            }
        }
        .accessibilityHidden(true)   // decorativo; el nombre ya nombra el truco
    }
}
