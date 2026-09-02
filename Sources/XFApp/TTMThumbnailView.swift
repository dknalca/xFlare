// SPDX-License-Identifier: GPL-3.0-only

import SwiftUI
import XFDesign

/// Dibuja una `TTMThumbnail` escalada al tamaño disponible: los tramos de la
/// curva del disco (hueco donde el fader está cerrado), un círculo **hueco** ○
/// donde el fader abre (empieza el sonido) y uno **relleno** ● donde cierra
/// (el corte), más un tick corto en cada phantom click.
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

                // fader ABRE: círculo hueco ○ (empieza a sonar)
                Path { path in
                    let r: CGFloat = 2.4
                    for c in thumbnail.openMarks {
                        let p = CGPoint(x: c.x * w, y: (1 - c.y) * h)
                        path.addEllipse(in: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2))
                    }
                }
                .stroke(XFColor.accent, lineWidth: 1.1)

                // fader CIERRA: círculo relleno ● (el corte / click)
                Path { path in
                    let r: CGFloat = 2.4
                    for c in thumbnail.closeMarks {
                        let p = CGPoint(x: c.x * w, y: (1 - c.y) * h)
                        path.addEllipse(in: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2))
                    }
                }
                .fill(XFColor.accent)

                // phantom clicks: tick vertical corto sobre la curva (el disco
                // se para al cambiar de sentido). Más discreto que un círculo.
                Path { path in
                    let half: CGFloat = 3
                    for c in thumbnail.phantomCuts {
                        let x = c.x * w
                        let y = (1 - c.y) * h
                        path.move(to: CGPoint(x: x, y: y - half))
                        path.addLine(to: CGPoint(x: x, y: y + half))
                    }
                }
                .stroke(XFColor.textMuted, lineWidth: 1)
            }
        }
        .accessibilityHidden(true)   // decorativo; el nombre ya nombra el truco
    }
}
