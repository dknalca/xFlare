// SPDX-License-Identifier: GPL-3.0-only

import SwiftUI
import AppKit
import XFDesign
import XFRender
import XFNotation
import XFCapture

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
    @State private var sensitivity: Double = 1.0
    // Amplitud del movimiento: a que fraccion del sample llega el pico del
    // patron. 2/3 por defecto; el principio siempre abajo (inicio del sample).
    @State private var amplitude: Double = AudioAsset.scratchPatternTopFraction
    // Desplazamiento manual de la rejilla respecto a la base (botones ◀/▶), ticks.
    @State private var gridShift: Double = 0
    // Ultima linea grabada, lista para exportar a .xfsession.
    @State private var lastRecording: XFSession?
    @State private var recSeconds: Double = 0   // contador visible mientras grabas
    @State private var meterPeak: Double = 0
    @State private var faderClosed = false
    @State private var metroOn: Bool
    // Nombre (sin extension) de la instrumental cargada, para el panel.
    @State private var instrName: String = "080bpm_beat"

    private let meterTick = Timer.publish(every: 0.05, on: .main, in: .common).autoconnect()

    private let scratch: Scratch
    private let exerciseName: String
    /// Modo **Freestyle**: sin fantasma ni "repite conmigo"; grabas una línea
    /// libre y la exportas / importas. El resto (plato, base, mixer) igual.
    private let freestyle: Bool
    private let geometry: HighwayGeometry
    private let engine: EngineHandle?
    private let content: ContentLoader
    private let metronomeOn: Bool
    private let onExit: () -> Void
    private let onMetronomeChanged: (Bool) -> Void

    public init(scratch: Scratch,
                exerciseName: String,
                bpm: Int,
                geometry: HighwayGeometry,
                freestyle: Bool = false,
                engine: EngineHandle? = nil,
                content: ContentLoader = RepoContentLoader(),
                metronomeOn: Bool = true,
                onMetronomeChanged: @escaping (Bool) -> Void = { _ in },
                onExit: @escaping () -> Void = {}) {
        self.scratch = scratch
        self.exerciseName = exerciseName
        self.freestyle = freestyle
        self.geometry = geometry
        self.engine = engine
        self.content = content
        self.metronomeOn = metronomeOn
        self.onMetronomeChanged = onMetronomeChanged
        self.onExit = onExit
        _metroOn = State(initialValue: metronomeOn)
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
                        // en "tu turno" del call & response el fantasma se atenua
                        ghostDimmed: s.crPhase == .respond,
                        showGhost: !freestyle,
                        // el slider "Amplitud" solo escala la onda fantasma; con
                        // amplitud 2/3 la escala es 1 (pico a 2/3), con 1.0 -> 1.5
                        // (pico arriba del todo). La traza del usuario no se toca.
                        patternAmplitude: CGFloat(amplitude),
                        gridShift: gridShift)
                    PlatterInputView(
                        onScroll: { s.scrollBy($0) },
                        onNudge: { s.nudge(forward: $0) },
                        onFaderClosed: { closed in
                            // solo avisa a la sesion; el gain lo pone el
                            // .onChange de session.faderClosed (asi tambien
                            // funciona cuando el fader lo mueve el fantasma).
                            s.setFaderClosed(closed)
                        },
                        onFreeze: {
                            // P: congela la imagen. La instrumental y el
                            // metronomo se paran con el transporte; el scratch
                            // del sample sigue vivo (la sesion no toca el motor).
                            s.toggleFreeze()
                            engine?.setTransport(bpm: Double(s.bpm), ppq: 480,
                                                 playing: !s.frozen)
                        },
                        onCue: {
                            // 1: cue 1 = vuelve al inicio del sample.
                            s.jumpToCue()
                            engine?.seekScratch(0)
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
        .onReceive(meterTick) { _ in
            meterPeak = engine?.outputPeak ?? 0
            recSeconds = session.recording ? session.recordedSeconds : 0
        }
        .onChange(of: session.faderClosed) { closed in
            faderClosed = closed
            // fader cerrado / mute = calla SOLO el scratch; la instrumental y el
            // metronomo siguen. Vale tanto si lo cierra el usuario (Espacio) como
            // si lo cierra el fantasma en la fase de escucha.
            engine?.setScratchGain(closed ? 0 : Float(sampleVol))
        }
        .onChange(of: session.recArming) { arming in
            // durante la claqueta el metronomo suena aunque el usuario lo tenga
            // apagado; al terminar (empieza a grabar o se cancela) se restablece.
            engine?.metronomeEnabled = arming ? true : metroOn
        }
        .onAppear { start() }
        .onDisappear { stop() }
    }

    // MARK: - panel derecho: medidor + volumenes (provisional)

    private var rightPanel: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: XFSpacing.md) {
                panelSection("Mezcla") {
                    clipMeter
                    volSlider("Sample", $sampleVol) { v in
                        if !faderClosed { engine?.setScratchGain(Float(v)) }
                    }
                    volSlider("Instru", $instruVol) { v in engine?.setInstrumentalGain(Float(v)) }
                }
                panelSection("Base") { instrumentalPicker }
                if !freestyle {
                    panelSection("Repite conmigo") { callResponsePanel }
                }
                panelSection("Grabar línea") { recordPanel }
                panelSection("Ajuste rápido") {
                    volSlider("Trackpad", $sensitivity, range: 0.1...1.5) { v in
                        session.scrollSensitivity = v
                    }
                    if !freestyle {
                        // "Amplitud" solo cambia el ALTO de la onda fantasma que
                        // hay que seguir; no toca el movimiento ni el sample.
                        volSlider("Amplitud", $amplitude, range: 0.3...1.0) { _ in }
                    }
                }
            }
            .padding(XFSpacing.sm)
        }
        .frame(width: 176)
        .background(XFColor.surface)
    }

    /// Un bloque con título del panel derecho.
    private func panelSection<C: View>(_ title: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: XFSpacing.xxs) {
            Text(title.uppercased())
                .font(XFFont.body(9)).kerning(0.6)
                .foregroundColor(XFColor.textMuted)
            VStack(spacing: XFSpacing.xs) { content() }
                .padding(XFSpacing.xs)
                .frame(maxWidth: .infinity)
                .background(RoundedRectangle(cornerRadius: XFRadius.control, style: .continuous)
                    .fill(XFColor.surfaceRaised))
        }
    }

    /// Botón "chip" (texto o icono) para el panel. Tamaño fijo y borde: no se
    /// aplasta y se ve que es pulsable.
    private func chip(_ label: String, icon: Bool = false, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Group {
                if icon { Image(systemName: label).font(.system(size: 11, weight: .bold)) }
                else { Text(label).font(XFFont.mono(11)) }
            }
            .frame(width: 30, height: 22)
            .background(RoundedRectangle(cornerRadius: 5).fill(XFColor.surface))
            .overlay(RoundedRectangle(cornerRadius: 5).stroke(XFColor.stroke, lineWidth: 1))
            .foregroundColor(XFColor.text)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .fixedSize()
    }

    /// "Repite conmigo": la máquina toca `n` compases con el fantasma moviendo el
    /// sample, luego los imitas de oído. `n` en múltiplos de 2. Botón ancho en
    /// una fila; los compases a imitar en otra.
    private var callResponsePanel: some View {
        VStack(spacing: XFSpacing.xs) {
            Button {
                session.setCallResponse(session.crPhase == .off)
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: session.crPhase == .off ? "play.fill" : "stop.fill")
                        .font(.system(size: 9))
                    Text(crShort).font(XFFont.bodyMedium(11))
                    Spacer(minLength: 0)
                }
                .foregroundColor(session.crPhase == .off ? XFColor.text : crColor)
                .padding(.vertical, 5).padding(.horizontal, XFSpacing.xs)
                .frame(maxWidth: .infinity)
                .background(RoundedRectangle(cornerRadius: 5)
                    .fill(session.crPhase == .off ? XFColor.surface : crColor.opacity(0.15)))
                .overlay(RoundedRectangle(cornerRadius: 5).stroke(XFColor.stroke, lineWidth: 1))
            }
            .buttonStyle(.plain)

            HStack(spacing: 5) {
                Text("Compases").font(XFFont.body(9)).foregroundColor(XFColor.textMuted)
                Spacer(minLength: 0)
                chip("−") { session.setCallResponseBars(session.crBars / 2) }
                    .disabled(session.crBars <= 2)
                Text("\(session.crBars)").font(XFFont.mono(11)).frame(width: 16)
                chip("+") { session.setCallResponseBars(session.crBars * 2) }
                    .disabled(session.crBars >= 16)
            }
        }
    }

    private var crShort: String {
        switch session.crPhase {
        case .off:     return "Empezar"
        case .listen:  return "Escucha…"
        case .respond: return "Tu turno"
        }
    }

    /// Cargar otra instrumental + su BPM + ajuste ×2 / ÷2 + fase de la rejilla.
    private var instrumentalPicker: some View {
        VStack(spacing: XFSpacing.xs) {
            Button(action: pickInstrumental) {
                HStack(spacing: 5) {
                    Image(systemName: "waveform")
                    Text(instrName).font(XFFont.body(10)).lineLimit(1).truncationMode(.middle)
                    Spacer()
                    Image(systemName: "folder").font(.system(size: 9)).foregroundColor(XFColor.textMuted)
                }
                .foregroundColor(XFColor.text)
            }
            .buttonStyle(.plain)

            HStack(spacing: 5) {
                Text("\(session.bpm) BPM").font(XFFont.mono(12)).foregroundColor(XFColor.accent)
                Spacer(minLength: 0)
                chip("÷2") { retempo(0.5) }
                chip("×2") { retempo(2.0) }
            }

            HStack(spacing: 5) {
                Text("Rejilla").font(XFFont.body(9)).foregroundColor(XFColor.textMuted)
                Spacer(minLength: 0)
                chip("chevron.left", icon: true) { gridShift += gridStep }
                chip("chevron.right", icon: true) { gridShift -= gridStep }
            }
        }
    }

    /// Paso de cada pulsación de ◀ / ▶ de rejilla: 1/8 de negra (~40 ms a 90 BPM,
    /// ~15 px en pantalla). Se acumula.
    private var gridStep: Double { Double(scratch.ppq) / 8 }

    /// ÷2 / ×2: corrige la **rejilla**, no la velocidad de la base. Si el tempo
    /// se detecto al doble (180 en un hiphop de 90), ÷2 deja la rejilla a 90 y
    /// la base se sigue oyendo natural: se reinstala con `nativeBPM = 90`, asi
    /// el ratio de reproduccion se queda en ~1.0. Vuelve a empezar desde el "1".
    /// Grabar una línea libre y exportarla / importarla (`.xfsession`).
    private var recordPanel: some View {
        let rec = session.recording
        let arming = session.recArming
        let active = rec || arming
        return VStack(spacing: XFSpacing.xs) {
            Button {
                if rec { lastRecording = session.stopRecording() }
                else if arming { session.stopRecording() }        // cancela la claqueta
                else { session.stopPlayback(); session.armRecording() }
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: rec ? "stop.fill" : (arming ? "metronome" : "record.circle"))
                        .font(.system(size: rec ? 9 : 11))
                    Text(rec ? String(format: "Parar · %.0fs", recSeconds)
                         : (arming ? "Claqueta…" : "Grabar"))
                        .font(XFFont.bodyMedium(11))
                    Spacer(minLength: 0)
                }
                .foregroundColor(active ? Color(hex: 0xFF4D5E) : XFColor.text)
                .padding(.vertical, 6).padding(.horizontal, XFSpacing.xs)
                .frame(maxWidth: .infinity)
                .background(RoundedRectangle(cornerRadius: 5)
                    .fill(active ? Color(hex: 0xFF4D5E).opacity(0.15) : XFColor.surface))
                .overlay(RoundedRectangle(cornerRadius: 5)
                    .stroke(active ? Color(hex: 0xFF4D5E) : XFColor.stroke, lineWidth: 1))
            }
            .buttonStyle(.plain)

            HStack(spacing: 5) {
                Button("Exportar…") { exportLine() }
                    .buttonStyle(.plain).font(XFFont.body(9))
                    .foregroundColor(lastRecording == nil ? XFColor.textMuted : XFColor.text)
                    .disabled(lastRecording == nil || active)
                Spacer(minLength: 0)
                Button("Importar…") { importLine() }
                    .buttonStyle(.plain).font(XFFont.body(9)).foregroundColor(XFColor.text)
                    .disabled(active)
            }

            if session.playingBack {
                Button {
                    session.stopPlayback()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "stop.fill").font(.system(size: 8))
                        Text("Parar reproducción").font(XFFont.body(9))
                        Spacer(minLength: 0)
                    }
                    .foregroundColor(XFColor.accent)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func exportLine() {
        guard let rec = lastRecording else { return }
        let panel = NSSavePanel()
        panel.allowedFileTypes = ["xfsession"]
        panel.nameFieldStringValue = "linea.xfsession"
        panel.prompt = "Exportar"
        if panel.runModal() == .OK, let url = panel.url {
            try? rec.encodedJSONLines().write(to: url, atomically: true, encoding: .utf8)
        }
    }

    private func importLine() {
        let panel = NSOpenPanel()
        panel.allowedFileTypes = ["xfsession"]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.prompt = "Importar"
        if panel.runModal() == .OK, let url = panel.url,
           let text = try? String(contentsOf: url, encoding: .utf8),
           let s = try? XFSession(jsonLines: text) {
            session.loadPlayback(s)
            // la linea arranca en la fase 0 de su bucle: la instrumental
            // tambien vuelve al principio y el reloj musical a 0, para que los
            // scratches caigan sobre los mismos golpes de la base.
            session.resyncClock()
            engine?.replayInstrumental(nativeBPM: Double(session.bpm))
            engine?.setTransport(bpm: Double(session.bpm), ppq: 480, playing: !session.frozen)
            gridShift = 0
        }
    }

    private func retempo(_ factor: Double) {
        session.setBPM(Int((Double(session.bpm) * factor).rounded()))
        engine?.replayInstrumental(nativeBPM: Double(session.bpm))
        engine?.setTransport(bpm: Double(session.bpm), ppq: 480, playing: !session.frozen)
        session.resyncClock()
        gridShift = 0
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

        // 1) el SAMPLE de scratch (fijo). 2) la instrumental (por defecto la del
        // asset; `loadInstrumental` arranca el reloj y la sesion al terminar).
        DispatchQueue.global(qos: .userInitiated).async {
            let scratchPCM = AudioAsset.loadMono(AudioAsset.scratchRelPath, from: content)
            let sampleW = scratchPCM.map {
                WaveformColored.build($0, sampleRate: sr, buckets: min($0.count / 48, 200_000))
            } ?? WaveformColored.Data(levels: [], colors: [])
            DispatchQueue.main.async {
                if let scratchPCM {
                    engine.loadSample(scratchPCM)
                    engine.seekScratch(0)
                }
                sampleWave = sampleW
                loadInstrumental(url: nil, initial: true)
            }
        }
    }

    /// Decodifica una instrumental (la del asset si `url == nil`, o la elegida
    /// por el usuario), le detecta el BPM y la fase del "1", **ajusta el tempo
    /// del ejercicio** a ese BPM y la deja sonando en bucle. En el arranque
    /// (`initial`) tambien pone en marcha la salida de audio y el reloj de la
    /// sesion (asi la practica empieza en tick 0, con el audio, sin arrancar a
    /// mitad de movimiento).
    private func loadInstrumental(url: URL?, initial: Bool) {
        guard let engine = engine else { return }
        let sr = engine.sampleRateHz
        let ppq = scratch.ppq
        let beatsPerBar = geometry.beatsPerBar
        let name = url?.lastPathComponent ?? AudioAsset.instrumentalRelPath
        instrName = url?.deletingPathExtension().lastPathComponent ?? "080bpm_beat"

        DispatchQueue.global(qos: .userInitiated).async {
            let raw = url.flatMap { AudioAsset.loadMono($0, sampleRate: sr) }
                ?? AudioAsset.loadMono(AudioAsset.instrumentalRelPath, from: content)

            var pcmOut = raw
            var bpm = AudioAsset.instrumentalNativeBPM
            var loopTicks = Double(beatsPerBar * ppq)
            let hint = TempoAnalyzer.bpmHint(fromFilename: name)
            if let pcm = raw {
                if let a = TempoAnalyzer.analyze(pcm, sampleRate: sr, hintBPM: hint) {
                    bpm = a.bpm
                    let phi = ((a.phaseFrames % pcm.count) + pcm.count) % pcm.count
                    pcmOut = phi == 0 ? pcm : Array(pcm[phi...]) + Array(pcm[..<phi])
                    loopTicks = a.isShortLoop
                        ? Double(a.beats) * Double(ppq)
                        : (Double(pcm.count) / sr) * (a.bpm / 60.0) * Double(ppq)
                } else {
                    let beats = Double(pcm.count) / sr * (bpm / 60.0)
                    let bars = max(1.0, (beats / Double(beatsPerBar)).rounded())
                    loopTicks = bars * Double(beatsPerBar) * Double(ppq)
                }
            }
            let wave = pcmOut.map {
                WaveformColored.build($0, sampleRate: sr, buckets: min($0.count / 64, 300_000))
            } ?? WaveformColored.Data(levels: [], colors: [])
            let bpmRounded = Int(bpm.rounded())

            DispatchQueue.main.async {
                if let pcmOut { engine.loadInstrumental(pcmOut, nativeBPM: bpm) }
                instrWave = wave
                instrLoopTicks = loopTicks
                // la sesion necesita la longitud del bucle para cuadrar las
                // tomas grabadas a un multiplo entero de el.
                session.setInstrumentalLoopTicks(loopTicks)
                // el tempo del EJERCICIO pasa a ser el de esta instrumental
                session.setBPM(bpmRounded)
                session.resyncClock()
                engine.setTransport(bpm: Double(session.bpm), ppq: 480, playing: true)
                if initial {
                    _ = engine.startOutput()
                    session.start()
                }
            }
        }
    }

    /// Abre un selector de fichero y carga esa instrumental (ajusta el BPM).
    private func pickInstrumental() {
        let panel = NSOpenPanel()
        panel.allowedFileTypes = ["wav", "aif", "aiff", "caf", "mp3", "m4a", "aac"]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.prompt = "Cargar"
        if panel.runModal() == .OK, let url = panel.url {
            gridShift = 0
            loadInstrumental(url: url, initial: false)
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
            XFWordmark(size: 14)
            Divider().frame(height: 16).background(XFColor.stroke)
            Text(exerciseName).font(XFFont.bodyMedium(14))
            if session.frozen {
                Text("CONGELADO")
                    .font(XFFont.mono(10))
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(XFColor.accent.opacity(0.18))
                    .foregroundColor(XFColor.accent)
                    .cornerRadius(3)
            }
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
                 + "Espacio: fader cerrado   ·   P: congelar   ·   1: cue   ·   ↑ ↓: BPM   ·   Esc: salir")
                .font(XFFont.body(12)).foregroundColor(XFColor.textMuted)
            Spacer()
        }
        .padding(.horizontal, XFSpacing.md)
        .padding(.vertical, XFSpacing.xs)
        .background(XFColor.surface)
    }
}
