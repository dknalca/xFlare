// SPDX-License-Identifier: GPL-3.0-only

import SwiftUI
import XFDesign

/// Pantalla de progreso por ejercicio y variante (`docs/UI_DESIGN.md` §3.4b).
/// Dibuja un `ExerciseProgressDisplay` ya formateado.
public struct ExerciseProgressView: View {

    private let display: ExerciseProgressDisplay

    public init(display: ExerciseProgressDisplay) {
        self.display = display
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: XFSpacing.lg) {
            Sparkline(scores: display.sparkline).frame(height: 60)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())],
                      alignment: .leading, spacing: XFSpacing.md) {
                stat("Intentos", "\(display.attempts)")
                stat("Mejor", display.bestScore + (display.bestScoreDate.map { " · \($0)" } ?? ""))
                stat("Última", display.lastScore)
                stat("Media de 5", display.averageOfLast5)
                stat("Estrellas", String(repeating: "★", count: display.stars))
                stat("Mejor BPM con 3★", display.bestBpmWith3Stars)
                stat("Sesgo medio", display.meanBias)
                stat("Tiempo total", display.totalPracticeTime)
            }
        }
        .padding(XFSpacing.xl)
        .background(XFColor.bg)
    }

    private func stat(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(XFFont.body(11)).foregroundColor(XFColor.textMuted)
            Text(value).font(XFFont.mono(15))
        }
    }
}

/// La "línea de puntuaciones" de los últimos 20 intentos.
struct Sparkline: View {
    let scores: [Int]

    var body: some View {
        GeometryReader { geo in
            Path { path in
                guard scores.count > 1, let lo = scores.min(), let hi = scores.max(), hi > lo else { return }
                let span = Double(hi - lo)
                for (i, s) in scores.enumerated() {
                    let x = geo.size.width * Double(i) / Double(scores.count - 1)
                    let y = geo.size.height * (1 - (Double(s - lo) / span))
                    let p = CGPoint(x: x, y: y)
                    if i == 0 { path.move(to: p) } else { path.addLine(to: p) }
                }
            }
            .stroke(XFColor.accent, lineWidth: 2)
        }
    }
}
