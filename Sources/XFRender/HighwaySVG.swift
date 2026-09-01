// SPDX-License-Identifier: GPL-3.0-only

import CoreGraphics
import Foundation

/// Serializa un `HighwayFrame` a un SVG **determinista**: mismas entradas ⇒
/// mismo texto, byte a byte. Se usa para los golden tests (B7.6) y sirve además
/// para exportar una toma o generar los previews de la notación.
///
/// Todas las coordenadas se redondean a **4 decimales** (política de ADR-028):
/// así un golden generado en `x86_64` pasa igual en `arm64` sin comparar los
/// últimos bits de coma flotante.
///
/// El eje Y se voltea (SVG es Y hacia abajo; los frames vienen con Y hacia
/// arriba, como SpriteKit).
public enum HighwaySVG {

    /// Documento SVG completo para `frame` con el encuadre `geometry`.
    public static func document(_ frame: HighwayFrame, geometry g: HighwayGeometry) -> String {
        let W = f(g.size.width), H = f(g.size.height)
        func fy(_ y: CGFloat) -> CGFloat { g.size.height - y }

        var lines: [String] = [
            "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"\(W)\" height=\"\(H)\" viewBox=\"0 0 \(W) \(H)\">",
            "<rect width=\"\(W)\" height=\"\(H)\" fill=\"#0B0D10\"/>",
        ]

        // carril de fader: tramos abiertos, franja inferior de alto laneHeight
        let laneTop = f(fy(g.laneHeight))
        for band in frame.faderBands where band.isOpen {
            let x = f(band.xRange.lowerBound)
            let bw = f(band.xRange.upperBound - band.xRange.lowerBound)
            lines.append("<rect class=\"lane-open\" x=\"\(x)\" y=\"\(laneTop)\" width=\"\(bw)\" height=\"\(f(g.laneHeight))\" fill=\"#F2F5F7\" fill-opacity=\"0.1\"/>")
        }

        // curva del patrón (fantasma)
        if frame.discCurve.count >= 2 {
            let pts = frame.discCurve.map { "\(f($0.x)),\(f(fy($0.y)))" }.joined(separator: " ")
            lines.append("<polyline class=\"ghost\" points=\"\(pts)\" fill=\"none\" stroke=\"#7A8794\" stroke-opacity=\"0.55\" stroke-width=\"3\"/>")
        }

        // cabeza de lectura
        let ph = f(frame.playheadX)
        lines.append("<line class=\"playhead\" x1=\"\(ph)\" y1=\"0\" x2=\"\(ph)\" y2=\"\(H)\" stroke=\"#3A444F\" stroke-width=\"1\"/>")

        // marcas de fader: ○ abre, ● cierra
        for p in frame.openMarks {
            lines.append("<circle class=\"open\" cx=\"\(f(p.x))\" cy=\"\(f(fy(p.y)))\" r=\"5\" fill=\"none\" stroke=\"#7A8794\" stroke-width=\"2\"/>")
        }
        for p in frame.closeMarks {
            lines.append("<circle class=\"close\" cx=\"\(f(p.x))\" cy=\"\(f(fy(p.y)))\" r=\"5\" fill=\"#34E1C4\"/>")
        }

        lines.append("</svg>")
        return lines.joined(separator: "\n") + "\n"
    }

    /// Formatea con 4 decimales en locale C y mata el `-0`.
    private static func f(_ value: CGFloat) -> String {
        let s = String(format: "%.4f", Double(value))
        return s == "-0.0000" ? "0.0000" : s
    }
}
