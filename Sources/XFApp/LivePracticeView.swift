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
    @State private var sampleWave = WaveformColored.Data(levels: [], colors: [])
    // Onda de la instrumental (tira superior) + longitud musical de su bucle.
    @State private var instrWave = WaveformColored.Data(levels: [], colors: [])
    @State private var instrLoopTicks: Double = 0
    // Volumenes por sesion (no se persisten: asi la practica nunca arranca muda).
    // Ambos arrancan a la mitad: el sample a tope tapaba la instrumental.
    @State private var sampleVol: Double = 0.5
    @State private var instruVol: Double = 0.5
    // Sensibilidad del trackpad, PROVISIONAL: a ojo el gesto va rapido.
    @State private var sensitivity: Double = 0.5
    // Buffer de audio en caliente: al cambiarlo se reabre el motor solo.
    @State private var bufferSel: Int
    @State private var restarting = false
    @State private var meterPeak: Double = 0
    @State private var faderClosed = false
    @State private var metroOn: Bool

    private let meterTick = Timer.publish(every: 0.05, on: .main, in: .common).autoconnect()

    private let scratch: Scratch
    private let exerciseName: String
    private let geometry: HighwayGeometry
    private let engine: EngineHandle?
    private let content: ContentLoader
    private let metronomeOn: Bool
    private let bufferOptions: [Int]
    private let onExit: () -> Void
    private let onMetronomeChanged: (Bool) -> Void
    private let onBufferChanged: (Int) -> Void

    public init(scratch: Scratch,
                exerciseName: String,
                bpm: Int,
                geometry: HighwayGeometry,
                engine: EngineHandle? = nil,
                content: ContentLoader = RepoContentLoader(),
                metronomeOn: Bool = true,
                bufferFrames: Int = 512,
                bufferOptions: [Int] = [64, 128, 256, 512, 1024, 2048],
                onMetronomeChanged: @escaping (Bool) -> Void = { _ in },
                onBufferChanged: @escaping (Int) -> Void = { _ in },
                onExit: @escaping () -> Void = {}) {
        self.scratch = scratch
        self.exerciseName = exerciseName
        self.geometry = geometry
        self.engine = engine
        self.content = content
        self.metronomeOn = metronomeOn
        self.bufferOptions = bufferOptions
        self.onMetronomeChanged = onMetronomeChanged
        self.onBufferChanged = onBufferChanged
        self.onExit = onExit
        _metroOn = State(initialValue: metronomeOn)
        _bufferSel = State(initialValue: bufferFrames)
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
                // UNA sola visualizacion: la autopista, la onda de la
                // instrumental (banda superior) y la del sample (rail izquierdo
                // vertical) se pintan en la misma escena y el mismo reloj de
                // fotograma, asi la rejilla de compas no se puede desfasar.
                ZStack {
                    PracticeSceneView(
                        scratch: scratch,
                        geometry: geometry,
                        tick: { s.tick() },
                        trace: { s.trace() },
                        instrumentalWave: instrWave,
                        instrumentalLoopTicks: instrLoopTicks,
                        sampleWave: sampleWave,
                        sampleProgress: { engine?.scratchProgress ?? 0 },
                        // en "tu turno" del call & response el fantasma se atenua
                        ghostDimmed: s.crPhase == .respond)
                    PlatterInputView(
                        onScroll: { s.scrollBy($0) },
                        onNudge: { s.nudge(forward: $0) },
                        onFaderClosed: { closed in
                            // solo avisa a la sesion; el gain lo pone el
                            // .onChange de session.faderClosed (asi tambien
                            // funciona cuando el fader lo mueve el fantasma).
                            s.setFaderClosed(closed)
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
            hintBar
        }
        .background(XFColor.bg)
        .foregroundColor(XFColor.text)
        .onReceive(meterTick) { _ in meterPeak = engine?.outputPeak ?? 0 }
        .onChange(of: session.faderClosed) { closed in
            faderClosed = closed
            // fader cerrado / mute = calla SOLO el scratch; la instrumental y el
            // metronomo siguen. Vale tanto si lo cierra el usuario (Espacio) como
            // si lo cierra el fantasma en la fase de escucha.
            engine?.setScratchGain(closed ? 0 : Float(sampleVol))
        }
        .onAppear { start() }
        .onDisappear { stop() }
    }

    // MARK: - panel derecho: medidor + volumenes (provisional)

    private var rightPanel: some View {
        VStack(spacing: XFSpacing.sm) {
            clipMeter
            volSlider("Sample", $sampleVol) { v in
                if !faderClosed { engine?.setScratchGain(Float(v)) }
            }
            volSlider("Instru", $instruVol) { v in
                engine?.setInstrumentalGain(Float(v))
            }
            volSlider("Trackpad", $sensitivity, range: 0.1...1.5) { v in
                session.scrollSensitivity = v
            }
            bufferControl
            Divider().background(XFColor.stroke)
            callResponsePanel
        }
        .frame(width: 108)
        .padding(XFSpacing.sm)
        .background(XFColor.surface)
    }

    /// Llamada y respuesta: la máquina toca `n` compases con el fantasma
    /// moviendo el sample, luego los imitas de oído. `n` en múltiplos de 2.
    private var callResponsePanel: some View {
        VStack(spacing: 3) {
            Button {
                session.setCallResponse(session.crPhase == .off)
            } label: {
                HStack(spacing: XFSpacing.xs) {
                    Image(systemName: session.crPhase == .off
                          ? "questionmark.circle" : "questionmark.circle.fill")
                    Text(crLabel).font(XFFont.body(10))
                }
                .foregroundColor(crColor)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)

            HStack(spacing: 4) {
                Text("Compases").font(XFFont.body(10)).foregroundColor(XFColor.textMuted)
                Spacer()
                Button { session.setCallResponseBars(session.crBars / 2) } label: { Text("−") }
                    .buttonStyle(.plain).disabled(session.crBars <= 2)
                Text("\(session.crBars)").font(XFFont.mono(11)).frame(width: 16)
                Button { session.setCallResponseBars(session.crBars * 2) } label: { Text("+") }
                    .buttonStyle(.plain).disabled(session.crBars >= 16)
            }
            .foregroundColor(XFColor.text)
        }
    }

    /// Cambia el buffer de audio en caliente: reabre el motor solo (sin
    /// reiniciar la app) para poder ver si el tamano de buffer es lo que hace
    /// que el sonido crepite. PROVISIONAL, panel de pruebas.
    private var bufferControl: some View {
        VStack(spacing: 2) {
            HStack {
                Text("Buffer").font(XFFont.body(10)).foregroundColor(XFColor.textMuted)
                Spacer()
                if restarting {
                    Text("…").font(XFFont.mono(9)).foregroundColor(XFColor.textMuted)
                }
            }
            Picker("", selection: $bufferSel) {
                ForEach(bufferOptions, id: \.self) { Text("\($0)").tag($0) }
            }
            .labelsHidden()
            .controlSize(.mini)
            .disabled(restarting)
            .onChange(of: bufferSel) { newVal in
                guard let engine = engine, newVal != engine.currentMaxFrames else { return }
                restarting = true
                // se aplaza un tick para que el spinner pinte antes del reinicio
                // (parar + recrear + recargar bloquea unas decenas de ms)
                DispatchQueue.main.async {
                    engine.restartOutput(maxFrames: newVal)
                    applyEngineParams()
                    let applied = engine.currentMaxFrames
                    onBufferChanged(applied)
                    if applied != newVal { bufferSel = applied }   // el motor no acepto el pedido
                    restarting = false
                }
            }
        }
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
                           range: ClosedRange<Double> = 0...1,
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
                   in: range)
                .controlSize(.mini)
        }
    }

    // MARK: - audio + reloj

    /// Ganancias + transporte + metronomo. Se llama al arrancar y despues de
    /// reabrir el motor con otro buffer (el motor nuevo nace sin estos ajustes).
    private func applyEngineParams() {
        guard let engine = engine else { return }
        engine.metronomeEnabled = metroOn
        engine.setInstrumentalGain(Float(instruVol))
        engine.setMasterGain(0.85)
        engine.setScratchGain(faderClosed ? 0 : Float(sampleVol))
        engine.setTransport(bpm: Double(session.bpm), ppq: 480, playing: true)
    }

    private func start() {
        session.scrollSensitivity = sensitivity
        guard let engine = engine else { session.start(); return }

        applyEngineParams()

        // cada paso del reloj: se manda la velocidad (driver del cabezal) Y el
        // objetivo de posicion como ancla anti-deriva (trim acotado en el motor,
        // <=1.5% de pitch: no se oye). Asi la onda de abajo no se separa de la
        // autopista a la larga sin meter barridos de pitch.
        let sr = engine.sampleRateHz
        session.onAdvance = { [weak engine] normVel, normPos, _ in
            guard let engine = engine, engine.scratchFrameCount > 1 else { return }
            // normPos / normVel ya estan normalizados al SAMPLE ENTERO (el pico
            // del patron cae en 2/3; el plato puede llegar hasta 1 = final).
            let full = Double(engine.scratchFrameCount - 1)
            engine.setVelocity(normVel * full / sr)
            engine.setScratchTarget(normPos * full)
        }

        // decodificar los audios fuera del hilo principal (el MP3 tarda)
        let ppq = scratch.ppq
        let beatsPerBar = geometry.beatsPerBar
        DispatchQueue.global(qos: .userInitiated).async {
            let scratchPCM = AudioAsset.loadMono(AudioAsset.scratchRelPath, from: content)
            let rawInstr   = AudioAsset.loadMono(AudioAsset.instrumentalRelPath, from: content)
            let sampleW = scratchPCM.map {
                WaveformColored.build($0, sampleRate: sr, buckets: min($0.count / 48, 200_000))
            } ?? WaveformColored.Data(levels: [], colors: [])

            // Analiza la instrumental: tempo real + fase del primer golpe. Si
            // sale, se ROTA el PCM para que empiece en el "1" y se usa ese BPM;
            // así la rejilla cae sobre los golpes de verdad. Si no, 80 BPM y
            // longitud redondeada a compás (como antes).
            var instrPCM = rawInstr
            var instrBPM = AudioAsset.instrumentalNativeBPM
            var loopTicks = Double(beatsPerBar * ppq)
            // si el nombre del fichero trae el BPM (080bpm_beat.wav), fiarse de
            // el y usar el analizador solo para la fase del "1".
            let hint = TempoAnalyzer.bpmHint(fromFilename: AudioAsset.instrumentalRelPath)
            if let pcm = rawInstr {
                if let a = TempoAnalyzer.analyze(pcm, sampleRate: sr, hintBPM: hint) {
                    instrBPM = a.bpm
                    let phi = ((a.phaseFrames % pcm.count) + pcm.count) % pcm.count
                    instrPCM = phi == 0 ? pcm : Array(pcm[phi...]) + Array(pcm[..<phi])
                    // unidad de bucle para la tira: si es un loop corto, sus
                    // negras; si es una pista larga, su longitud musical entera.
                    loopTicks = a.isShortLoop
                        ? Double(a.beats) * Double(ppq)
                        : (Double(pcm.count) / sr) * (a.bpm / 60.0) * Double(ppq)
                } else {
                    let beats = Double(pcm.count) / sr * (instrBPM / 60.0)
                    let bars = max(1.0, (beats / Double(beatsPerBar)).rounded())
                    loopTicks = bars * Double(beatsPerBar) * Double(ppq)
                }
            }
            let instrW = instrPCM.map {
                WaveformColored.build($0, sampleRate: sr, buckets: min($0.count / 64, 300_000))
            } ?? WaveformColored.Data(levels: [], colors: [])
            let bpmRounded = Int(instrBPM.rounded())

            DispatchQueue.main.async {
                if let scratchPCM {
                    engine.loadSample(scratchPCM)
                    engine.seekScratch(0)          // el sample arranca desde el principio
                }
                if let instrPCM {
                    engine.loadInstrumental(instrPCM, nativeBPM: instrBPM)
                }
                sampleWave = sampleW
                instrWave = instrW
                instrLoopTicks = loopTicks
                // el tempo de la sesion pasa a ser el de la cancion, y el reloj
                // ARRANCA aqui (no antes): asi la practica empieza en tick 0
                // -patron desde abajo- justo cuando suena el audio, sin el medio
                // segundo de scroll "a mitad de movimiento" mientras decodifica.
                session.setBPM(bpmRounded)
                session.resyncClock()
                engine.setTransport(bpm: Double(session.bpm), ppq: 480, playing: true)
                _ = engine.startOutput()
                session.start()
            }
        }
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
            Button {
                metroOn.toggle()
                engine?.metronomeEnabled = metroOn
                onMetronomeChanged(metroOn)
            } label: {
                HStack(spacing: XFSpacing.xs) {
                    Circle().fill(metroOn ? XFColor.accent : XFColor.textMuted)
                        .frame(width: 8, height: 8)
                    Text("Metrónomo").font(XFFont.body(11))
                }
                .foregroundColor(metroOn ? XFColor.text : XFColor.textMuted)
            }
            .buttonStyle(.plain)

            Text("\(session.bpm) BPM").font(XFFont.mono(13)).foregroundColor(XFColor.accent)
        }
        .padding(.horizontal, XFSpacing.md)
        .padding(.vertical, XFSpacing.xs)
        .background(XFColor.surface)
    }

    private var crLabel: String {
        switch session.crPhase {
        case .off:     return "Llamada y respuesta"
        case .listen:  return "Escucha…"
        case .respond: return "Tu turno"
        }
    }
    private var crColor: Color {
        switch session.crPhase {
        case .off:     return XFColor.textMuted
        case .listen:  return XFColor.accent
        case .respond: return XFColor.text
        }
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
