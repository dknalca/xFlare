// SPDX-License-Identifier: GPL-3.0-only

import SwiftUI
import AppKit
import Combine
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
    // Nombre del sample de scratch cargado (por defecto el asset del autor).
    @State private var sampleName: String = "Ahh"
    // F.4: exportación de vídeo en curso y su progreso (0…1).
    @State private var exportingVideo = false
    @State private var videoProgress: Double = 0
    // Pantalla de carga (logo + cita) mientras decodifica sample + instrumental.
    @State private var loading = true
    @State private var quote = ""
    // Tamaño real de la autopista en pantalla, para exportar el vídeo con la
    // misma proporción que la ventana (lo reporta `PracticeScene`).
    @State private var highwaySize: CGSize = .zero

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
    /// Puntúa la última toma grabada (`XFAnalysis` → pantalla de resultados).
    /// Sin efecto en Freestyle (no hay patrón que puntuar).
    private let onScore: (XFSession) -> Void
    /// Ruta del sample de scratch a cargar al abrir (F.3). Vacío = el asset por
    /// defecto. Si el fichero no existe, cae al asset.
    private let scratchSamplePath: String
    /// Se llama al cargar un sample nuevo, con su ruta (para persistirla).
    private let onScratchSampleChanged: (String) -> Void
    /// Comandos que llegan por MIDI (cue, reiniciar base, congelar, grabar,
    /// fader…). Los publica `AppModel`; aquí se enrutan a las mismas acciones que
    /// el teclado. Por defecto un publisher vacío (sin mesa MIDI).
    private let commandEvents: AnyPublisher<PracticeCommandEvent, Never>
    /// Overlay de fps en la autopista (ajuste de diagnóstico, B7.2b).
    private let showFPS: Bool

    public init(scratch: Scratch,
                exerciseName: String,
                bpm: Int,
                geometry: HighwayGeometry,
                freestyle: Bool = false,
                engine: EngineHandle? = nil,
                content: ContentLoader = RepoContentLoader(),
                metronomeOn: Bool = true,
                scratchSamplePath: String = "",
                showFPS: Bool = false,
                commandEvents: AnyPublisher<PracticeCommandEvent, Never>
                    = Empty(completeImmediately: false).eraseToAnyPublisher(),
                onMetronomeChanged: @escaping (Bool) -> Void = { _ in },
                onScore: @escaping (XFSession) -> Void = { _ in },
                onScratchSampleChanged: @escaping (String) -> Void = { _ in },
                onExit: @escaping () -> Void = {}) {
        self.scratch = scratch
        self.exerciseName = exerciseName
        self.freestyle = freestyle
        self.geometry = geometry
        self.engine = engine
        self.content = content
        self.metronomeOn = metronomeOn
        self.scratchSamplePath = scratchSamplePath
        self.showFPS = showFPS
        self.commandEvents = commandEvents
        self.onMetronomeChanged = onMetronomeChanged
        self.onScore = onScore
        self.onScratchSampleChanged = onScratchSampleChanged
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
        return ZStack {
        VStack(spacing: 0) {
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
                        gridShift: gridShift,
                        onHighwaySize: { highwaySize = $0 },
                        showFPS: showFPS)
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
                        onRestartInstrumental: { restartInstrumental() },   // 2
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
        .onReceive(commandEvents) { handleCommand($0) }
        .onAppear { quote = Quotes.random(from: content); start() }
        .onDisappear { stop() }

        if loading {
            LoadingView(quote: quote).zIndex(1)
        }
        }
        .animation(.easeOut(duration: 0.25), value: loading)
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
                    // F.3: cargar tu propio sample; se recorta al punto cero.
                    Button(action: pickScratchSample) {
                        HStack(spacing: 5) {
                            Image(systemName: "waveform.badge.plus")
                            Text(sampleName).font(XFFont.body(10)).lineLimit(1).truncationMode(.middle)
                            Spacer()
                            Image(systemName: "folder").font(.system(size: 9))
                                .foregroundColor(XFColor.textMuted)
                        }
                        .foregroundColor(XFColor.text)
                    }
                    .buttonStyle(.plain)
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
                    .lineLimit(1).fixedSize()
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
                // reinicia la base desde el "1" (tambien con la tecla 2)
                Text("Reiniciar (2)").font(XFFont.body(9)).foregroundColor(XFColor.textMuted)
                Spacer(minLength: 0)
                chip("arrow.counterclockwise", icon: true) { restartInstrumental() }
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
                         : (arming ? "Claqueta · \(session.recCountBeats)" : "Grabar"))
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

            // F.4: exportar la toma como vídeo vertical para compartir.
            VStack(alignment: .leading, spacing: 3) {
                Button { exportVideo() } label: {
                    HStack(spacing: 4) {
                        Image(systemName: exportingVideo ? "hourglass" : "film").font(.system(size: 9))
                        Text(exportingVideo
                             ? "Exportando vídeo… \(Int(videoProgress * 100)) %"
                             : "Vídeo…").font(XFFont.body(9))
                        Spacer(minLength: 0)
                    }
                    .foregroundColor(lastRecording == nil ? XFColor.textMuted : XFColor.text)
                }
                .buttonStyle(.plain)
                .disabled(lastRecording == nil || active || exportingVideo)

                if exportingVideo {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(XFColor.surface).frame(height: 3)
                            Capsule().fill(XFColor.accent)
                                .frame(width: geo.size.width * CGFloat(videoProgress), height: 3)
                        }
                    }
                    .frame(height: 3)
                }
            }

            // puntuar la toma contra el patron (XFAnalysis -> resultados).
            // En Freestyle no hay patron: no aparece.
            if !freestyle, let rec = lastRecording, !active {
                Button {
                    onScore(rec)
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.seal").font(.system(size: 9))
                        Text("Puntuar la toma").font(XFFont.bodyMedium(10))
                        Spacer(minLength: 0)
                    }
                    .foregroundColor(XFColor.accent)
                    .padding(.vertical, 4).padding(.horizontal, XFSpacing.xs)
                    .frame(maxWidth: .infinity)
                    .background(RoundedRectangle(cornerRadius: 5)
                        .fill(XFColor.accent.opacity(0.12)))
                }
                .buttonStyle(.plain)
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

                // si la toma se grabó sobre otra base, avisa (se reproduce
                // igual, cuadrada de fase, pero los golpes no son los mismos).
                if !session.playbackInstrName.isEmpty,
                   session.playbackInstrName != PracticeSession.slug(instrName) {
                    HStack(spacing: 3) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 7))
                        Text("grabada sobre \(session.playbackInstrName)")
                            .font(XFFont.body(8)).lineLimit(1).truncationMode(.middle)
                    }
                    .foregroundColor(Color(hex: 0xF5C542))
                }
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

    /// F.4: renderiza la última toma como vídeo vertical 9:16 **con audio** (el
    /// `xf_engine` reproducido offline siguiendo el movimiento grabado). El
    /// render corre en segundo plano; el botón muestra el progreso.
    private func exportVideo() {
        guard let rec = lastRecording, !exportingVideo else { return }
        let panel = NSSavePanel()
        panel.allowedFileTypes = ["mp4"]
        panel.nameFieldStringValue = "toma.mp4"
        panel.prompt = "Exportar"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        exportingVideo = true
        videoProgress = 0
        let sc = scratch
        // el vídeo sale con la MISMA proporción que la autopista en pantalla
        // (si aún no se ha reportado, cae a la geometría nominal).
        var g = geometry
        if highwaySize.width > 1, highwaySize.height > 1 { g.size = highwaySize }
        let pcm = engine?.scratchPCMCopy()
        let instr = engine?.instrumentalPCMCopy()
        TakeVideoExporter.export(session: rec, scratch: sc, geometry: g,
            scratchPCM: pcm, instrumental: instr, to: url,
            progress: { p in DispatchQueue.main.async { videoProgress = p } },
            completion: { _ in DispatchQueue.main.async { exportingVideo = false } })
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

    /// Tecla `2` / botón: reinicia la instrumental desde el principio y realinea
    /// el reloj de la sesión (rejilla + fantasma) con ella. El scratch y el cue 1
    /// no se tocan: esto es solo la base.
    private func restartInstrumental() {
        engine?.replayInstrumental(nativeBPM: Double(session.bpm))
        session.resyncClock()
        engine?.setTransport(bpm: Double(session.bpm), ppq: 480, playing: !session.frozen)
        gridShift = 0
    }

    private func retempo(_ factor: Double) {
        session.setBPM(Int((Double(session.bpm) * factor).rounded()))
        // ÷2/×2 reinterpreta la rejilla: el mismo audio pasa a tener la mitad /
        // el doble de compases, asi que su bucle en TICKS escala con el factor.
        instrLoopTicks *= factor
        session.setInstrumentalLoopTicks(instrLoopTicks)
        engine?.replayInstrumental(nativeBPM: Double(session.bpm))
        engine?.setTransport(bpm: Double(session.bpm), ppq: 480, playing: !session.frozen)
        session.resyncClock()
        gridShift = 0
    }

    // MARK: - comandos por MIDI

    /// Enruta un comando recibido por MIDI a la misma acción que dispara el
    /// teclado. El fader es momentáneo (pulsar = cerrado); el resto, discretos.
    private func handleCommand(_ event: PracticeCommandEvent) {
        let s = session
        switch event {
        case .faderClosed(let closed):
            // solo avisa a la sesión; el gain lo pone el `.onChange` de
            // `session.faderClosed` (igual que el fader del trackpad).
            s.setFaderClosed(closed)

        case .trigger(.fader):
            break   // el fader nunca llega como trigger

        case .trigger(.cue):
            s.jumpToCue()
            engine?.seekScratch(0)

        case .trigger(.restartBase):
            restartInstrumental()

        case .trigger(.freeze):
            s.toggleFreeze()
            engine?.setTransport(bpm: Double(s.bpm), ppq: 480, playing: !s.frozen)

        case .trigger(.record):
            if s.recording { lastRecording = s.stopRecording() }
            else if s.recArming { s.stopRecording() }
            else { s.stopPlayback(); s.armRecording() }

        case .trigger(.bpmUp):
            s.setBPM(s.bpm + 1)
            engine?.setTransport(bpm: Double(s.bpm), ppq: 480, playing: true)

        case .trigger(.bpmDown):
            s.setBPM(s.bpm - 1)
            engine?.setTransport(bpm: Double(s.bpm), ppq: 480, playing: true)

        case .trigger(.metronome):
            metroOn.toggle()
            engine?.metronomeEnabled = metroOn
            onMetronomeChanged(metroOn)

        case .trigger(.callResponse):
            guard !freestyle else { break }
            s.setCallResponse(s.crPhase == .off)
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
        guard let engine = engine else { session.start(); loading = false; return }

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

        // 1) el SAMPLE de scratch (recortado al punto cero, F.3). Si hay uno
        // guardado y el fichero sigue existiendo, ese; si no, el asset. 2) la
        // instrumental; `loadInstrumental` arranca la salida, el reloj y la
        // sesion al terminar.
        let saved = scratchSamplePath.isEmpty ? nil
            : (FileManager.default.fileExists(atPath: scratchSamplePath)
               ? URL(fileURLWithPath: scratchSamplePath) : nil)
        loadScratchSample(url: saved, initial: true)
    }

    /// Decodifica un sample de scratch (el del asset si `url == nil`, o el que
    /// elige el usuario), lo **recorta al punto cero** (`SampleTrim`, F.3), lo
    /// carga en el motor y rehace la onda del rail izquierdo. `initial` encadena
    /// la carga de la instrumental (que arranca la sesion).
    private func loadScratchSample(url: URL?, initial: Bool) {
        guard let engine = engine else { return }
        let sr = engine.sampleRateHz
        sampleName = url?.deletingPathExtension().lastPathComponent ?? "Ahh"
        DispatchQueue.global(qos: .userInitiated).async {
            let raw = url.flatMap { AudioAsset.loadMono($0, sampleRate: sr) }
                ?? AudioAsset.loadMono(AudioAsset.scratchRelPath, from: content)
            let pcm = raw.map { SampleTrim.trimmed($0, sampleRate: sr).pcm }
            let wave = pcm.map {
                WaveformColored.build($0, sampleRate: sr, buckets: min($0.count / 48, 200_000))
            } ?? WaveformColored.Data(levels: [], colors: [])
            DispatchQueue.main.async {
                if let pcm, pcm.count > 1 {
                    engine.loadSample(pcm)
                    engine.seekScratch(0)
                    session.jumpToCue()
                }
                sampleWave = wave
                if initial { loadInstrumental(url: nil, initial: true) }
            }
        }
    }

    /// Abre un selector y carga ese sample de scratch (recortado al punto cero).
    private func pickScratchSample() {
        let panel = NSOpenPanel()
        panel.allowedFileTypes = ["wav", "aif", "aiff", "caf", "mp3", "m4a", "aac"]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.prompt = "Cargar"
        if panel.runModal() == .OK, let url = panel.url {
            loadScratchSample(url: url, initial: false)
            onScratchSampleChanged(url.path)
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
                // tomas grabadas a un multiplo entero de el, y el nombre para la
                // cabecera de la toma.
                session.setInstrumentalLoopTicks(loopTicks)
                session.setInstrumentalName(instrName)
                // el tempo del EJERCICIO pasa a ser el de esta instrumental
                session.setBPM(bpmRounded)
                session.resyncClock()
                engine.setTransport(bpm: Double(session.bpm), ppq: 480, playing: true)
                if initial {
                    _ = engine.startOutput()
                    session.start()
                    loading = false   // ya suena: fuera la pantalla de carga
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
                 + "Espacio: fader cerrado   ·   P: congelar   ·   1: cue   ·   2: reiniciar base   ·   ↑ ↓: BPM   ·   Esc: salir")
                .font(XFFont.body(12)).foregroundColor(XFColor.textMuted)
            Spacer()
        }
        .padding(.horizontal, XFSpacing.md)
        .padding(.vertical, XFSpacing.xs)
        .background(XFColor.surface)
    }
}
