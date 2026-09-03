// SPDX-License-Identifier: GPL-3.0-only

import SwiftUI
import XFDesign

/// Dibuja una `TTMThumbnail` escalada al tamaño disponible: la curva del disco
/// **entera**, con los tramos que suenan (fader abierto) en color vivo y los
/// tramos cortados (fader cerrado) en gris apagado. Sin puntos.
struct TTMThumbnailView: View {

    let thumbnail: TTMThumbnail

    /// Color de los tramos que suenan.
    var soundingColor: Color = XFColor.text
    /// Color de los tramos cortados / en silencio.
    var mutedColor: Color = XFColor.textMuted.opacity(0.4)

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height

            ZStack {
                // un trazo por grupo de estado (y invertida: 1 = arriba)
                path(for: false, w: w, h: h)
                    .stroke(mutedColor,
                            style: StrokeStyle(lineWidth: 1.2, lineCap: .round, lineJoin: .round))
                path(for: true, w: w, h: h)
                    .stroke(soundingColor,
                            style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round))
            }
        }
        .accessibilityHidden(true)   // decorativo; el nombre ya nombra el truco
    }

    /// Une en un solo `Path` todos los tramos con el estado `sounding` pedido.
    private func path(for sounding: Bool, w: CGFloat, h: CGFloat) -> Path {
        Path { path in
            for seg in thumbnail.segments where seg.sounding == sounding && seg.points.count >= 2 {
                let pts = seg.points
                path.move(to: CGPoint(x: pts[0].x * w, y: (1 - pts[0].y) * h))
                for c in pts.dropFirst() {
                    path.addLine(to: CGPoint(x: c.x * w, y: (1 - c.y) * h))
                }
            }
        }
    }
}
