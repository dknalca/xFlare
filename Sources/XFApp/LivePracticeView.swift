// SPDX-License-Identifier: GPL-3.0-only

import SwiftUI
import XFDesign
import XFRender
import XFNotation

/// Pantalla de practica **rudimentaria**: la autopista corre con el reloj de
/// `PracticeSession` y el trackpad / teclado mueven el plato. Con audio: el
/// scratch suena al mover (via `EngineHandle`) y una base instrumental corre
/// pegada al tempo. Todavia **sin scoring** (necesita el callback de audio con
/// captura, B4.2): sirve para practicar el gesto antes de tener la mesa.
///
/// Cuando exista el bucle de sesion de verdad, esta vista se sustituye por
/// `PracticeView` cableada a `XFEngine` + `XFAnalysis`.
public struct LivePracticeView: View {

    @StateObject private var session: PracticeSession
    @State private var waveEnvelope: [Float] = []

    private let scratch: Scratch
    private let exerciseName: String
    private let geometry: HighwayGeometry
    private let engine: EngineHandle?
    private let content: ContentLoader
    private let metronomeOn: Bool
    private let onExit: () -> Void

    public init(scratch: Scratch,
                exerciseName: String,
                bpm: Int,
                geometry: HighwayGeometry,
                engine: EngineHandle? = nil,
                content: ContentLoader = RepoContentLoader(),
                metronomeOn: Bool = true,
                onExit: @escaping () -> Void = {}) {
        self.scratch = scratch
        self.exerciseName = exerciseName
        self.geometry = geometry
        self.engine = engine
        self.content = content
        self.metronomeOn = metronomeOn
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
                // fader cerrado = no suena -> la autopista se oscurece
                Rectangle()
                    .fill(Color.black)
                    .opacity(session.faderClosed ? 0.5 : 0)
                    .animation(.easeOut(duration: 0.06), value: session.faderClosed)
                    .allowsHitTesting(false)
                PlatterInputView(
                    onScroll: { s.scrollBy($0) },
                    onNudge: { s.nudge(forward: $0) },
                    onFaderClosed: { closed in
                        s.setFaderClosed(closed)
                        // fader cerrado = corta el sonido del scratch
                        engine?.setMasterGain(closed ? 0 : 1)
                    },
                    onBPM: { bpm in
                        s.setBPM(bpm)
                        engine?.setTransport(bpm: Double(s.bpm), ppq: 480, playing: true)
                    },
                    currentBPM: { s.bpm },
                    onExit: onExit)
            }
            waveStrip
            hintBar
        }
        .background(XFColor.bg)
        .foregroundColor(XFColor.text)
        .onAppear { start() }
        .onDisappear { stop() }
    }

    // MARK: - audio + reloj

    private func start() {
        session.start()
        guard let engine = engine else { return }

        engine.metronomeEnabled = metronomeOn
        engine.setInstrumentalGain(0.5)
        engine.setMasterGain(1)
        engine.setTransport(bpm: Double(session.bpm), ppq: 480, playing: true)

        // cada paso del reloj empuja la velocidad del plato al reproductor
        session.onAdvance = { [weak engine] platterVelocity, _ in
            let v = max(-8.0, min(8.0, platterVelocity * 1.6))
            engine?.setVelocity(v)
        }

        // decodificar los audios fuera del hilo principal (el MP3 tarda)
        DispatchQueue.global(qos: .userInitiated).async {
            let scratchPCM = AudioAsset.loadMono(AudioAsset.scratchRelPath, from: content)
            let instrPCM   = AudioAsset.loadMono(AudioAsset.instrumentalRelPath, from: content)
            let env = scratchPCM.map { WaveformEnvelope.build($0) } ?? []
            DispatchQueue.main.async {
                if let scratchPCM { engine.loadSample(scratchPCM) }
                if let instrPCM {
                    engine.loadInstrumental(instrPCM, nativeBPM: AudioAsset.instrumentalNativeBPM)
                }
                waveEnvelope = env
                _ = engine.startOutput()
            }
        }
    }

    private var waveStrip: some View {
        WaveformStripView(envelope: waveEnvelope,
                          progress: { engine?.scratchProgress ?? 0 })
            .frame(height: 54)
            .background(XFColor.surface)
    }

    private func stop() {
        session.onAdvance = nil
        session.stop()
        engine?.stop()
        engine?.clearSample()
        engine?.clearInstrumental()
    }

    // MARK: - chrome

    private var topBar: some View {
        HStack(spacing: XFSpacing.lg) {
            Button(action: onExit) { Image(systemName: "chevron.left") }
                .buttonStyle(.plain)
            Text(exerciseName).font(XFFont.bodyMedium(14))
            Spacer()
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
