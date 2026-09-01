// SPDX-License-Identifier: GPL-3.0-only

import SwiftUI
import XFDesign

/// Dibuja una `TTMThumbnail` escalada al tamaño disponible: los tramos de la
/// curva del disco (con hueco donde el fader está cerrado) y un círculo pequeño
/// en cada apertura/cierre del fader.
struct TTMThumbnailView: View {

    let thumbnail: TTMThumbnail

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height

            ZStack {
                // tramos de curva (y invertida: 1 = arriba)
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

                // círculos de corte del fader
                Path { path in
                    let r: CGFloat = 2.2
                    for c in thumbnail.cuts {
                        let p = CGPoint(x: c.x * w, y: (1 - c.y) * h)
                        path.addEllipse(in: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2))
                    }
                }
                .stroke(XFColor.accent, lineWidth: 1)
            }
        }
        .accessibilityHidden(true)   // decorativo; el nombre ya nombra el truco
    }
}
