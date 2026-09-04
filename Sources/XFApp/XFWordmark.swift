// SPDX-License-Identifier: GPL-3.0-only

import SwiftUI
import XFDesign

/// El logotipo de xFlare: la marca (una **miniatura del icono de la app** — la
/// placa con el riel del crossfader y las dos tapas, viva y fantasma) + el
/// texto "xFlare". Sin ficheros: todo `Shape` + `Text`, así funciona en
/// cualquier build sin recursos. Mismo motivo que `icon/xflare.svg`.
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
        HStack(spacing: size * 0.26) {
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

    /// La marca es una **miniatura del icono de la app** (`icon/xflare.svg`): la
    /// placa, el riel del crossfader, la tapa fantasma (el objetivo) y la tapa
    /// viva de acento con su **borde claro** y su **surco de agarre verde
    /// medio**. Antes era una silueta plana con un corte que sobre el tema
    /// oscuro se leía como una mancha verde sin detalle. Todo `Shape`: sin
    /// recursos.
    private var mark: some View {
        let s = size
        let plate = s * 1.18
        let corner = s * 0.30
        let capW = s * 0.54, capH = s * 1.00
        let capX = s * 0.15            // la tapa viva, un poco a la derecha
        let ghostX = -s * 0.22
        let stroke = max(0.75, s * 0.028)

        return ZStack {
            RoundedRectangle(cornerRadius: corner, style: .continuous)
                .fill(XFColor.surfaceRaised)

            ZStack {
                // riel del crossfader
                Capsule().fill(XFColor.surface)
                    .overlay(Capsule().stroke(XFColor.stroke, lineWidth: max(0.5, s * 0.02)))
                    .frame(width: s * 1.02, height: s * 0.24)

                // tapa fantasma (el objetivo), detrás
                FaderCapMark().fill(XFColor.textMuted.opacity(0.28))
                    .frame(width: capW, height: capH)
                    .offset(x: ghostX)

                // tapa viva: acento + borde CLARO (separa la tapa del fondo,
                // como el icono)
                FaderCapMark().fill(XFColor.accent)
                    .overlay(FaderCapMark().stroke(Color.white.opacity(0.7),
                                                   lineWidth: max(1, s * 0.03)))
                    .frame(width: capW, height: capH)
                    .offset(x: capX)

                // surco de agarre: verde MEDIO (antes casi negro / de lado a lado)
                Capsule().fill(Color(hex: 0x0F6F62))
                    .frame(width: capW * 0.72, height: max(2, s * 0.10))
                    .offset(x: capX)

                // brillo superior de la tapa
                Capsule().fill(Color.white.opacity(0.38))
                    .frame(width: capW * 0.46, height: max(1, s * 0.045))
                    .offset(x: capX, y: -capH * 0.32)
            }
            .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))

            RoundedRectangle(cornerRadius: corner, style: .continuous)
                .stroke(XFColor.stroke, lineWidth: stroke)
        }
        .frame(width: plate, height: plate)
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
