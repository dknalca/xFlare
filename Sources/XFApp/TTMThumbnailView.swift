// SPDX-License-Identifier: GPL-3.0-only

import SwiftUI
import XFDesign

/// Dibuja una `TTMThumbnail` escalada al tamaño disponible: la curva del disco
/// como **una línea continua** y un **círculo relleno ●** en cada corte (el
/// fader se cierra). Sin círculo al abrir, sin huecos: es el esquema simple TTM.
struct TTMThumbnailView: View {

    let thumbnail: TTMThumbnail

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height

            ZStack {
                // curva del disco (y invertida: 1 = arriba), continua
                Path { path in
                    let pts = thumbnail.curve
                    guard pts.count >= 2 else { return }
                    path.move(to: CGPoint(x: pts[0].x * w, y: (1 - pts[0].y) * h))
                    for c in pts.dropFirst() {
                        path.addLine(to: CGPoint(x: c.x * w, y: (1 - c.y) * h))
                    }
                }
                .stroke(XFColor.textMuted,
                        style: StrokeStyle(lineWidth: 1.2, lineCap: .round, lineJoin: .round))

                // corte: círculo relleno ● (el fader cierra; se supone corto)
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
