// SPDX-License-Identifier: GPL-3.0-only

import SwiftUI
import Combine
import XFDesign
import XFRender
import XFNotation
import XFCapture

/// La vista raiz de xFlare: barra de navegacion + la pantalla actual segun
/// `AppModel.screen`. Sustituye a la maqueta inerte `HomeScaffoldView`.
public struct AppRootView: View {

    @ObservedObject private var model: AppModel
    @State private var showSplash = true
    /// El asistente de calibración vive AQUÍ, no inline en `current`: si se
    /// construyera un `CalibrationWizardModel()` nuevo en cada reevaluación
    /// del `body` (que pasa por cualquier `@Published` de `AppModel`, no solo
    /// los del propio asistente), cualquier dispositivo o dato que el usuario
    /// ya hubiera elegido se perdería sin avisar — "no me deja asignar nada"
    /// también podía venir de aquí. `@StateObject`: una sola instancia
    /// mientras viva `AppRootView`.
    @StateObject private var calibrationModel = CalibrationWizardModel()
    /// Dispositivos de audio para el paso 1 del asistente: se enumeran UNA VEZ
    /// al entrar en la pantalla (`.onChange(of: model.screen)`), no en cada
    /// reevaluación del `body` — arrastrar un slider del asistente no tiene
    /// por qué disparar llamadas a CoreAudio.
    @State private var calibrationDevices: [AudioDeviceList.Device] = []
    /// `true` mientras `model` está capturando entrada de verdad para el scope
    /// del paso 3. Sin esto, cada cambio de pantalla llamaría a
    /// `stopTimecodeCapture()` (reinicia el motor) aunque nunca hubiéramos
    /// empezado a capturar — solo hace falta pararlo al SALIR de Calibración.
    @State private var capturingTimecode = false
    /// Paso "Fader" del asistente (F.67): detecta qué CC/canal es el
    /// crossfader observando el tráfico real mientras el usuario lo mueve de
    /// tope a tope ("aprender"), y cuenta cortes en vivo con el cutIn/
    /// histéresis que se estén ajustando ahí — ninguno de los dos depende de
    /// hardware para EXISTIR (son puros, `XFCapture`), solo para recibir
    /// datos reales.
    @State private var faderLearner = MidiFaderLearner()
    @State private var faderBinarizer: FaderBinarizer?
    @State private var faderConfig: MidiCrossfaderConfig?
    /// F.72 (ADR-077) — para qué `deviceKey` ya se precargó una calibración
    /// guardada (`CalibrationWizardModel.applyLoaded`). Sin esto, cada
    /// `applyCalibrationSelection()` (dispara con cualquier cambio de canal)
    /// volvería a pisar cutIn/histéresis/CC aprendido con lo guardado,
    /// borrando un ajuste que el usuario esté tocando ahora mismo.
    @State private var calibrationLoadedDeviceKey: String?

    public init(model: AppModel) {
        self.model = model
    }

    public var body: some View {
        ZStack {
            appContent
            if showSplash {
                SplashView(onDone: { withAnimation(.easeOut(duration: 0.2)) { showSplash = false } })
            }
        }
        .preferredColorScheme(.dark)
    }

    private var appContent: some View {
        VStack(spacing: 0) {
            navBar
            Divider().background(XFColor.stroke)
            current
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(XFColor.bg)
        // xFlare es tema oscuro fijo: forzamos el esquema para que los colores
        // semanticos de SwiftUI (texto por defecto, controles de Form, Toggle,
        // Picker...) salgan en su variante clara. Sin esto, en un Mac en modo
        // claro el texto sin `.foregroundColor` sale casi negro sobre `bg` casi
        // negro y no se lee.
        .foregroundColor(XFColor.text)
        .preferredColorScheme(.dark)
        .onAppear { model.goHome() }
        .onChange(of: model.screen) { s in
            // enumerar dispositivos de audio es un puñado de llamadas a
            // CoreAudio: barato, pero no hace falta repetirlo en cada
            // reevaluación del body mientras el asistente está abierto (p.
            // ej. al arrastrar un slider) — solo al ENTRAR en la pantalla.
            if s == .calibration {
                calibrationDevices = AudioDeviceList.all()
                // Precarga el paso 1 con lo que YA está resuelto (Ajustes ›
                // Hardware, o el de sistema por defecto si no hay nada
                // elegido) — si no, los desplegables se ven vacíos aunque el
                // motor sí sepa qué dispositivo usar, y cualquier cambio real
                // de canal exige partir de un dispositivo ya seleccionado.
                if calibrationModel.outputDeviceName == nil,
                   let out = AudioDeviceList.resolvedOutput(uid: model.settings.outputDeviceUID,
                                                            in: calibrationDevices) {
                    calibrationModel.outputDeviceName = out.name
                }
                if calibrationModel.inputDeviceName == nil,
                   let inp = AudioDeviceList.resolvedInput(uid: model.settings.inputDeviceUID,
                                                           in: calibrationDevices) {
                    calibrationModel.inputDeviceName = inp.name
                }
                // F.68: precarga el canal de la instrumental si Ajustes ya
                // tenía uno guardado (0 = combinado se queda en `nil`).
                if calibrationModel.instrumentalOutputChannelFirst == nil,
                   model.settings.instrumentalOutputChannel > 0 {
                    calibrationModel.instrumentalOutputChannelFirst = model.settings.instrumentalOutputChannel
                }
                // el scope del paso 3 (Timecode) necesita el motor capturando
                // entrada de verdad — para lo que sonara en otra pantalla y
                // reabre el motor con captura (F.60/F.61 dejaron el motor
                // listo para esto). `model.onTimecodeSample` alimenta EL
                // MISMO modelo que ya dibuja el asistente, sin que `AppModel`
                // tenga que conocer `CalibrationWizardModel` (ADR-073: ese
                // modelo vive en la vista).
                model.onTimecodeSample = { sample in
                    calibrationModel.reportTimecode(confidence: Double(sample.confidence),
                                                    forwards: sample.velocity >= 0,
                                                    suggestedHamster: calibrationModel.hamster)
                }
                capturingTimecode = true
                // Aplica la selección (precargada arriba, o la que ya
                // hubiera de una visita anterior): fija canal por defecto,
                // vuelca a Ajustes Y arranca la captura — un solo camino en
                // vez de dos.
                applyCalibrationSelection()
                // Paso "Fader" (F.67): el crossfader real ya está sonando por
                // `AppModel.midiMonitor` durante TODA la sesión (F.61) — solo
                // hace falta escuchar el mismo grifo, no abrir nada nuevo.
                rebuildFaderConfig()
                model.onRawMidiMessage = { status, data1, data2 in
                    handleCalibrationMidi(status: status, data1: data1, data2: data2)
                }
            } else if capturingTimecode {
                // SOLO al salir de Calibración habiendo capturado de verdad —
                // si no, cualquier cambio de pantalla reiniciaría el motor.
                model.onTimecodeSample = nil
                model.stopTimecodeCapture()
                capturingTimecode = false
                model.onRawMidiMessage = nil
            } else {
                model.onRawMidiMessage = nil
            }
        }
        // Paso "Fader": si el usuario aprende un CC/canal nuevo, o mueve los
        // sliders de cutIn/histéresis, el binarizador en vivo tiene que
        // reflejarlo — si no, los cortes se seguirían contando contra el
        // umbral viejo mientras la UI muestra el nuevo.
        .onChange(of: calibrationModel.learnedFaderCC) { _ in rebuildFaderConfig() }
        .onChange(of: calibrationModel.faderCutIn) { _ in rebuildFaderConfig() }
        .onChange(of: calibrationModel.faderHysteresis) { _ in rebuildFaderConfig() }
        // El paso 1 (Audio) del asistente elegía dispositivo/canal en una
        // copia LOCAL (`calibrationModel`) que no llegaba a ningún sitio: el
        // motor seguía leyendo `model.settings`, sin tocar. Resultado real
        // con la Rane 72 conectada: "no puedo elegir la entrada estéreo del
        // timecode" (el selector no hacía nada) y scope vacío (la captura
        // seguía abierta con el canal viejo). Cualquier cambio del paso 1
        // vuelve a aplicar la selección completa.
        .onChange(of: calibrationModel.inputDeviceName) { _ in applyCalibrationSelection() }
        .onChange(of: calibrationModel.outputDeviceName) { _ in applyCalibrationSelection() }
        .onChange(of: calibrationModel.inputChannelFirst) { _ in applyCalibrationSelection() }
        .onChange(of: calibrationModel.outputChannelFirst) { _ in applyCalibrationSelection() }
        .onChange(of: calibrationModel.instrumentalOutputChannelFirst) { _ in applyCalibrationSelection() }
    }

    /// F.71 — botón "Refrescar dispositivos" del paso 1: re-enumera CoreAudio
    /// a mano. La lista normal solo se refresca al ENTRAR en Calibración (más
    /// abajo, `.onChange(of: model.screen)`); si el driver de la mesa tiene un
    /// hipo justo tras un replug de USB mientras ya estabas dentro del
    /// asistente (p. ej. reporta menos pares de salida de los que hay de
    /// verdad — visto con la Rane 72 al arreglar el "Aprender MIDI" con un
    /// replug), te quedas con esa foto vieja sin ningún cambio de pantalla
    /// que la refresque sola.
    private func refreshCalibrationDevices() {
        calibrationDevices = AudioDeviceList.all()
        applyCalibrationSelection()
    }

    /// Traslada la selección de dispositivo/canal del paso 1 a `AppSettings`
    /// — de donde de verdad lee el motor (`applyAudioDevicePreferences`) — y
    /// relanza la captura de timecode si ya estaba activa (paso 2), para que
    /// el scope refleje el canal nuevo sin tener que salir y volver a entrar
    /// en Calibración.
    private func applyCalibrationSelection() {
        guard model.screen == .calibration else { return }
        guard let outDevice = calibrationDevices.first(where: {
            $0.name == calibrationModel.outputDeviceName && $0.outputChannels > 0
        }) else { return }
        // F.72 (ADR-077) — la calibración se GUARDA bajo esta clave
        // (`CalibrationWizardModel.result()`), pero hasta ahora nadie la
        // fijaba: se quedaba en "" y `result()` caía al NOMBRE del
        // dispositivo — mientras que quien la LEE de vuelta
        // (`AppModel.rebuildCrossfaderSource`) buscaba por el UID. Dos claves
        // distintas para el mismo registro = la calibración guardada nunca se
        // encontraba, "no se guarda de una sesión a otra" aunque sí estuviera
        // en el fichero. Fijarla aquí, al UID del dispositivo de salida
        // resuelto (la misma fuente de verdad que `AppSettings.outputDeviceUID`),
        // cierra el círculo.
        if calibrationModel.deviceKey != outDevice.uid { calibrationModel.deviceKey = outDevice.uid }
        if let pid = model.activeProfileId, calibrationModel.profileId != pid { calibrationModel.profileId = pid }
        // Precarga el paso Fader con lo que ya se guardó para ESTA mesa, una
        // sola vez por `deviceKey` resuelto (no en cada cambio de canal, o
        // pisaría un ajuste en curso).
        if calibrationLoadedDeviceKey != outDevice.uid {
            calibrationLoadedDeviceKey = outDevice.uid
            if let saved = try? model.db.calibration(deviceKey: outDevice.uid) {
                calibrationModel.applyLoaded(saved)
            }
        }
        let outPairs = AudioDeviceList.outputChannelPairs(for: outDevice)
        let outFirst = AudioDeviceList.resolvedChannel(current: calibrationModel.outputChannelFirst, in: outPairs)
        // Solo escribe/reinicia si algo CAMBIA de verdad: fijar el mismo par
        // por defecto (nil -> primero) dispara este mismo método otra vez vía
        // `.onChange`, y sin esta guarda el motor se pararía y arrancaría dos
        // veces seguidas por cada entrada a la pantalla.
        var changed = calibrationModel.outputChannelFirst != outFirst
        calibrationModel.outputChannelFirst = outFirst
        if model.settings.outputDeviceUID != outDevice.uid { model.settings.outputDeviceUID = outDevice.uid; changed = true }
        if let outFirst, model.settings.outputChannel != outFirst { model.settings.outputChannel = outFirst; changed = true }

        // F.68 (ADR-075): canal de la BASE INSTRUMENTAL, si es distinto al
        // del scratch. A diferencia de `outFirst`/`inFirst`, aquí `nil` es un
        // estado válido por sí mismo ("Combinado") — si el par elegido ya no
        // existe en el dispositivo actual (p. ej. se cambió a uno con menos
        // canales) cae a `nil` (combinado, siempre seguro), NO al primer par
        // — saltar a otro par sin que el usuario lo pida sería peor sorpresa
        // que simplemente volver al comportamiento de siempre.
        let instrFirst = calibrationModel.instrumentalOutputChannelFirst.flatMap { c in
            outPairs.contains(where: { $0.first == c }) ? c : nil
        }
        if calibrationModel.instrumentalOutputChannelFirst != instrFirst {
            calibrationModel.instrumentalOutputChannelFirst = instrFirst
            changed = true
        }
        if model.settings.instrumentalOutputChannel != (instrFirst ?? 0) {
            model.settings.instrumentalOutputChannel = instrFirst ?? 0
            changed = true
        }

        if let inDevice = calibrationDevices.first(where: {
            $0.name == calibrationModel.inputDeviceName && $0.inputChannels > 0
        }) {
            let inPairs = AudioDeviceList.inputChannelPairs(for: inDevice)
            let inFirst = AudioDeviceList.resolvedChannel(current: calibrationModel.inputChannelFirst, in: inPairs)
            if calibrationModel.inputChannelFirst != inFirst { changed = true }
            calibrationModel.inputChannelFirst = inFirst
            if model.settings.inputDeviceUID != inDevice.uid { model.settings.inputDeviceUID = inDevice.uid; changed = true }
            if let inFirst, model.settings.inputChannel != inFirst { model.settings.inputChannel = inFirst; changed = true }
        }

        guard changed, capturingTimecode else { return }
        model.stopTimecodeCapture()
        model.startTimecodeCapture()
    }

    // MARK: - paso "Fader" del asistente (F.67)

    /// Qué `(canal, cc, rango)` usa el binarizador en vivo: lo aprendido en
    /// esta sesión si lo hay, si no el que declare el perfil activo (si
    /// declara `crossfader.method = midi`) — mismo criterio de prioridad que
    /// `AppModel.rebuildCrossfaderSource` (lo GUARDADO/aprendido manda sobre
    /// el `.conf`). Rearma también el binarizador con el cutIn/histéresis
    /// actuales de los sliders.
    private func rebuildFaderConfig() {
        if let ch = calibrationModel.learnedFaderChannel, let cc = calibrationModel.learnedFaderCC,
           let lo = calibrationModel.learnedFaderMin, let hi = calibrationModel.learnedFaderMax {
            faderConfig = MidiCrossfaderConfig(channel: ch, cc: cc, rawMin: lo, rawMax: hi)
        } else if let id = model.activeProfileId, let profile = model.profiles.profile(id: id) {
            faderConfig = try? MidiCrossfaderConfig(from: profile)
        } else {
            faderConfig = nil
        }
        faderBinarizer = FaderBinarizer(cutIn: Float(min(1, max(0, calibrationModel.faderCutIn))),
                                        hysteresis: Float(max(0, calibrationModel.faderHysteresis)))
    }

    /// Un mensaje MIDI real, mientras Calibración está en pantalla: durante
    /// el aprendizaje alimenta al `MidiFaderLearner`; si no, binariza contra
    /// `faderConfig`/`faderBinarizer` y cuenta un corte cada vez que
    /// `isOpen` CAMBIA (mismo criterio que `MidiFaderSource.onChange`, F.61).
    private func handleCalibrationMidi(status: UInt8, data1: UInt8, data2: UInt8) {
        if calibrationModel.faderLearning {
            faderLearner.ingest(status: status, data1: data1, data2: data2)
            calibrationModel.reportFaderLearnProgress(span: faderLearner.bestSpanSoFar)
            return
        }
        guard let config = faderConfig, status & 0xF0 == 0xB0 else { return }
        let channel = Int(status & 0x0F) + 1
        guard config.accepts(channel: channel), Int(data1) == config.cc,
              let value = config.value(fromCC: Int(data2)) else { return }
        let wasOpen = faderBinarizer?.isOpen ?? false
        let isOpen = faderBinarizer?.update(rawValue: value) ?? wasOpen
        guard isOpen != wasOpen else { return }
        calibrationModel.reportFaderCut(cutIn: calibrationModel.faderCutIn,
                                        hysteresis: calibrationModel.faderHysteresis)
    }

    /// Botón "Aprender MIDI del fader": arma la escucha y limpia lo que el
    /// `MidiFaderLearner` hubiera visto de un intento anterior.
    private func startFaderLearn() {
        faderLearner.reset()
        calibrationModel.startFaderLearn()
    }

    /// Botón "Listo" tras mover el fader de tope a tope: si el barrido es
    /// fiable, lo aprende (y `rebuildFaderConfig` se dispara solo vía
    /// `.onChange(of: calibrationModel.learnedFaderCC)`); si no, se cancela
    /// sin pisar un aprendizaje anterior.
    private func finishFaderLearn() {
        if let g = faderLearner.bestGuess() {
            calibrationModel.reportLearnedFader(channel: g.channel, cc: g.cc,
                                                rawMin: g.rawMin, rawMax: g.rawMax)
        } else {
            calibrationModel.cancelFaderLearn()
        }
    }

    private var navBar: some View {
        HStack(spacing: XFSpacing.xxs) {
            XFWordmark(size: 17)
                .padding(.trailing, XFSpacing.xs)
            Divider().frame(height: 18).background(XFColor.stroke)
                .padding(.trailing, XFSpacing.xs)
            Group {
                navButton("Home", "square.grid.3x3.fill", active: onHome) { model.goHome() }
                navButton("Trucos", "books.vertical", active: onTrucos) { model.openLibrary() }
                navButton("Librería", "square.stack", active: onLibreria) { model.openMediaLibrary() }
                navButton("Mi mesa", "pianokeys", active: isScreen(.myTable)) { model.openMyTable() }
                navButton("Calentar", "flame", active: isScreen(.warmup)) { model.openWarmup() }
                navButton("Freestyle", "waveform.and.mic", active: isScreen(.freeMode)) { model.openFreeMode() }
                navButton("Ajustes", "slider.horizontal.3", active: isScreen(.settings)) { model.openSettings() }
            }
            Spacer()
            navButton("Calibración", "dot.radiowaves.left.and.right",
                      active: isScreen(.calibration)) { model.openCalibration() }
        }
        .padding(.horizontal, XFSpacing.md)
        .padding(.vertical, XFSpacing.xs)
        .background(XFColor.surface)
        .overlay(Rectangle().fill(XFColor.stroke).frame(height: XFStroke.hairline),
                 alignment: .bottom)
    }

    // MARK: - qué sección está activa

    private func isScreen(_ s: AppModel.Screen) -> Bool { model.screen == s }
    private var onHome: Bool { model.screen == .home }
    private var onTrucos: Bool {
        switch model.screen { case .library, .exerciseDetail, .progress: return true; default: return false }
    }
    private var onLibreria: Bool {
        switch model.screen { case .mediaLibrary, .instrumentalEditor, .sampleEditor: return true; default: return false }
    }

    @State private var hovered: String? = nil

    private func navButton(_ title: String, _ symbol: String, active: Bool,
                           _ action: @escaping () -> Void) -> some View {
        let hot = hovered == title
        return Button(action: action) {
            Label(title, systemImage: symbol)
                .font(XFFont.body(12))
                .padding(.horizontal, XFSpacing.xs)
                .padding(.vertical, 5)
                .background(
                    RoundedRectangle(cornerRadius: XFRadius.control, style: .continuous)
                        .fill(active ? XFColor.accent.opacity(0.14)
                              : (hot ? XFColor.surfaceRaised : Color.clear))
                )
                .foregroundColor(active ? XFColor.accent
                                 : (hot ? XFColor.text : XFColor.textMuted))
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 ? title : (hovered == title ? nil : hovered) }
        .animation(.easeOut(duration: 0.12), value: active)
        .animation(.easeOut(duration: 0.12), value: hot)
    }

    @ViewBuilder private var current: some View {
        switch model.screen {
        case .home:
            HomeView(summary: model.home ?? .init(cells: [], streakDays: 0, minutesToday: 0),
                     onContinue: {
                         if let id = model.continueExerciseId { model.startPractice(exerciseId: id) }
                     },
                     onSelect: { model.selectScratch($0) })

        case .library:
            LibraryView(browser: model.library ?? .init(entries: []),
                        onSelect: { model.selectScratch($0) })

        case .mediaLibrary:
            MediaLibraryView(
                instrumentals: model.settings.instrumentalLibrary,
                samples: model.settings.sampleLibrary,
                sampleSlots: model.settings.sampleSlots,
                analysisCache: model.analysisCache,
                sampleRate: model.engine?.sampleRateHz ?? 48_000,
                onInstrumentalsChanged: { model.settings.instrumentalLibrary = $0 },
                onSamplesChanged: { model.settings.sampleLibrary = $0 },
                onSampleSlotsChanged: { model.settings.sampleSlots = $0 },
                onEditInstrumental: { model.openInstrumentalEditor(path: $0) },
                onEditSample: { model.openSampleEditor(path: $0) })

        case .instrumentalEditor(let path):
            InstrumentalEditorView(
                path: path,
                engine: model.engine,
                content: model.content,
                cachedAnalysis: { model.analysisCache.result(for: path, sampleRate: model.engine?.sampleRateHz ?? 48_000) },
                initialEdit: model.instrumentalEdits.edit(for: path),
                onSave: { model.instrumentalEdits.set($0, for: path) },
                onExit: { model.openMediaLibrary() })

        case .sampleEditor(let path):
            SampleEditorView(
                path: path,
                engine: model.engine,
                initialEdit: model.sampleEdits.edit(for: path),
                onSave: { model.sampleEdits.set($0, for: path) },
                onExit: { model.openMediaLibrary() })

        case .exerciseDetail(let scratchId):
            if let d = model.exerciseDetail(scratchId: scratchId) {
                ExerciseDetailView(
                    display: d,
                    onPractice: { exerciseId, variantId in
                        model.startPractice(exerciseId: exerciseId, variantId: variantId)
                    },
                    onBack: { model.openLibrary() })
            } else {
                emptyPanel("No se encuentra el truco \(scratchId).")
            }

        case .myTable:
            MyTableView(table: model.myTable(),
                        onActivate: { model.activeProfileId = $0 },
                        onCalibrate: { _ in model.openCalibration() })

        case .settings:
            SettingsView(settings: model.settings,
                         profileBindings: model.profileCommandBindings,
                         learn: model.midiLearn,
                         onChange: { model.settings = $0 })

        case .progress(let ex, let v):
            if let d = model.progressDisplay(exerciseId: ex, variantId: v) {
                ExerciseProgressView(display: d)
            } else {
                emptyPanel("Sin datos de progreso todavía.")
            }

        case .results:
            if let r = model.lastResults {
                ResultsView(summary: r, onRetry: {
                    if let id = model.continueExerciseId { model.startPractice(exerciseId: id) }
                }, onContinue: { model.goHome() })
            } else {
                emptyPanel("No hay resultados que mostrar.")
            }

        case .calibration:
            // Dispositivos REALES (paso 1): antes los desplegables de
            // Entrada/Salida no recibían ninguna lista y se veían vacíos —
            // "no me deja asignar nada". `AudioDeviceList` es el mismo par de
            // llamadas CoreAudio que ya usa `spike/b1-latency/passthrough
            // --list` (ve la Rane 72 dúplex, 14 in / 10 out); se enumeran al
            // entrar en la pantalla (`.onChange` más abajo), no aquí.
            CalibrationWizardView(
                model: calibrationModel,
                inputDevices: calibrationDevices.filter { $0.inputChannels > 0 },
                outputDevices: calibrationDevices.filter { $0.outputChannels > 0 },
                scopeReadings: { model.scopeReadings },
                onStartFaderLearn: startFaderLearn,
                onFinishFaderLearn: finishFaderLearn,
                onRefreshDevices: refreshCalibrationDevices,
                driftMs: { model.timecodeDriftMs },
                lockedFraction: { model.timecodeLockedFraction },
                ringDropCount: { model.engine?.inputRingDropCount ?? 0 },
                onFinish: { cal in
                    try? model.db.saveCalibration(cal)
                    model.goHome()
                })

        case .practice(let ex, let variant):
            livePractice(exerciseId: ex, variantId: variant)

        case .freeMode:
            // Freestyle: reutiliza la práctica en vivo pero sin fantasma ni
            // "repite conmigo". Cualquier patrón sirve de rejilla base (se toma
            // `baby`, o el primero de la librería): en Freestyle no se sigue.
            if let scratch = model.catalog.library.scratch(id: "baby")
                ?? model.catalog.library.scratches.first {
                LivePracticeView(
                    scratch: scratch,
                    exerciseName: "Freestyle",
                    bpm: 90,
                    // F.73 (ADR-076 iter.) — `curveInset` sube de 8 a 48: con
                    // timecode real el plato puede seguir bajando de n=0
                    // (silencio antes del principio, F.70), y con el margen
                    // mínimo de antes ("pegado al borde") esa bajada
                    // desaparecía por debajo casi al instante — no se veía
                    // en la autopista, aunque el motor la siguiera bien. Más
                    // hueco debajo de la onda del patrón la hace visible
                    // antes de salirse. `laneHeight` NO se toca (es el alto
                    // real del carril de fader, otra cosa).
                    geometry: HighwayGeometry(size: CGSize(width: 1000, height: 380),
                                              laneHeight: 8, curveInset: 48,
                                              patternFill: CGFloat(AudioAsset.scratchPatternTopFraction)),
                    freestyle: true,
                    engine: model.engine,
                    content: model.content,
                    metronomeOn: model.settings.metronomeEnabled,
                    showFPS: model.settings.showFPS,
                    videoFps: model.settings.videoFps,
                    videoLongSide: model.settings.videoLongSide,
                    sampleLibrary: model.settings.sampleLibrary,
                    platterGlideMs: model.settings.platterGlideMs,
                    platterSpeedGate: model.settings.platterSpeedGate,
                    platterFriction: model.settings.platterFriction,
                    trackpadSensitivity: model.settings.trackpadSensitivity,
                    scratchSeekTrimMs: model.settings.scratchSeekTrimMs,
                    scratchSeekMaxTrim: model.settings.scratchSeekMaxTrim,
                    commandEvents: model.practiceCommandEvents.eraseToAnyPublisher(),
                    captureRealTimecode: !model.settings.inputDeviceUID.isEmpty,
                    motionSamples: model.motionSampleEvents.eraseToAnyPublisher(),
                    startRealCapture: { model.startTimecodeCapture() },
                    stopRealCapture: { model.stopTimecodeCapture() },
                    hardwareCrossfader: model.hasHardwareCrossfader,
                    onMetronomeChanged: { model.settings.metronomeEnabled = $0 },
                    onSampleLibraryChanged: { model.settings.sampleLibrary = $0 },
                    cachedAnalysis: { model.analysisCache.result(for: $0, sampleRate: model.engine?.sampleRateHz ?? 48_000) },
                    instrumentalEdit: { model.instrumentalEdits.edit(for: $0) },
                    sampleEdit: { model.sampleEdits.edit(for: $0) },
                    instrumentalLibrary: model.settings.instrumentalLibrary,
                    sampleSlots: model.settings.sampleSlots,
                    onSampleSlotsChanged: { model.settings.sampleSlots = $0 },
                    onExit: { model.goHome() })
            } else {
                emptyPanel("No hay ningún patrón base para la rejilla.")
            }

        case .warmup:
            WarmupView(rows: model.warmup,
                       library: model.warmupLibrary,
                       onStart: { model.startWarmupSession(rows: $0) },
                       onSkip: { model.goHome() })

        case .error(let message):
            emptyPanel("xFlare no ha podido arrancar:\n\(message)")
        }
    }

    /// Practica **rudimentaria**: la autopista corre con su propio reloj musical
    /// y el trackpad / teclado mueven el plato (`PracticeSession`). Todavia **sin
    /// scoring** — eso necesita el callback de audio (B4.2). De momento sirve
    /// para ver el movimiento y probar la entrada.
    @ViewBuilder private func livePractice(exerciseId: String, variantId: String) -> some View {
        let ex = model.catalog.exercise(id: exerciseId)
        let variantName = model.catalog.variant(id: variantId).map { $0.isBase ? "" : " · \($0.name)" } ?? ""
        let name = (ex.flatMap { model.catalog.library.scratch(id: $0.scratchId)?.name } ?? "Práctica") + variantName
        if let scratch = model.scratch(exerciseId: exerciseId, variantId: variantId) {
            LivePracticeView(
                scratch: scratch,
                exerciseName: name,
                bpm: ex?.startBpm ?? 90,
                // `patternFill` = amplitud del movimiento; lo controla el slider
                // "Amplitud" de la vista (por defecto 2/3: el pico del patron a
                // 2/3 del sample).
                // F.73 (ADR-076 iter.) — `curveInset` sube de 8 a 48: con
                // timecode real el plato puede seguir bajando de n=0
                // (silencio antes del principio, F.70), y con el margen
                // mínimo de antes ("pegado al borde inferior") esa bajada
                // desaparecía por debajo casi al instante, aunque el motor
                // la siguiera bien — no se veía en la autopista. Más hueco
                // debajo de la onda del patrón la hace visible antes de
                // salirse. `laneHeight` NO se toca (alto real del carril de
                // fader, otra cosa).
                geometry: HighwayGeometry(size: CGSize(width: 1000, height: 380),
                                          laneHeight: 8, curveInset: 48,
                                          patternFill: CGFloat(AudioAsset.scratchPatternTopFraction)),
                engine: model.engine,
                content: model.content,
                metronomeOn: model.settings.metronomeEnabled,
                scratchSamplePath: model.settings.lastScratchSamplePath,
                showFPS: model.settings.showFPS,
                startInCallResponseBars: model.startCallResponseBars,
                warmupSteps: model.warmupSteps,
                videoFps: model.settings.videoFps,
                videoLongSide: model.settings.videoLongSide,
                sampleLibrary: model.settings.sampleLibrary,
                platterGlideMs: model.settings.platterGlideMs,
                platterSpeedGate: model.settings.platterSpeedGate,
                platterFriction: model.settings.platterFriction,
                trackpadSensitivity: model.settings.trackpadSensitivity,
                scratchSeekTrimMs: model.settings.scratchSeekTrimMs,
                scratchSeekMaxTrim: model.settings.scratchSeekMaxTrim,
                commandEvents: model.practiceCommandEvents.eraseToAnyPublisher(),
                captureRealTimecode: !model.settings.inputDeviceUID.isEmpty,
                motionSamples: model.motionSampleEvents.eraseToAnyPublisher(),
                startRealCapture: { model.startTimecodeCapture() },
                stopRealCapture: { model.stopTimecodeCapture() },
                hardwareCrossfader: model.hasHardwareCrossfader,
                onMetronomeChanged: { model.settings.metronomeEnabled = $0 },
                onScore: { session in
                    model.scoreTake(session, exerciseId: exerciseId, variantId: variantId)
                },
                onWarmupScore: { session, ex, va in
                    model.scoreWarmupTake(session, exerciseId: ex, variantId: va)
                        .map { ($0.stars, $0.accuracyPercent, $0.oxidationMessage) }
                },
                onScratchSampleChanged: { model.settings.lastScratchSamplePath = $0 },
                onSampleLibraryChanged: { model.settings.sampleLibrary = $0 },
                cachedAnalysis: { model.analysisCache.result(for: $0, sampleRate: model.engine?.sampleRateHz ?? 48_000) },
                    instrumentalEdit: { model.instrumentalEdits.edit(for: $0) },
                    sampleEdit: { model.sampleEdits.edit(for: $0) },
                instrumentalLibrary: model.settings.instrumentalLibrary,
                sampleSlots: model.settings.sampleSlots,
                onSampleSlotsChanged: { model.settings.sampleSlots = $0 },
                onExit: { model.goHome() })
        } else {
            emptyPanel("No se encuentra el patrón de \(exerciseId).")
        }
    }

    private func emptyPanel(_ text: String) -> some View {
        VStack {
            Text(text)
                .font(XFFont.body(14)).foregroundColor(XFColor.textMuted)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(XFColor.bg)
    }
}
