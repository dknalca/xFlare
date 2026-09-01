// SPDX-License-Identifier: GPL-3.0-only

import SwiftUI
import XFDesign
import XFRender
import XFNotation

/// La vista raiz de xFlare: barra de navegacion + la pantalla actual segun
/// `AppModel.screen`. Sustituye a la maqueta inerte `HomeScaffoldView`.
public struct AppRootView: View {

    @ObservedObject private var model: AppModel

    public init(model: AppModel) {
        self.model = model
    }

    public var body: some View {
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
            navButton("Home", "square.grid.3x3.fill") { model.goHome() }
            navButton("Librería", "books.vertical") { model.openLibrary() }
            navButton("Mi mesa", "pianokeys") { model.openMyTable() }
            navButton("Ajustes", "slider.horizontal.3") { model.openSettings() }
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

        case .myTable:
            MyTableView(table: model.myTable(),
                        onActivate: { model.activeProfileId = $0 })

        case .settings:
            SettingsView(settings: model.settings, onChange: { model.settings = $0 })

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

        case .practice(let ex, _):
            livePractice(exerciseId: ex)

        case .freeMode:
            if let scratch = model.continueExerciseId.flatMap(model.scratch(exerciseId:)) {
                FreeModeView(scratch: scratch,
                             highwayGeometry: HighwayGeometry(size: CGSize(width: 1000, height: 380)),
                             tick: { [weak model] in model?.engine?.tick ?? 0 },
                             onExit: { model.goHome() })
            } else {
                emptyPanel("Elige un scratch primero.")
            }

        case .error(let message):
            emptyPanel("xFlare no ha podido arrancar:\n\(message)")
        }
    }

    /// Practica **rudimentaria**: la autopista corre con su propio reloj musical
    /// y el trackpad / teclado mueven el plato (`PracticeSession`). Todavia **sin
    /// scoring** — eso necesita el callback de audio (B4.2). De momento sirve
    /// para ver el movimiento y probar la entrada.
    @ViewBuilder private func livePractice(exerciseId: String) -> some View {
        let ex = model.catalog.exercise(id: exerciseId)
        let name = ex.flatMap { model.catalog.library.scratch(id: $0.scratchId)?.name } ?? "Práctica"
        if let scratch = model.scratch(exerciseId: exerciseId) {
            LivePracticeView(
                scratch: scratch,
                exerciseName: name,
                bpm: ex?.startBpm ?? 90,
                geometry: HighwayGeometry(size: CGSize(width: 1000, height: 380)),
                engine: model.engine,
                content: model.content,
                metronomeOn: model.settings.metronomeEnabled,
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
