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
///
/// Un paso del **calentamiento en una sola sesión** (F.0): el patrón + su nombre
/// + cuántas frases de "repite conmigo" hacer antes de pasar al siguiente. Lleva
/// también el `exerciseId`/`variantId` para que, si puntúas una toma a mitad de
/// calentamiento, se registre contra el ejercicio que toca (`mode:.warmup`).
public struct WarmupStep: Equatable {
    public let scratch: Scratch
    public let name: String
    public let phraseCount: Int
    public let exerciseId: String
    public let variantId: String
    public init(scratch: Scratch, name: String, phraseCount: Int,
                exerciseId: String, variantId: String) {
        self.scratch = scratch; self.name = name; self.phraseCount = phraseCount
        self.exerciseId = exerciseId; self.variantId = variantId
    }
}

public struct LivePracticeView: View {

    @StateObject private var session: PracticeSession
    @State private var sampleWave = WaveformColored.Data(levels: [], colors: [])
    // Onda de la instrumental (tira superior) + longitud musical de su bucle.
    @State private var instrWave = WaveformColored.Data(levels: [], colors: [])
    @State private var instrLoopTicks: Double = 0
    // Instrumental subida por el usuario en "modo loop": el fichero ES un bucle
    // de N compases y suena a velocidad natural; el BPM de la rejilla se DERIVA
    // de N y de la duración, así el metrónomo y el compás quedan clavados al
    // bucle. `nil` = base por defecto del asset (no es modo loop). `instrFileSeconds`
    // guarda la duración real para recalcular el BPM al cambiar N (botones −/+).
    @State private var instrLoopBars: Int?
    @State private var instrFileSeconds: Double = 0
    // BPM de la base a mano: TAP tempo (`TapTempo` puro) y edición directa del
    // número. La detección afina bien pero no siempre clava; esto lo remata.
    @State private var tap = TapTempo()
    @State private var editingBPM = false
    @State private var bpmText = ""
    // Volumenes por sesion (no se persisten: asi la practica nunca arranca muda).
    // Ambos arrancan a la mitad: el sample a tope tapaba la instrumental.
    @State private var sampleVol: Double = 0.5
    @State private var instruVol: Double = 0.5
    // EQ Lo/Mid/Hi del sample de scratch, en dB (por sesion; 0 = plano). Solo
    // afecta al scratch, no a la base ni al metronomo.
    @State private var eqLowDb: Double = 0
    @State private var eqMidDb: Double = 0
    @State private var eqHighDb: Double = 0
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
    // F.3: samples recordados (se siembra de `sampleLibrary` y se persiste con
    // `onSampleLibraryChanged`); ruta del sample activo ("" = asset por defecto).
    @State private var library: [String] = []
    @State private var activeSamplePath: String = ""
    // F.3: si el sample cargado parece un loop rítmico, su descripción.
    @State private var sampleLoopInfo: String?
    // F.3: cue points A/B como fracción 0…1 del sample (por sesión, no se guardan).
    @State private var cueA: Double?
    @State private var cueB: Double?
    // F.4: exportación de vídeo en curso y su progreso (0…1).
    @State private var exportingVideo = false
    @State private var videoProgress: Double = 0
    // Pantalla de carga (logo + cita) mientras decodifica sample + instrumental.
    @State private var loading = true
    @State private var quote = ""
    // Tamaño real de la autopista en pantalla, para exportar el vídeo con la
    // misma proporción que la ventana (lo reporta `PracticeScene`).
    @State private var highwaySize: CGSize = .zero
    // F.0: calentamiento en una sola sesión. Índice del ejercicio actual, nº de
    // frases "respondidas" del actual y la última fase vista de call-response.
    @State private var warmupIndex = 0
    @State private var warmupResponds = 0
    @State private var lastCrPhase: PracticeSession.CallResponsePhase = .off
    // F.0: resultado de la última toma puntuada dentro del calentamiento
    // (estrellas · precisión · aviso de oxidación). Se enseña en un panel que se
    // puede cerrar; no navega a resultados para no cortar la tanda.
    @State private var warmupTake: (stars: Int, pct: Int, note: String?)?

    private let meterTick = Timer.publish(every: 0.05, on: .main, in: .common).autoconnect()

    private let scratch: Scratch
    private let exerciseName: String
    /// F.0: si viene lleno, el calentamiento corre **todos** los ejercicios en
    /// una sola sesión — cambia de patrón cada `phraseCount` frases sin recargar
    /// audio ni salir de la práctica.
    private let warmupSteps: [WarmupStep]
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
    /// Puntúa una toma hecha **dentro del calentamiento** (F.0): la registra como
    /// `mode:.warmup` y devuelve estrellas + precisión + aviso de oxidación para
    /// enseñarlo aquí mismo, sin salir a resultados (así la tanda no se corta).
    private let onWarmupScore: (XFSession, String, String)
        -> (stars: Int, accuracyPercent: Int, oxidationMessage: String?)?
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
    /// Si viene del calentamiento: arranca en "repite conmigo" con N compases
    /// por frase (F.0).
    private let startInCallResponseBars: Int?
    /// FPS y lado mayor del vídeo exportado (F.4, vienen de Ajustes).
    private let videoFps: Int
    private let videoLongSide: Int
    /// Samples de scratch recordados (F.3). `onSampleLibraryChanged` los persiste.
    private let sampleLibrary: [String]
    private let onSampleLibraryChanged: ([String]) -> Void
    /// Ajustes de "tacto" del plato (ventana Ajustes › Debug). Se aplican al
    /// abrir la práctica.
    private let platterGlideMs: Double
    private let platterSpeedGate: Double
    private let platterFriction: Double
    private let trackpadSensitivity: Double

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
                startInCallResponseBars: Int? = nil,
                warmupSteps: [WarmupStep] = [],
                videoFps: Int = 30,
                videoLongSide: Int = 1600,
                sampleLibrary: [String] = [],
                platterGlideMs: Double = 3.0,
                platterSpeedGate: Double = 0.12,
                platterFriction: Double = 1.8,
                trackpadSensitivity: Double = 1.0,
                commandEvents: AnyPublisher<PracticeCommandEvent, Never>
                    = Empty(completeImmediately: false).eraseToAnyPublisher(),
                onMetronomeChanged: @escaping (Bool) -> Void = { _ in },
                onScore: @escaping (XFSession) -> Void = { _ in },
                onWarmupScore: @escaping (XFSession, String, String)
                    -> (stars: Int, accuracyPercent: Int, oxidationMessage: String?)? = { _, _, _ in nil },
                onScratchSampleChanged: @escaping (String) -> Void = { _ in },
                onSampleLibraryChanged: @escaping ([String]) -> Void = { _ in },
                onExit: @escaping () -> Void = {}) {
        self.warmupSteps = warmupSteps
        self.scratch = warmupSteps.first?.scratch ?? scratch
        self.exerciseName = warmupSteps.first?.name ?? exerciseName
        self.freestyle = freestyle
        self.geometry = geometry
        self.engine = engine
        self.content = content
        self.metronomeOn = metronomeOn
        self.scratchSamplePath = scratchSamplePath
        self.showFPS = showFPS
        self.startInCallResponseBars = startInCallResponseBars
        self.videoFps = videoFps
        self.videoLongSide = videoLongSide
        self.sampleLibrary = sampleLibrary
        self.platterGlideMs = platterGlideMs
        self.platterSpeedGate = platterSpeedGate
        self.platterFriction = platterFriction
        self.trackpadSensitivity = trackpadSensitivity
        self.commandEvents = commandEvents
        self.onMetronomeChanged = onMetronomeChanged
        self.onScore = onScore
        self.onWarmupScore = onWarmupScore
        self.onScratchSampleChanged = onScratchSampleChanged
        self.onSampleLibraryChanged = onSampleLibraryChanged
        self.onExit = onExit
        _metroOn = State(initialValue: metronomeOn)
        // Arranca al tempo de la instrumental para que suene coherente desde el
        // primer compas (el `bpm` del ejercicio manda cuando se cambie a mano).
        _ = bpm
        _session = StateObject(wrappedValue: PracticeSession(
            scratch: warmupSteps.first?.scratch ?? scratch,
            bpm: Int(AudioAsset.instrumentalNativeBPM)))
    }

    /// Patrón / nombre del ejercicio actual (el mismo salvo en el calentamiento
    /// multi-ejercicio, donde va cambiando).
    private var activeScratch: Scratch {
        warmupSteps.indices.contains(warmupIndex) ? warmupSteps[warmupIndex].scratch : scratch
    }
    private var activeName: String {
        warmupSteps.indices.contains(warmupIndex) ? warmupSteps[warmupIndex].name : exerciseName
    }
    /// El paso de calentamiento en curso (`nil` fuera del calentamiento).
    private var activeWarmupStep: WarmupStep? {
        warmupSteps.indices.contains(warmupIndex) ? warmupSteps[warmupIndex] : nil
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
                        scratch: activeScratch,
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
        .onChange(of: session.crPhase) { phase in
            // calentamiento: cada vez que se completa una frase (sales de
            // `respond`) se cuenta; al llegar a las del ejercicio, salta al
            // siguiente patrón sin salir de la práctica.
            guard !warmupSteps.isEmpty else { lastCrPhase = phase; return }
            if lastCrPhase == .respond, phase != .respond {
                warmupResponds += 1
                let need = warmupSteps.indices.contains(warmupIndex)
                    ? warmupSteps[warmupIndex].phraseCount : 8
                if warmupResponds >= need { advanceWarmup() }
            }
            lastCrPhase = phase
        }
        .onReceive(commandEvents) { handleCommand($0) }
        .onAppear {
            quote = Quotes.random(from: content)
            library = sampleLibrary
            activeSamplePath = scratchSamplePath
            // ajustes de "tacto" del plato (Ajustes › Debug)
            engine?.setScratchGlideMs(platterGlideMs)
            engine?.setScratchSpeedGate(platterSpeedGate)
            session.frictionPerSecond = platterFriction
            session.scrollSensitivity = trackpadSensitivity
            sensitivity = trackpadSensitivity
            start()
        }
        .onDisappear { stop() }

        if loading {
            LoadingView(quote: quote).zIndex(1)
        }
        }
        .animation(.easeOut(duration: 0.25), value: loading)
    }

    /// Calentamiento: pasa al siguiente ejercicio (cambia el patrón en caliente)
    /// o sale si era el último.
    private func advanceWarmup() {
        warmupResponds = 0
        warmupTake = nil            // el resultado del anterior no vale para el nuevo
        warmupIndex += 1
        guard warmupSteps.indices.contains(warmupIndex) else { onExit(); return }
        session.reload(scratch: warmupSteps[warmupIndex].scratch)
        engine?.seekScratch(0)
        // "repite conmigo" ya está en marcha a 2 compases; solo cambia el patrón.
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
                    sampleEQ
                    samplePicker
                    if let info = sampleLoopInfo {
                        Text(info).font(XFFont.body(9)).foregroundColor(Color(hex: 0xF5C542))
                            .lineLimit(1)
                    }
                    cueButtons
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

    // MARK: - F.3: sample de scratch (biblioteca + cue points)

    /// Menú del sample activo: el asset por defecto + los samples recordados +
    /// "Cargar otro…". Al elegir uno se carga; al cargar uno nuevo entra en la
    /// biblioteca.
    private var samplePicker: some View {
        Menu {
            Button("Ahh (por defecto)") { chooseSample(path: "") }
            if !library.isEmpty {
                Divider()
                ForEach(library, id: \.self) { path in
                    Button(URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent) {
                        chooseSample(path: path)
                    }
                }
            }
            Divider()
            Button("Cargar otro…") { pickScratchSample() }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "waveform")
                Text(sampleName).font(XFFont.body(10)).lineLimit(1).truncationMode(.middle)
                Spacer()
                Image(systemName: "chevron.up.chevron.down").font(.system(size: 8))
                    .foregroundColor(XFColor.textMuted)
            }
            .foregroundColor(XFColor.text)
        }
        .menuStyle(.borderlessButton)
    }

    /// Cue A / B: fija la posición actual del cabezal del sample y salta a ella.
    private var cueButtons: some View {
        HStack(spacing: 5) {
            Text("Cue").font(XFFont.body(9)).foregroundColor(XFColor.textMuted)
            Spacer(minLength: 0)
            cueChip("A", slot: $cueA)
            cueChip("B", slot: $cueB)
        }
    }

    private func cueChip(_ label: String, slot: Binding<Double?>) -> some View {
        let set = slot.wrappedValue != nil
        return Button {
            if let f = slot.wrappedValue {
                session.jumpTo(sampleFraction: f)
                if let e = engine, e.scratchFrameCount > 1 {
                    e.seekScratch(f * Double(e.scratchFrameCount - 1))
                }
            } else {
                slot.wrappedValue = engine.map { _ in session.normalizedPosition } ?? session.normalizedPosition
            }
        } label: {
            Text(set ? label : "+\(label)").font(XFFont.mono(10))
                .frame(width: 26, height: 20)
                .background(RoundedRectangle(cornerRadius: 4)
                    .fill(set ? XFColor.accent.opacity(0.18) : XFColor.surface))
                .overlay(RoundedRectangle(cornerRadius: 4).stroke(XFColor.stroke, lineWidth: 1))
                .foregroundColor(set ? XFColor.accent : XFColor.textMuted)
        }
        .buttonStyle(.plain)
        .simultaneousGesture(LongPressGesture().onEnded { _ in slot.wrappedValue = nil })
    }

    /// Carga un sample de la biblioteca (o el asset por defecto si `path` vacío).
    private func chooseSample(path: String) {
        guard path != activeSamplePath else { return }
        let url = path.isEmpty ? nil : URL(fileURLWithPath: path)
        if let url, !FileManager.default.fileExists(atPath: url.path) {
            library.removeAll { $0 == path }
            onSampleLibraryChanged(library)
            return
        }
        cueA = nil; cueB = nil
        loadScratchSample(url: url, initial: false)
        activeSamplePath = path
        onScratchSampleChanged(path)
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
                // pinchar el número -> editarlo a mano
                if editingBPM {
                    TextField("BPM", text: $bpmText, onCommit: {
                        if let v = Int(bpmText.trimmingCharacters(in: .whitespaces)) {
                            setInstrumentalBPM(v)
                        }
                        editingBPM = false
                    })
                    .textFieldStyle(.roundedBorder)
                    .font(XFFont.mono(12))
                    .frame(width: 54)
                } else {
                    Button {
                        bpmText = "\(session.bpm)"
                        editingBPM = true
                    } label: {
                        Text("\(session.bpm) BPM").font(XFFont.mono(12)).foregroundColor(XFColor.accent)
                    }
                    .buttonStyle(.plain)
                }
                Spacer(minLength: 0)
                chip("TAP") { if let bpm = tap.tap() { setInstrumentalBPM(bpm) } }
                chip("÷2") { retempo(0.5) }
                chip("×2") { retempo(2.0) }
            }

            if let bars = instrLoopBars {
                // instrumental subida en modo loop: se ajusta cuántos compases
                // dura el bucle; el BPM se recalcula solo para que cuadre.
                HStack(spacing: 5) {
                    Text("Loop").font(XFFont.body(9)).foregroundColor(XFColor.textMuted)
                    Spacer(minLength: 0)
                    chip("minus", icon: true) { relockLoop(bars: bars - 1) }
                    Text("\(bars) \(bars == 1 ? "compás" : "compases")")
                        .font(XFFont.mono(11)).foregroundColor(XFColor.text)
                        .frame(minWidth: 62)
                    chip("plus", icon: true) { relockLoop(bars: bars + 1) }
                }
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
            // En Freestyle no hay patron: no aparece. En el calentamiento se
            // registra como `mode:.warmup` y el resultado se enseña aqui mismo.
            if !freestyle, let rec = lastRecording, !active {
                Button {
                    if let step = activeWarmupStep {
                        warmupTake = onWarmupScore(rec, step.exerciseId, step.variantId)
                            .map { ($0.stars, $0.accuracyPercent, $0.oxidationMessage) }
                    } else {
                        onScore(rec)
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.seal").font(.system(size: 9))
                        Text(activeWarmupStep == nil ? "Puntuar la toma"
                                                     : "Puntuar (calentamiento)")
                            .font(XFFont.bodyMedium(10))
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

            if let take = warmupTake {
                warmupTakeCard(take)
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
        let sc = activeScratch
        // el vídeo sale con la MISMA proporción que la autopista en pantalla
        // (si aún no se ha reportado, cae a la geometría nominal).
        var g = geometry
        if highwaySize.width > 1, highwaySize.height > 1 { g.size = highwaySize }
        let pcm = engine?.scratchPCMCopy()
        let instr = engine?.instrumentalPCMCopy()
        var opts = TakeVideoExporter.Options()
        opts.fps = videoFps
        opts.longSide = videoLongSide
        // el vídeo suena como lo que estabas oyendo: mismos volúmenes del mixer
        let mix: (master: Float, scratch: Float, instrumental: Float) =
            (0.85, Float(sampleVol), Float(instruVol))
        TakeVideoExporter.export(session: rec, scratch: sc, geometry: g, options: opts,
            scratchPCM: pcm, instrumental: instr, mix: mix, to: url,
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
            engine?.seek(tick: 0)      // metrónomo al "1", como la base y la rejilla
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
        // El metrónomo va con el reloj del MOTOR (`e->tick`), no con el de la
        // sesión. Si no lo mandamos también a 0 aquí, la base vuelve al "1" pero
        // el clic sigue en su fase vieja y se descuadra respecto a la rejilla.
        // `seek(tick:)` rearma el metrónomo para que el "1" suene en el 0.
        engine?.seek(tick: 0)
        gridShift = 0
    }

    private func retempo(_ factor: Double) {
        // En modo loop, ×2 / ÷2 = doblar / partir el nº de compases del bucle
        // (misma reinterpretación, pero manteniendo el BPM clavado a la duración).
        if let bars = instrLoopBars {
            relockLoop(bars: factor > 1 ? bars * 2 : bars / 2)
            return
        }
        session.setBPM(Int((Double(session.bpm) * factor).rounded()))
        // ÷2/×2 reinterpreta la rejilla: el mismo audio pasa a tener la mitad /
        // el doble de compases, asi que su bucle en TICKS escala con el factor.
        instrLoopTicks *= factor
        session.setInstrumentalLoopTicks(instrLoopTicks)
        engine?.replayInstrumental(nativeBPM: Double(session.bpm))
        engine?.setTransport(bpm: Double(session.bpm), ppq: 480, playing: !session.frozen)
        session.resyncClock()
        engine?.seek(tick: 0)          // metrónomo al "1", como la base y la rejilla
        gridShift = 0
    }

    /// Modo loop: fija en `bars` los compases que dura la instrumental subida y
    /// **deriva el BPM** de la rejilla de esa cuenta y de la duración real del
    /// fichero (`instrFileSeconds`). El audio sigue sonando a velocidad natural;
    /// lo que cambia es cómo lo cuadriculamos. Con esto el metrónomo y las líneas
    /// de compás quedan pegados al bucle aunque la detección de tempo fallara.
    private func relockLoop(bars: Int) {
        guard instrFileSeconds > 0.01 else { return }
        let loop = InstrumentalLoop.locked(
            bars: bars, fileSeconds: instrFileSeconds,
            beatsPerBar: geometry.beatsPerBar, ppq: scratch.ppq)
        instrLoopBars = loop.bars
        instrLoopTicks = loop.loopTicks
        session.setInstrumentalLoopTicks(loop.loopTicks)
        session.setBPM(Int(loop.bpm.rounded()))
        engine?.replayInstrumental(nativeBPM: loop.bpm)
        session.resyncClock()
        engine?.setTransport(bpm: Double(session.bpm), ppq: 480, playing: !session.frozen)
        engine?.seek(tick: 0)          // metrónomo al "1", como la base y la rejilla
        gridShift = 0
    }

    /// Fija el BPM de la rejilla a mano (TAP o edición del número), **en caliente**:
    /// la rejilla y el metrónomo pasan al nuevo tempo desde donde están, sin
    /// saltos; la base sigue sonando donde estaba y a su velocidad real (se
    /// reajusta su `nativeBPM` para que el ratio no cambie). NO reinicia nada ni
    /// resincroniza el reloj — eso es lo que hace `TAP` diferente de ÷2/×2.
    /// En modo loop el BPM se traduce al nº de compases entero más cercano.
    private func setInstrumentalBPM(_ target: Int) {
        let clamped = min(220, max(40, target))
        let old = Double(max(1, session.bpm))

        if instrLoopBars != nil, instrFileSeconds > 0.01 {
            let bpb = Double(geometry.beatsPerBar)
            let bars = max(1, Int((Double(clamped) * instrFileSeconds / (bpb * 60.0)).rounded()))
            instrLoopBars = bars
            instrLoopTicks = Double(bars * geometry.beatsPerBar) * Double(scratch.ppq)
        } else {
            instrLoopTicks *= Double(clamped) / old
        }
        session.setInstrumentalLoopTicks(instrLoopTicks)
        session.setBPM(clamped)
        // primero el transporte (fija `e->bpm`, que marca el tempo del metrónomo
        // y del reloj), luego el nativeBPM de la base para que su ratio quede en
        // ~1 (suena a su velocidad real). NADA reinicia el cabezal ni el reloj.
        engine?.setTransport(bpm: Double(session.bpm), ppq: 480, playing: !session.frozen)
        engine?.setInstrumentalNativeBPM(Double(session.bpm))
    }

    /// F.0 — panel del resultado de una toma de calentamiento: estrellas +
    /// precisión, y si el ejercicio se ha oxidado, el aviso concreto. Sobrio: no
    /// hay confeti ni "¡bien!", solo el dato. Se cierra con la X.
    private func warmupTakeCard(_ take: (stars: Int, pct: Int, note: String?)) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                ForEach(0..<3, id: \.self) { i in
                    Image(systemName: i < take.stars ? "star.fill" : "star")
                        .font(.system(size: 9))
                        .foregroundColor(i < take.stars ? XFColor.accent : XFColor.stroke)
                }
                Text("\(take.pct) %").font(XFFont.mono(10)).foregroundColor(XFColor.textMuted)
                Spacer(minLength: 0)
                Text("no cuenta para estrellas").font(XFFont.body(8))
                    .foregroundColor(XFColor.textMuted)
                Button { warmupTake = nil } label: {
                    Image(systemName: "xmark").font(.system(size: 8))
                        .foregroundColor(XFColor.textMuted)
                }
                .buttonStyle(.plain)
            }
            if let note = take.note {
                Text(note).font(XFFont.body(10)).foregroundColor(XFColor.text)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 5).padding(.horizontal, XFSpacing.xs)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 5)
            .fill((take.note == nil ? XFColor.textMuted : XFColor.accent).opacity(0.12)))
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

    /// EQ Lo/Mid/Hi del sample de scratch (dB). Cada mando 0 = plano; el motor no
    /// filtra si los tres están a 0. No toca la base ni el metrónomo.
    private var sampleEQ: some View {
        VStack(spacing: 2) {
            HStack {
                Text("EQ sample").font(XFFont.body(10)).foregroundColor(XFColor.textMuted)
                Spacer()
                Button("plano") { eqLowDb = 0; eqMidDb = 0; eqHighDb = 0; applyEQ() }
                    .buttonStyle(.plain)
                    .font(XFFont.body(9))
                    .foregroundColor((eqLowDb == 0 && eqMidDb == 0 && eqHighDb == 0)
                                     ? XFColor.textMuted : XFColor.accent)
            }
            eqSlider("Lo", $eqLowDb)
            eqSlider("Mid", $eqMidDb)
            eqSlider("Hi", $eqHighDb)
        }
    }

    private func eqSlider(_ label: String, _ db: Binding<Double>) -> some View {
        HStack(spacing: 4) {
            Text(label).font(XFFont.mono(9)).foregroundColor(XFColor.textMuted)
                .frame(width: 20, alignment: .leading)
            Slider(value: Binding(get: { db.wrappedValue },
                                  set: { db.wrappedValue = $0; applyEQ() }),
                   in: -24...6, step: 1)
                .controlSize(.mini)
            Text(db.wrappedValue == 0 ? "0" : String(format: "%+.0f", db.wrappedValue))
                .font(XFFont.mono(9)).foregroundColor(XFColor.textMuted)
                .frame(width: 22, alignment: .trailing)
        }
    }

    private func applyEQ() {
        engine?.setSampleEQ(lowDb: Float(eqLowDb), midDb: Float(eqMidDb), highDb: Float(eqHighDb))
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
        let hint = url.flatMap { TempoAnalyzer.bpmHint(fromFilename: $0.lastPathComponent) }
        DispatchQueue.global(qos: .userInitiated).async {
            let raw = url.flatMap { AudioAsset.loadMono($0, sampleRate: sr) }
                ?? AudioAsset.loadMono(AudioAsset.scratchRelPath, from: content)
            let pcm = raw.map { SampleTrim.trimmed($0, sampleRate: sr).pcm }
            let wave = pcm.map {
                WaveformColored.build($0, sampleRate: sr, buckets: min($0.count / 48, 200_000))
            } ?? WaveformColored.Data(levels: [], colors: [])
            // F.3: ¿es un loop rítmico? (solo para avisar; el sample se scratchea
            // igual, pero conviene saber que quizá va mejor como base).
            var loopInfo: String? = nil
            if url != nil, let pcm, pcm.count > Int(sr / 2),
               let a = TempoAnalyzer.analyze(pcm, sampleRate: sr, hintBPM: hint), a.isShortLoop {
                let bars = max(1, Int((Double(a.beats) / 4.0).rounded()))
                loopInfo = "loop ≈ \(Int(a.bpm.rounded())) BPM · \(bars) \(bars == 1 ? "compás" : "compases")"
            }
            DispatchQueue.main.async {
                if let pcm, pcm.count > 1 {
                    engine.loadSample(pcm)
                    engine.seekScratch(0)
                    session.jumpToCue()
                }
                sampleWave = wave
                sampleLoopInfo = loopInfo
                if initial { loadInstrumental(url: nil, initial: true) }
            }
        }
    }

    /// Abre un selector y carga ese sample de scratch (recortado al punto cero).
    /// El fichero elegido entra en la biblioteca (F.3).
    private func pickScratchSample() {
        let panel = NSOpenPanel()
        panel.allowedFileTypes = ["wav", "aif", "aiff", "caf", "mp3", "m4a", "aac"]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.prompt = "Cargar"
        if panel.runModal() == .OK, let url = panel.url {
            cueA = nil; cueB = nil
            loadScratchSample(url: url, initial: false)
            activeSamplePath = url.path
            onScratchSampleChanged(url.path)
            library.removeAll { $0 == url.path }
            library.insert(url.path, at: 0)
            if library.count > 12 { library = Array(library.prefix(12)) }
            onSampleLibraryChanged(library)
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
            // `userLoopBars != nil` -> "modo loop": el fichero es un bucle de N
            // compases, suena a velocidad natural y el BPM se DERIVA de N y la
            // duración. Solo se usa cuando el fichero PARECE un loop (corto, o sin
            // tempo detectable). Una pista larga con tempo claro va por la
            // detección normal — BPM + fase del "1" — como la base del asset.
            var userLoopBars: Int? = nil
            var fileSeconds = 0.0
            let hint = TempoAnalyzer.bpmHint(fromFilename: name)
            if let pcm = raw {
                fileSeconds = Double(pcm.count) / sr
                let a = TempoAnalyzer.analyze(pcm, sampleRate: sr, hintBPM: hint)

                if let a = a, !a.isShortLoop {
                    // pista larga con tempo detectado (asset o fichero del
                    // usuario): rejilla al BPM detectado y alineada al "1".
                    bpm = a.bpm
                    let phi = ((a.phaseFrames % pcm.count) + pcm.count) % pcm.count
                    pcmOut = phi == 0 ? pcm : Array(pcm[phi...]) + Array(pcm[..<phi])
                    loopTicks = fileSeconds * (a.bpm / 60.0) * Double(ppq)
                } else if url != nil {
                    // fichero del usuario que parece un loop (corto, o sin tempo):
                    // modo loop de N compases (`InstrumentalLoop`, cálculo puro).
                    let loop = InstrumentalLoop.guess(
                        fileSeconds: fileSeconds, beatsPerBar: beatsPerBar,
                        ppq: ppq, analyzedBeats: a.map { $0.beats })
                    userLoopBars = loop.bars
                    bpm = loop.bpm
                    loopTicks = loop.loopTicks
                    pcmOut = pcm            // un loop empieza en su "1": no se rota
                } else if let a = a {
                    // asset y ES un loop corto: BPM + fase de la detección, bucle
                    // de `beats` negras.
                    bpm = a.bpm
                    let phi = ((a.phaseFrames % pcm.count) + pcm.count) % pcm.count
                    pcmOut = phi == 0 ? pcm : Array(pcm[phi...]) + Array(pcm[..<phi])
                    loopTicks = Double(a.beats) * Double(ppq)
                } else {
                    // asset sin tempo detectable: cuadra a compases enteros.
                    let beats = fileSeconds * (bpm / 60.0)
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
                instrLoopBars = userLoopBars
                instrFileSeconds = fileSeconds
                // la sesion necesita la longitud del bucle para cuadrar las
                // tomas grabadas a un multiplo entero de el, y el nombre para la
                // cabecera de la toma.
                session.setInstrumentalLoopTicks(loopTicks)
                session.setInstrumentalName(instrName)
                // el tempo de la rejilla pasa a ser el de esta base (o el
                // derivado de los compases del loop en modo loop).
                session.setBPM(bpmRounded)
                session.resyncClock()
                engine.setTransport(bpm: Double(session.bpm), ppq: 480, playing: true)
                // reloj del motor (y con él el metrónomo) al "1", igual que la
                // rejilla de la sesión y el cabezal de la base recién cargada.
                engine.seek(tick: 0)
                if initial {
                    _ = engine.startOutput()
                    session.start()
                    loading = false   // ya suena: fuera la pantalla de carga
                    // calentamiento: arranca en "repite conmigo" con N compases.
                    if !freestyle, let bars = startInCallResponseBars {
                        session.setCallResponseBars(bars)
                        session.setCallResponse(true)
                        lastCrPhase = session.crPhase
                    }
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
            Text(activeName).font(XFFont.bodyMedium(14))
            if !warmupSteps.isEmpty {
                // Progreso del calentamiento: en que ejercicio de la tanda vamos.
                Text("Calentamiento \(min(warmupIndex + 1, warmupSteps.count))/\(warmupSteps.count)")
                    .font(XFFont.mono(10))
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(XFColor.accent.opacity(0.18))
                    .foregroundColor(XFColor.accent)
                    .cornerRadius(3)
            }
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
