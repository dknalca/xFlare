// SPDX-License-Identifier: GPL-3.0-only

import SwiftUI

/// Insignia de acierto: la forma del `HitLevel` (no solo el color) y,
/// opcionalmente, el desfase en ms. Es lo que aparece en "últimos clicks
/// ●●●○○" y sobre cada click de la autopista.
public struct HitBadge: View {

    private let level: HitLevel
    private let offsetMs: Double?
    private let size: CGFloat

    public init(_ level: HitLevel, offsetMs: Double? = nil, size: CGFloat = 12) {
        self.level = level
        self.offsetMs = offsetMs
        self.size = size
    }

    public var body: some View {
        HStack(spacing: XFSpacing.xxs) {
            HitShape(level.shape)
                .frame(width: size, height: size)
                .foregroundColor(level.color)
            if let ms = offsetMs {
                Text(signed(ms))
                    .xfNumber(11)
                    .foregroundColor(XFColor.textMuted)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(offsetMs.map { "\(level.label), \(signed($0))" } ?? level.label)
    }

    private func signed(_ ms: Double) -> String {
        let r = (ms).rounded()
        return (r > 0 ? "+" : "") + String(format: "%.0f ms", r)
    }
}

/// Dibuja la forma distintiva de cada nivel (círculo lleno / círculo / rombo /
/// triángulo / cruz).
public struct HitShape: View {
    private let shape: HitLevel.Shape
    public init(_ shape: HitLevel.Shape) { self.shape = shape }

    public var body: some View {
        GeometryReader { geo in
            let s = min(geo.size.width, geo.size.height)
            let lw = max(1, s * 0.14)
            switch shape {
            case .filledCircle:
                Circle()
            case .circle:
                Circle().strokeBorder(lineWidth: lw)
            case .diamond:
                Diamond().fill()
            case .triangle:
                Triangle().fill()
            case .cross:
                CrossMark(lineWidth: lw).fill()
            }
        }
    }

    private struct Diamond: SwiftUI.Shape {
        func path(in r: CGRect) -> Path {
            var p = Path()
            p.move(to: CGPoint(x: r.midX, y: r.minY))
            p.addLine(to: CGPoint(x: r.maxX, y: r.midY))
            p.addLine(to: CGPoint(x: r.midX, y: r.maxY))
            p.addLine(to: CGPoint(x: r.minX, y: r.midY))
            p.closeSubpath()
            return p
        }
    }
    private struct Triangle: SwiftUI.Shape {
        func path(in r: CGRect) -> Path {
            var p = Path()
            p.move(to: CGPoint(x: r.midX, y: r.minY))
            p.addLine(to: CGPoint(x: r.maxX, y: r.maxY))
            p.addLine(to: CGPoint(x: r.minX, y: r.maxY))
            p.closeSubpath()
            return p
        }
    }
    private struct CrossMark: SwiftUI.Shape {
        let lineWidth: CGFloat
        func path(in r: CGRect) -> Path {
            var p = Path()
            let w = lineWidth
            p.addRect(CGRect(x: r.midX - w / 2, y: r.minY, width: w, height: r.height))
            p.addRect(CGRect(x: r.minX, y: r.midY - w / 2, width: r.width, height: w))
            return p.applying(CGAffineTransform(rotationAngle: .pi / 4)
                .concatenating(CGAffineTransform(translationX: r.midX, y: r.midY))
                .concatenating(CGAffineTransform(translationX: -r.midX, y: -r.midY)))
        }
    }
}
