// SPDX-License-Identifier: GPL-3.0-only

import SwiftUI
import XFDesign
import XFRender
import XFNotation

/// La pantalla de práctica: la autopista (`docs/UI_DESIGN.md` §3.3). Scope a la
/// izquierda, autopista a la derecha, barra fina arriba y barra de feedback
/// abajo. `Esc` sale siempre, sin diálogo.
///
/// La lógica de sesión, el reloj y el scoring van por fuera; esta vista recibe el
/// `PracticeHUD` ya montado y las fuentes de datos para `HighwayView`/`ScopeView`.
public struct PracticeView: View {

    private let hud: PracticeHUD
    private let scratch: Scratch
    private let highwayGeometry: HighwayGeometry
    private let tick: () -> Double
    private let userTrace: () -> [TracePoint]
    private let clickHits: () -> [ClickHit]
    private let scopeReadings: () -> [ScopeReading]
    private let onExit: () -> Void
    private let onBPMChange: (Int) -> Void

    public init(hud: PracticeHUD, scratch: Scratch,
                highwayGeometry: HighwayGeometry,
                tick: @escaping () -> Double,
                userTrace: @escaping () -> [TracePoint] = { [] },
                clickHits: @escaping () -> [ClickHit] = { [] },
                scopeReadings: @escaping () -> [ScopeReading] = { [] },
                onExit: @escaping () -> Void = {},
                onBPMChange: @escaping (Int) -> Void = { _ in }) {
        self.hud = hud
        self.scratch = scratch
        self.highwayGeometry = highwayGeometry
        self.tick = tick
        self.userTrace = userTrace
        self.clickHits = clickHits
        self.scopeReadings = scopeReadings
        self.onExit = onExit
        self.onBPMChange = onBPMChange
    }

    public var body: some View {
        VStack(spacing: 0) {
            topBar
            HStack(spacing: 0) {
                ScopeView(geometry: ScopeGeometry(size: CGSize(width: 160, height: 160)),
                          readings: scopeReadings)
                    .frame(width: 180)
                    .padding(XFSpacing.sm)
                HighwayView(scratch: scratch, geometry: highwayGeometry,
                            tick: tick, userTrace: userTrace, clickHits: clickHits)
            }
            bottomBar
        }
        .background(XFColor.bg)
    }

    private var topBar: some View {
        HStack(spacing: XFSpacing.lg) {
            Button(action: onExit) { Image(systemName: "chevron.left") }.buttonStyle(.plain)
            Text(hud.exerciseName).font(XFFont.bodyMedium(14))
            Spacer()
            Text(hud.phaseLabel).foregroundColor(XFColor.textMuted)
            Text("\(hud.bpm) BPM").font(XFFont.mono(13)).foregroundColor(XFColor.accent)
            if let pct = hud.accuracyPercent {
                Text("\(pct)%").font(XFFont.mono(14))
            } else if hud.isCountingIn {
                Text("···").font(XFFont.mono(14)).foregroundColor(XFColor.textMuted)
            }
        }
        .padding(.horizontal, XFSpacing.md)
        .padding(.vertical, XFSpacing.xs)
        .background(XFColor.surface)
    }

    private var bottomBar: some View {
        HStack(spacing: XFSpacing.md) {
            HStack(spacing: 3) {
                ForEach(Array(hud.recentClicks.enumerated()), id: \.offset) { _, level in
                    Circle().fill(level.color).frame(width: 8, height: 8)
                }
            }
            if let feedback = hud.liveFeedback {
                Text(feedback).font(XFFont.body(13)).foregroundColor(XFColor.textMuted)
            }
            Spacer()
        }
        .padding(.horizontal, XFSpacing.md)
        .padding(.vertical, XFSpacing.xs)
        .background(XFColor.surface)
    }
}
