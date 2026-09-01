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
    @State private var sampleVol: Double
    @State private var instruVol: Double
    @State private var meterPeak: Double = 0
    @State private var faderClosed = false

    private let meterTick = Timer.publish(every: 0.05, on: .main, in: .common).autoconnect()

    private let scratch: Scratch
    private let exerciseName: String
    private let geometry: HighwayGeometry
    private let engine: EngineHandle?
    private let content: ContentLoader
    private let metronomeOn: Bool
    private let onExit: () -> Void
    private let onVolumesChanged: (_ sample: Double, _ instrumental: Double) -> Void

    public init(scratch: Scratch,
                exerciseName: String,
                bpm: Int,
                geometry: HighwayGeometry,
                engine: EngineHandle? = nil,
                content: ContentLoader = RepoContentLoader(),
                metronomeOn: Bool = true,
                sampleVolume: Double = 1.0,
                instrumentalVolume: Double = 0.3,
                onVolumesChanged: @escaping (Double, Double) -> Void = { _, _ in },
                onExit: @escaping () -> Void = {}) {
        self.scratch = scratch
        self.exerciseName = exerciseName
        self.geometry = geometry
        self.engine = engine
        self.content = content
        self.metronomeOn = metronomeOn
        self.onVolumesChanged = onVolumesChanged
        self.onExit = onExit
        _sampleVol = State(initialValue: sampleVolume)
        _instruVol = State(initialValue: instrumentalVolume)
        // Arranca al tempo de la instrumental para que suene coherente desde el
        // primer compas (el `bpm` del ejercicio manda cuando se cambie a mano).
        _ = bpm
        _session = StateObject(wrappedValue: PracticeSession(
            scratch: scratch, bpm: Int(AudioAsset.instrumentalNativeBPM)))
    }

    public var body: some View {
        let s = session
        return VStack(spacing: 0) {
            topBar
            HStack(spacing: 0) {
                ZStack {
                    HighwayView(scratch: scratch, geometry: geometry,
                                tick: { s.tick() },
                                userTrace: { s.trace() })
                    PlatterInputView(
                        onScroll: { s.scrollBy($0) },
                        onNudge: { s.nudge(forward: $0) },
                        onFaderClosed: { closed in
                            faderClosed = closed
                            s.setFaderClosed(closed)
                            // fader cerrado / mute = calla SOLO el scratch; la
                            // instrumental (y el metronomo) siguen sonando.
                            engine?.setScratchGain(closed ? 0 : Float(sampleVol))
                        },
                        onBPM: { bpm in
                            s.setBPM(bpm)
                            engine?.setTransport(bpm: Double(s.bpm), ppq: 480, playing: true)
                        },
                        currentBPM: { s.bpm },
                        onExit: onExit)
                }
                rightPanel
            }
            waveStrip
            hintBar
        }
        .background(XFColor.bg)
        .foregroundColor(XFColor.text)
        .onReceive(meterTick) { _ in meterPeak = engine?.outputPeak ?? 0 }
        .onAppear { start() }
        .onDisappear { stop() }
    }

    // MARK: - panel derecho: medidor + volumenes (provisional)

    private var rightPanel: some View {
        VStack(spacing: XFSpacing.sm) {
            clipMeter
            volSlider("Sample", $sampleVol) { v in
                if !faderClosed { engine?.setScratchGain(Float(v)) }
                onVolumesChanged(v, instruVol)
            }
            volSlider("Instru", $instruVol) { v in
                engine?.setInstrumentalGain(Float(v))
                onVolumesChanged(sampleVol, v)
            }
        }
        .frame(width: 92)
        .padding(XFSpacing.sm)
        .background(XFColor.surface)
    }

    private var clipMeter: some View {
        let clip = meterPeak >= 1.0
        return VStack(spacing: 2) {
            GeometryReader { geo in
                let h = geo.size.height
                let level = CGFloat(min(1.2, meterPeak)) / 1.2
                ZStack(alignment: .bottom) {
                    RoundedRectangle(cornerRadius: 2).fill(XFColor.bg)
                    RoundedRectangle(cornerRadius: 2)
                        .fill(clip ? Color(hex: 0xFF4D5E)
                              : meterPeak > 0.8 ? Color(hex: 0xF5C542) : XFColor.accent)
                        .frame(height: max(1, h * level))
                }
            }
            .frame(height: 70)
            Text(clip ? "CLIP" : "\(Int(meterPeak * 100))")
                .font(XFFont.mono(9))
                .foregroundColor(clip ? Color(hex: 0xFF4D5E) : XFColor.textMuted)
        }
    }

    private func volSlider(_ label: String, _ value: Binding<Double>,
                           _ apply: @escaping (Double) -> Void) -> some View {
        VStack(spacing: 1) {
            HStack {
                Text(label).font(XFFont.body(10)).foregroundColor(XFColor.textMuted)
                Spacer()
                Text("\(Int(value.wrappedValue * 100))").font(XFFont.mono(9))
                    .foregroundColor(XFColor.textMuted)
            }
            Slider(value: Binding(get: { value.wrappedValue },
                                  set: { value.wrappedValue = $0; apply($0) }),
                   in: 0...1)
                .controlSize(.mini)
        }
    }

    // MARK: - audio + reloj

    private func start() {
        session.start()
        guard let engine = engine else { return }

        engine.metronomeEnabled = metronomeOn
        engine.setInstrumentalGain(Float(instruVol))
        engine.setMasterGain(0.85)
        engine.setScratchGain(faderClosed ? 0 : Float(sampleVol))
        engine.setTransport(bpm: Double(session.bpm), ppq: 480, playing: true)

        // cada paso del reloj: solo se manda la VELOCIDAD (derivada exacta del
        // movimiento del cabezal en fraccion util del sample). NO se hace
        // `seekScratch` por fotograma: escribir el cabezal desde el hilo normal
        // mientras el RT lo integra es una carrera y metia un click periodico.
        // El cabezal lo integra el RT a partir de la velocidad; la onda de abajo
        // lee ese mismo cabezal, asi que van juntas.
        let sr = engine.sampleRateHz
        session.onAdvance = { [weak engine] normVel, _, _ in
            guard let engine = engine, engine.scratchFrameCount > 1 else { return }
            let usable = Double(engine.scratchFrameCount - 1) * AudioAsset.scratchUsableFraction
            engine.setVelocity(normVel * usable / sr)   // frames de sample por frame de salida
        }

        // decodificar los audios fuera del hilo principal (el MP3 tarda)
        DispatchQueue.global(qos: .userInitiated).async {
            let scratchPCM = AudioAsset.loadMono(AudioAsset.scratchRelPath, from: content)
            let instrPCM   = AudioAsset.loadMono(AudioAsset.instrumentalRelPath, from: content)
            let env = scratchPCM.map { WaveformEnvelope.build($0) } ?? []
            DispatchQueue.main.async {
                if let scratchPCM {
                    engine.loadSample(scratchPCM)
                    engine.seekScratch(0)          // el sample arranca desde el principio
                }
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
                          progress: { engine?.scratchProgress ?? 0 },
                          visibleFraction: 0.9)
            .frame(height: 54)
            .background(XFColor.surface)
    }

    private func stop() {
        session.onAdvance = nil
        session.stop()
        engine?.setScratchGain(1)   // por si se salio con el fader cerrado
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
