// SPDX-License-Identifier: GPL-3.0-only

import SwiftUI
import XFDesign

/// Dibuja una `TTMThumbnail` escalada al tamaño disponible: la curva del disco
/// **solo donde suena** (tramos con el fader abierto) y un **círculo relleno ●**
/// por cada corte, alineados en una fila arriba (la "pista de fader" del TTM).
struct TTMThumbnailView: View {

    let thumbnail: TTMThumbnail

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height

            ZStack {
                // curva del disco (y invertida: 1 = arriba), un trazo por tramo
                // que suena; el hueco mudo no se dibuja
                Path { path in
                    for seg in thumbnail.segments where seg.count >= 2 {
                        path.move(to: CGPoint(x: seg[0].x * w, y: (1 - seg[0].y) * h))
                        for c in seg.dropFirst() {
                            path.addLine(to: CGPoint(x: c.x * w, y: (1 - c.y) * h))
                        }
                    }
                }
                .stroke(XFColor.textMuted,
                        style: StrokeStyle(lineWidth: 1.2, lineCap: .round, lineJoin: .round))

                // cortes: círculos rellenos ● en una fila cerca del borde superior
                Path { path in
                    let r: CGFloat = 2.6
                    for c in thumbnail.cuts {
                        let p = CGPoint(x: c.x * w, y: (1 - c.y) * h)
                        path.addEllipse(in: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2))
                    }
                }
                .fill(XFColor.accent)
            }
        }
        .accessibilityHidden(true)   // decorativo; el nombre ya nombra el truco
    }
}
