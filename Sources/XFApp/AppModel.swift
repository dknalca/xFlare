// SPDX-License-Identifier: GPL-3.0-only

import Foundation
import Combine
import XFNotation
import XFPersistence
import XFProfiles

/// El coordinador de la app: es dueño del contenido (`Catalog`), la base
/// (`XFDatabase`) y el motor de audio (`EngineHandle`), lleva la navegacion entre
/// pantallas y sirve a cada vista sus datos ya montados con los *assemblers*.
///
/// `ObservableObject` + `@Published` (macOS 11; nada de `@Observable`).
public final class AppModel: ObservableObject {

    public enum Screen: Equatable {
        case home
        case calibration
        case practice(exerciseId: String, variantId: String)
        case results
        case library
        case progress(exerciseId: String, variantId: String)
        case myTable
        case settings
        case freeMode
        case error(String)
    }

    public let catalog: Catalog
    public let db: XFDatabase
    public let engine: EngineHandle?
    public let profiles: ProfileStore
    /// De donde salen los recursos (repo en dev, bundle en el `.app`). Lo usa la
    /// practica para cargar los audios.
    public let content: ContentLoader

    @Published public private(set) var screen: Screen = .home
    @Published public var settings: AppSettings {
        didSet { Self.persist(settings) }
    }
    @Published public var activeProfileId: String?
    /// Ejercicio en curso para la tarjeta "Continuar" (en memoria por ahora).
    @Published public var continueExerciseId: String?

    // instantaneas para las pantallas
    @Published public private(set) var home: HomeSummary?
    @Published public private(set) var library: LibraryBrowser?
    @Published public private(set) var lastResults: ResultsSummary?

    public init(catalog: Catalog, db: XFDatabase, engine: EngineHandle? = nil,
                profiles: ProfileStore = ProfileStore(bundled: [], user: []),
                settings: AppSettings = .defaults,
                content: ContentLoader = RepoContentLoader()) {
        self.catalog = catalog
        self.db = db
        self.engine = engine
        self.profiles = profiles
        self.settings = settings
        self.content = content
    }

    // MARK: - arranque

    /// Monta el modelo real. En dev lee el contenido del repo; el empaquetado en
    /// el bundle es tarea de B12. Si algo falla, devuelve un modelo en
    /// `.error(...)` para que la ventana al menos abra y lo diga.
    public static func boot(content: ContentLoader = RepoContentLoader(),
                            databaseURL: URL? = nil) -> AppModel {
        do {
            let catalog = try CatalogLoader.load(from: content)
            let url = databaseURL ?? defaultDatabaseURL()
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let db = try XFDatabase(url: url)

            let confs = content.list("profiles", withExtension: "conf")
            let bundled: [(filename: String, text: String)] = confs.compactMap { name in
                guard let data = try? content.data("profiles/\(name)"),
                      let text = String(data: data, encoding: .utf8) else { return nil }
                return (name, text)
            }
            let profiles = ProfileStore(bundled: bundled, user: [])

            // Ajustes: se guardan en un plist local (UserDefaults); ningun dato
            // sale de la maquina. El buffer de audio se fija aqui, al crear el
            // motor (cambiarlo requiere reiniciar).
            let settings = loadSettings()
            let model = AppModel(catalog: catalog, db: db,
                                 engine: EngineHandle(maxFrames: settings.bufferFrames),
                                 profiles: profiles, settings: settings, content: content)
            model.refreshHome()
            return model
        } catch {
            return failed("\(error)")
        }
    }

    public static func failed(_ message: String) -> AppModel {
        let emptyLibrary = ScratchLibrary(schemaVersion: "0", generatedBy: "xFlare",
                                          notation: "XFN", ppq: 480, scratches: [])
        let db = (try? XFDatabase.inMemory()) ?? {
            // .inMemory() no deberia fallar nunca; si lo hace, no hay nada que hacer
            fatalError("no se puede abrir ni una base en memoria")
        }()
        let model = AppModel(
            catalog: Catalog(library: emptyLibrary, levels: [], exercises: [], variants: []),
            db: db)
        model.screen = .error(message)
        return model
    }

    // MARK: - persistencia de ajustes (plist local)

    private static let settingsDefaults = UserDefaults(suiteName: "app.xflare.settings")

    static func loadSettings() -> AppSettings {
        guard let d = settingsDefaults,
              let raw = d.dictionary(forKey: "settings") as? [String: String] else {
            return .defaults
        }
        return AppSettings(raw: raw)
    }

    static func persist(_ s: AppSettings) {
        settingsDefaults?.set(s.raw, forKey: "settings")
    }

    static func defaultDatabaseURL() -> URL {
        let base = (try? FileManager.default.url(for: .applicationSupportDirectory,
                                                 in: .userDomainMask, appropriateFor: nil, create: true))
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("xFlare/xflare.sqlite")
    }

    // MARK: - navegacion

    public func goHome()          { refreshHome(); screen = .home }
    public func openCalibration() { screen = .calibration }
    public func openLibrary()     { refreshLibrary(); screen = .library }
    public func openMyTable()     { screen = .myTable }
    public func openSettings()    { screen = .settings }
    public func openFreeMode()    { screen = .freeMode }

    public func startPractice(exerciseId: String, variantId: String = "base") {
        continueExerciseId = exerciseId
        screen = .practice(exerciseId: exerciseId, variantId: variantId)
    }

    public func openProgress(exerciseId: String, variantId: String = "base") {
        screen = .progress(exerciseId: exerciseId, variantId: variantId)
    }

    /// Desde una celda de la matriz o del navegador (recibe `scratchId`).
    public func selectScratch(_ scratchId: String) {
        guard let ex = catalog.exercise(forScratch: scratchId) else { return }
        startPractice(exerciseId: ex.id)
    }

    // MARK: - datos para las pantallas

    public func refreshHome() {
        home = try? HomeAssembler.summary(
            catalog: catalog, db: db,
            continueExerciseId: continueExerciseId,
            streakDays: currentStreakDays(), minutesToday: minutesPracticedToday())
    }

    public func refreshLibrary() {
        library = try? LibraryAssembler.browser(catalog: catalog, db: db)
    }

    public func variantOptions(exerciseId: String) -> [VariantOption] {
        (try? VariantAssembler.options(catalog: catalog, exerciseId: exerciseId, db: db)) ?? []
    }

    public func progressDisplay(exerciseId: String, variantId: String) -> ExerciseProgressDisplay? {
        guard let s = try? db.progressSummary(exerciseId: exerciseId, variantId: variantId) else {
            return nil
        }
        return ExerciseProgressDisplay.build(s)
    }

    public func myTable() -> MyTable {
        let rows = profiles.entries.values.compactMap { entry -> (profile: DeviceProfile, isUser: Bool)? in
            guard !entry.isExample, let p = entry.profile else { return nil }
            return (p, entry.origin == .user)
        }
        let cals = (try? db.allCalibrations()) ?? []
        return MyTableAssembler.table(profiles: rows, calibrations: cals,
                                      activeProfileId: activeProfileId)
    }

    /// El `Scratch` a practicar. Por ahora la variante base; las variantes
    /// (offset/amplitude/mirror…) se recomponen cuando se cablee el `Composer`.
    public func scratch(exerciseId: String) -> Scratch? {
        guard let ex = catalog.exercise(id: exerciseId) else { return nil }
        return catalog.library.scratch(id: ex.scratchId)
    }

    // MARK: - resultado de una practica

    /// Asienta una toma (persistencia + progreso + desbloqueos) y va a la
    /// pantalla de resultados.
    public func finishPractice(attempt: Attempt, events: [AttemptEvent],
                               starReasons: [String], diagnostics: [String]) {
        let previousBest = (try? db.progress(exerciseId: attempt.exerciseId,
                                             variantId: attempt.variantId)?.bestScore) ?? nil
        _ = try? AttemptRecorder.record(attempt, events: events, db: db, catalog: catalog)

        lastResults = ResultsSummary.build(
            score: attempt.score, maxScore: attempt.maxScore, starCount: attempt.stars,
            starReasons: starReasons, diagnostics: diagnostics,
            isBestScore: attempt.score > (previousBest ?? -1))
        refreshHome()
        screen = .results
    }

    // MARK: - racha / minutos (desde los intentos guardados)

    private func allAttemptDates() -> [Date] {
        catalog.exercises.flatMap { (try? db.attempts(exerciseId: $0.id)) ?? [] }
            .map(\.startedAt)
    }

    public func currentStreakDays() -> Int {
        PracticeStreak.currentStreak(practiceDates: allAttemptDates())
    }

    public func minutesPracticedToday() -> Int {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let ms = catalog.exercises
            .flatMap { (try? db.attempts(exerciseId: $0.id)) ?? [] }
            .filter { cal.isDate($0.startedAt, inSameDayAs: today) }
            .compactMap(\.durationMs)
            .reduce(0, +)
        return Int(ms / 60_000)
    }
}
