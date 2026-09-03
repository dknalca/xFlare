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
    }

    private var navBar: some View {
        HStack(spacing: XFSpacing.md) {
            XFWordmark(size: 16)
            Divider().frame(height: 18).background(XFColor.stroke)
            Group {
                navButton("Home", "square.grid.3x3.fill") { model.goHome() }
                navButton("Trucos", "books.vertical") { model.openLibrary() }
                navButton("Librería", "square.stack") { model.openMediaLibrary() }
                navButton("Mi mesa", "pianokeys") { model.openMyTable() }
                navButton("Calentar", "flame") { model.openWarmup() }
                navButton("Freestyle", "waveform.and.mic") { model.openFreeMode() }
                navButton("Ajustes", "slider.horizontal.3") { model.openSettings() }
            }
            Spacer()
            navButton("Calibración", "dot.radiowaves.left.and.right") { model.openCalibration() }
        }
        .padding(.horizontal, XFSpacing.md)
        .padding(.vertical, XFSpacing.xs)
        .background(XFColor.surface)
    }

    private func navButton(_ title: String, _ symbol: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: symbol).font(XFFont.body(12))
        }
        .buttonStyle(.plain)
        .foregroundColor(XFColor.textMuted)
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
                analysisCache: model.analysisCache,
                sampleRate: model.engine?.sampleRateHz ?? 48_000,
                onInstrumentalsChanged: { model.settings.instrumentalLibrary = $0 },
                onSamplesChanged: { model.settings.sampleLibrary = $0 })

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
                        onActivate: { model.activeProfileId = $0 })

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
            CalibrationWizardView(model: CalibrationWizardModel(), onFinish: { cal in
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
