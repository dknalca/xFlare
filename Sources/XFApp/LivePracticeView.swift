// SPDX-License-Identifier: GPL-3.0-only

import SwiftUI
import XFDesign
import XFRender
import XFNotation

/// Pantalla de practica **rudimentaria**: la autopista corre con el reloj de
/// `PracticeSession` y el trackpad / teclado mueven el plato. Todavia **sin
/// scoring** (necesita el callback de audio, B4.2): sirve para ver el movimiento
/// y probar la entrada antes de tener la mesa.
///
/// Cuando exista el bucle de sesion de verdad, esta vista se sustituye por
/// `PracticeView` cableada a `XFEngine` + `XFAnalysis`.
public struct LivePracticeView: View {

    @StateObject private var session: PracticeSession

    private let scratch: Scratch
    private let exerciseName: String
    private let geometry: HighwayGeometry
    private let onExit: () -> Void

    public init(scratch: Scratch,
                exerciseName: String,
                bpm: Int,
                geometry: HighwayGeometry,
                onExit: @escaping () -> Void = {}) {
        self.scratch = scratch
        self.exerciseName = exerciseName
        self.geometry = geometry
        self.onExit = onExit
        _session = StateObject(wrappedValue: PracticeSession(scratch: scratch, bpm: bpm))
    }

    public var body: some View {
        let s = session
        return VStack(spacing: 0) {
            topBar
            ZStack {
                HighwayView(scratch: scratch, geometry: geometry,
                            tick: { s.tick() },
                            userTrace: { s.trace() })
                // capa de entrada por encima: la autopista no tiene controles
                PlatterInputView(
                    onScroll: { s.scrollBy($0) },
                    onNudge: { s.nudge(forward: $0) },
                    onFaderClosed: { s.setFaderClosed($0) },
                    onBPM: { s.setBPM($0) },
                    currentBPM: { s.bpm },
                    onExit: onExit)
            }
            hintBar
        }
        .background(XFColor.bg)
        .foregroundColor(XFColor.text)
        .onAppear { s.start() }
        .onDisappear { s.stop() }
    }

    private var topBar: some View {
        HStack(spacing: XFSpacing.lg) {
            Button(action: onExit) { Image(systemName: "chevron.left") }
                .buttonStyle(.plain)
            Text(exerciseName).font(XFFont.bodyMedium(14))
            Spacer()
            // indicador de crossfader
            HStack(spacing: XFSpacing.xs) {
                Circle()
                    .fill(session.faderClosed ? XFColor.textMuted : XFColor.accent)
                    .frame(width: 8, height: 8)
                Text(session.faderClosed ? "fader cerrado" : "fader abierto")
                    .font(XFFont.body(11)).foregroundColor(XFColor.textMuted)
            }
            Text("\(session.bpm) BPM").font(XFFont.mono(13)).foregroundColor(XFColor.accent)
        }
        .padding(.horizontal, XFSpacing.md)
        .padding(.vertical, XFSpacing.xs)
        .background(XFColor.surface)
    }

    private var hintBar: some View {
        HStack(spacing: XFSpacing.md) {
            Text("Trackpad: gira el plato   ·   A / D: atrás / adelante   ·   "
                 + "Espacio: fader cerrado   ·   ↑ ↓: BPM   ·   Esc: salir")
                .font(XFFont.body(12)).foregroundColor(XFColor.textMuted)
            Spacer()
        }
        .padding(.horizontal, XFSpacing.md)
        .padding(.vertical, XFSpacing.xs)
        .background(XFColor.surface)
    }
}
