// SPDX-License-Identifier: GPL-3.0-only

import SwiftUI
import XFDesign
import XFRender
import XFNotation

/// Modo libre (`docs/UI_DESIGN.md` §3.5): sin fantasma ni puntuación, metrónomo
/// opcional, grabación siempre activa de los últimos 30 s.
public struct FreeModeView: View {

    private let scratch: Scratch
    private let highwayGeometry: HighwayGeometry
    private let tick: () -> Double
    private let userTrace: () -> [TracePoint]
    private let scopeReadings: () -> [ScopeReading]
    private let recordedSeconds: Double
    private let onSave: () -> Void
    private let onExit: () -> Void

    public init(scratch: Scratch, highwayGeometry: HighwayGeometry,
                tick: @escaping () -> Double,
                userTrace: @escaping () -> [TracePoint] = { [] },
                scopeReadings: @escaping () -> [ScopeReading] = { [] },
                recordedSeconds: Double = 0,
                onSave: @escaping () -> Void = {},
                onExit: @escaping () -> Void = {}) {
        self.scratch = scratch
        self.highwayGeometry = highwayGeometry
        self.tick = tick
        self.userTrace = userTrace
        self.scopeReadings = scopeReadings
        self.recordedSeconds = recordedSeconds
        self.onSave = onSave
        self.onExit = onExit
    }

    public var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: XFSpacing.md) {
                Button(action: onExit) { Image(systemName: "chevron.left") }.buttonStyle(.plain)
                Circle().fill(Color(hex: 0xFF4D5E)).frame(width: 8, height: 8)
                Text("Grabando · últimos 30 s").foregroundColor(XFColor.textMuted).font(XFFont.body(12))
                Spacer()
                Text(String(format: "%.0f s", recordedSeconds)).font(XFFont.mono(12))
                Button("Guardar los 30 s", action: onSave).xfButton(.filled)
            }
            .padding(.horizontal, XFSpacing.md).padding(.vertical, XFSpacing.xs)
            .background(XFColor.surface)

            HStack(spacing: 0) {
                ScopeView(geometry: ScopeGeometry(size: CGSize(width: 160, height: 160)),
                          readings: scopeReadings)
                    .frame(width: 180).padding(XFSpacing.sm)
                // sin capa fantasma: solo la del usuario
                HighwayView(scratch: scratch, geometry: highwayGeometry,
                            tick: tick, userTrace: userTrace)
            }
        }
        .background(XFColor.bg)
    }
}
