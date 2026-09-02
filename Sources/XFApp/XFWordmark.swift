// SPDX-License-Identifier: GPL-3.0-only

import SwiftUI
import XFDesign

/// El logotipo de xFlare: la marca (una **tapa de crossfader** de mesa de
/// batalla, con su silueta de reloj de arena) + el texto "xFlare". Sin ficheros:
/// todo `Shape` + `Text`, así funciona en cualquier build sin recursos.
///
/// Se usa en la barra de navegación (todas las pantallas de menú) y en la barra
/// superior de la práctica.
public struct XFWordmark: View {

    /// Altura de referencia del texto en puntos. La marca escala con él.
    private let size: CGFloat
    /// `false` = solo la marca (sin texto), para sitios muy estrechos.
    private let showText: Bool

    public init(size: CGFloat = 20, showText: Bool = true) {
        self.size = size
        self.showText = showText
    }

    public var body: some View {
        HStack(spacing: size * 0.34) {
            FaderCapMark()
                .fill(XFColor.accent)
                .frame(width: size * 0.60, height: size * 1.18)
                .shadow(color: XFColor.accent.opacity(0.35), radius: size * 0.14)

            if showText {
                (Text("x").foregroundColor(XFColor.accent)
                 + Text("Flare").foregroundColor(XFColor.text))
                    .font(.system(size: size, weight: .heavy, design: .rounded))
                    .kerning(-0.4)
            }
        }
        .accessibilityElement()
        .accessibilityLabel("xFlare")
    }
}

/// La silueta de una tapa de crossfader: un rectángulo con los lados largos
/// **cóncavos** (pellizcados en el centro), como las tapas de las mesas de
/// batalla. Es la marca del icono de la app.
struct FaderCapMark: Shape {

    func path(in r: CGRect) -> Path {
        var p = Path()
        let w = r.width, h = r.height
        let pinch = w * 0.30          // cuánto se estrechan los lados en el centro
        let round = w * 0.16          // redondeo de las esquinas

        p.move(to: CGPoint(x: round, y: 0))
        p.addLine(to: CGPoint(x: w - round, y: 0))
        p.addQuadCurve(to: CGPoint(x: w, y: round),
                       control: CGPoint(x: w, y: 0))
        // lado derecho, cóncavo hacia dentro
        p.addQuadCurve(to: CGPoint(x: w, y: h - round),
                       control: CGPoint(x: w - pinch, y: h / 2))
        p.addQuadCurve(to: CGPoint(x: w - round, y: h),
                       control: CGPoint(x: w, y: h))
        p.addLine(to: CGPoint(x: round, y: h))
        p.addQuadCurve(to: CGPoint(x: 0, y: h - round),
                       control: CGPoint(x: 0, y: h))
        // lado izquierdo, cóncavo hacia dentro
        p.addQuadCurve(to: CGPoint(x: 0, y: round),
                       control: CGPoint(x: pinch, y: h / 2))
        p.addQuadCurve(to: CGPoint(x: round, y: 0),
                       control: CGPoint(x: 0, y: 0))
        p.closeSubpath()
        return p
    }
}
