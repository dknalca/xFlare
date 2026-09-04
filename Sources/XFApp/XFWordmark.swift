// SPDX-License-Identifier: GPL-3.0-only

import SwiftUI
import XFDesign

/// El logotipo de xFlare: la marca (una **tapa de crossfader** de mesa de
/// batalla, con su silueta de reloj de arena y el surco del fader) + el texto
/// "xFlare". Sin ficheros: todo `Shape` + `Text`, así funciona en cualquier
/// build sin recursos. Mismo motivo que el icono de la app (`icon/xflare.svg`).
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
        HStack(spacing: size * 0.36) {
            mark

            if showText {
                (Text("x").foregroundColor(XFColor.accent)
                 + Text("Flare").foregroundColor(XFColor.text))
                    .font(.system(size: size, weight: .bold, design: .default))
                    .kerning(size * 0.005)
            }
        }
        .accessibilityElement()
        .accessibilityLabel("xFlare")
    }

    /// La tapa del crossfader: silueta de acento + surco del fader + un brillo
    /// tenue arriba. Las partes que antes iban en un tono **oscuro** (el surco,
    /// que usaba el color de fondo casi negro) ahora van en **claro**: sobre el
    /// tema oscuro de la app la marca se leía como una mancha verde sin detalle.
    private var mark: some View {
        let w = size * 0.62, h = size * 1.16
        return ZStack {
            FaderCapMark().fill(XFColor.accent)
            // surco del fader (indicador de posición): CLARO, como un corte de
            // luz en la tapa. Antes era `XFColor.bg` y desaparecía.
            Capsule().fill(XFColor.text)
                .frame(width: w * 0.66, height: max(1.5, h * 0.12))
            // brillo superior, muy sutil
            Capsule().fill(Color.white.opacity(0.28))
                .frame(width: w * 0.46, height: max(1, h * 0.05))
                .offset(y: -h * 0.31)
        }
        .frame(width: w, height: h)
        .compositingGroup()
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
