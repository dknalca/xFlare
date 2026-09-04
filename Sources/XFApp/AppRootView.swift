// SPDX-License-Identifier: GPL-3.0-only

import SwiftUI
import Combine
import XFDesign
import XFRender
import XFNotation

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
                // Paso 2 (Latencia, F.63): declarada por el driver, no medida
                // por loopback — no hace falta cable. Suma el lado de salida
                // y, si hay uno elegido, el de entrada; usa el dispositivo de
                // Ajustes › Hardware o el de sistema por defecto si no hay
                // ninguno elegido (mismo criterio que usaría el motor).
                if let out = AudioDeviceList.resolvedOutput(uid: model.settings.outputDeviceUID,
                                                            in: calibrationDevices),
                   let outInfo = AudioDeviceLatency.outputInfo(for: out) {
                    var totalMs = outInfo.totalMs
                    if let inp = AudioDeviceList.resolvedInput(uid: model.settings.inputDeviceUID,
                                                               in: calibrationDevices),
                       let inInfo = AudioDeviceLatency.inputInfo(for: inp) {
                        totalMs += inInfo.totalMs
                    }
                    calibrationModel.reportLatency(ms: totalMs)
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
                model.startTimecodeCapture()
                capturingTimecode = true
            } else if capturingTimecode {
                // SOLO al salir de Calibración habiendo capturado de verdad —
                // si no, cualquier cambio de pantalla reiniciaría el motor.
                model.onTimecodeSample = nil
                model.stopTimecodeCapture()
                capturingTimecode = false
            }
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
                inputDevices: calibrationDevices.filter { $0.inputChannels > 0 }.map(\.name),
                outputDevices: calibrationDevices.filter { $0.outputChannels > 0 }.map(\.name),
                scopeReadings: { model.scopeReadings },
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
                    geometry: HighwayGeometry(size: CGSize(width: 1000, height: 380),
                                              laneHeight: 8, curveInset: 8,
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
                    commandEvents: model.practiceCommandEvents.eraseToAnyPublisher(),
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
                // 2/3 del sample). Margenes minimos para que el movimiento
                // arranque casi pegado al borde inferior, como el rail del sample.
                geometry: HighwayGeometry(size: CGSize(width: 1000, height: 380),
                                          laneHeight: 8, curveInset: 8,
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
                commandEvents: model.practiceCommandEvents.eraseToAnyPublisher(),
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
