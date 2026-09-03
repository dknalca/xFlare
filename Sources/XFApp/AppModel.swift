// SPDX-License-Identifier: GPL-3.0-only

import Foundation
import Combine
import XFNotation
import XFPersistence
import XFProfiles
import XFCapture
import XFAnalysis

/// El coordinador de la app: es dueño del contenido (`Catalog`), la base
/// (`XFDatabase`) y el motor de audio (`EngineHandle`), lleva la navegacion entre
/// pantallas y sirve a cada vista sus datos ya montados con los *assemblers*.
///
/// `ObservableObject` + `@Published` (macOS 11; nada de `@Observable`).
public final class AppModel: ObservableObject {

    public enum Screen: Equatable {
        case home
        case calibration
        /// Ficha de un truco antes de practicarlo: dibujo + historia + variantes.
        case exerciseDetail(scratchId: String)
        case practice(exerciseId: String, variantId: String)
        case results
        case library
        case progress(exerciseId: String, variantId: String)
        case myTable
        case settings
        case freeMode
        /// Calentamiento adaptativo (F.0 / ADR-027).
        case warmup
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
        didSet { Self.persist(settings); rebuildMidiCommandMap() }
    }
    @Published public var activeProfileId: String? {
        didSet { rebuildMidiCommandMap() }
    }

    /// Comandos de práctica que llegan por MIDI (cue, reiniciar base, congelar,
    /// grabar, fader, …). El conector CoreMIDI (hardware) alimenta `midiCommands`
    /// con `ingest`; la práctica se suscribe a este subject.
    public let midiCommands = MidiCommandSource()
    public let practiceCommandEvents = PassthroughSubject<PracticeCommandEvent, Never>()
    /// "MIDI Learn" de Ajustes: escucha CoreMIDI mientras esa pantalla está
    /// abierta y asigna el control que se mueva al comando seleccionado.
    public let midiLearn = MidiLearnModel()
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

        // El decodificador MIDI reenvía cada comando al subject al que se
        // suscribe la práctica.
        self.midiCommands.onCommand = { [weak self] event in
            self?.practiceCommandEvents.send(event)
        }
        // `midiLearn.onLearn` lo cablea `SettingsView` mientras está en pantalla
        // (tiene que actualizar SU copia de los ajustes, no solo la de aquí).
        rebuildMidiCommandMap()
    }

    // MARK: - MIDI de comandos

    /// Reconstruye el mapa MIDI de comandos: base del perfil activo (sección
    /// `[transport]` del `.conf`) + los overrides del usuario por encima. Se
    /// llama al arrancar y cada vez que cambian el perfil o los ajustes.
    func rebuildMidiCommandMap() {
        let base = activeProfileId
            .flatMap { profiles.profile(id: $0)?.raw }
            .map(MidiCommandMap.fromProfile) ?? MidiCommandMap()

        var overrides: [PracticeCommand: MidiBinding] = [:]
        for (key, value) in settings.midiCommandOverrides {
            if let cmd = PracticeCommand(rawValue: key), let bind = MidiBinding(value) {
                overrides[cmd] = bind
            }
        }
        midiCommands.map = base.merging(userOverrides: overrides)
    }

    /// Asignaciones MIDI que trae el perfil activo (`comando -> "note:1:36"`),
    /// para mostrarlas como valor por defecto en Ajustes.
    public var profileCommandBindings: [String: String] {
        guard let ini = activeProfileId.flatMap({ profiles.profile(id: $0)?.raw }) else { return [:] }
        var out: [String: String] = [:]
        for (cmd, bind) in MidiCommandMap.fromProfile(ini).bindings {
            out[cmd.rawValue] = bind.text
        }
        return out
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

    public func goHome()          { warmupSteps = []; refreshHome(); screen = .home }
    public func openCalibration() { screen = .calibration }
    public func openLibrary()     { refreshLibrary(); screen = .library }
    public func openMyTable()     { screen = .myTable }
    public func openSettings()    { screen = .settings }
    public func openFreeMode()    { screen = .freeMode }

    /// Filas del calentamiento de hoy (vacío si no dominas nada todavía).
    /// `internal`: `WarmupRow` no cruza el límite del módulo.
    @Published private(set) var warmup: [WarmupRow] = []

    /// El plan crudo del calentamiento de hoy. Se fija al abrir la pantalla para
    /// que la lista que se ve y la sesión que se lanza usen **las mismas**
    /// variantes al azar (si no, cada llamada a `warmupPlan` sortea otras).
    private var warmupPlanItems: [WarmupPlanner.PlannedItem] = []

    /// Pasos del calentamiento en marcha. Vacío = no estamos calentando. Todo el
    /// calentamiento es UNA sesión: `LivePracticeView` encadena estos pasos
    /// conforme se completan las frases de "repite conmigo".
    /// `internal`: `WarmupStep` no cruza el límite del módulo.
    @Published private(set) var warmupSteps: [WarmupStep] = []

    /// Genera el plan de calentamiento y abre la pantalla.
    public func openWarmup() {
        var rng = SystemRandomNumberGenerator()
        warmupPlanItems = warmupPlan(rng: &rng)
        warmup = WarmupAssembler.rows(from: warmupPlanItems, catalog: catalog)
        screen = .warmup
    }

    /// Monta la tanda entera y abre la práctica en el primer ejercicio con
    /// "repite conmigo" ya en marcha. A partir de ahí `LivePracticeView` avanza
    /// solo: no se vuelve a pasar por aquí hasta el siguiente calentamiento.
    public func startWarmupSession() {
        let items: [WarmupPlanner.PlannedItem]
        if warmupPlanItems.isEmpty {
            var rng = SystemRandomNumberGenerator()
            items = warmupPlan(rng: &rng)
        } else {
            items = warmupPlanItems
        }
        let steps: [WarmupStep] = items.compactMap { item in
            guard let sc = scratch(exerciseId: item.exerciseId, variantId: item.variantId)
            else { return nil }
            let name = catalog.exercise(id: item.exerciseId)
                .flatMap { catalog.library.scratch(id: $0.scratchId)?.name } ?? item.exerciseId
            return WarmupStep(scratch: sc, name: name, phraseCount: item.phraseCount)
        }
        guard let first = items.first, !steps.isEmpty else { goHome(); return }
        warmupSteps = steps
        continueExerciseId = first.exerciseId
        startCallResponseBars = first.phraseBars
        screen = .practice(exerciseId: first.exerciseId, variantId: first.variantId)
    }

    /// Compases de "repite conmigo" con los que arrancar la próxima práctica, o
    /// `nil` para no forzar call-response. Lo pone el calentamiento; la práctica
    /// lo lee al aparecer y `startPractice` lo limpia para la siguiente.
    @Published private(set) var startCallResponseBars: Int?

    public func startPractice(exerciseId: String, variantId: String = "base",
                              callResponseBars: Int? = nil) {
        warmupSteps = []          // una práctica normal no es una tanda de calentamiento
        continueExerciseId = exerciseId
        startCallResponseBars = callResponseBars
        screen = .practice(exerciseId: exerciseId, variantId: variantId)
    }

    public func openProgress(exerciseId: String, variantId: String = "base") {
        screen = .progress(exerciseId: exerciseId, variantId: variantId)
    }

    /// Desde una celda de la matriz o del navegador (recibe `scratchId`): abre la
    /// **ficha** del truco, no la práctica. Desde la ficha se pulsa "Practicar".
    public func selectScratch(_ scratchId: String) {
        // acepta un scratchId real o un id de familia ("flare", "transformer")
        guard catalog.library.scratch(id: scratchId) != nil
                || catalog.family(id: scratchId) != nil else { return }
        screen = .exerciseDetail(scratchId: scratchId)
    }

    // MARK: - datos para las pantallas

    public func refreshHome() {
        home = try? HomeAssembler.summary(
            catalog: catalog, db: db,
            continueExerciseId: continueExerciseId,
            streakDays: currentStreakDays(), minutesToday: minutesPracticedToday(),
            allUnlocked: settings.allUnlocked)
    }

    public func refreshLibrary() {
        library = try? LibraryAssembler.browser(
            catalog: catalog, db: db, allUnlocked: settings.allUnlocked)
    }

    public func variantOptions(exerciseId: String) -> [VariantOption] {
        (try? VariantAssembler.options(catalog: catalog, exerciseId: exerciseId, db: db,
                                       allUnlocked: settings.allUnlocked)) ?? []
    }

    /// Ficha de detalle de un truco para la pantalla `.exerciseDetail`.
    public func exerciseDetail(scratchId: String) -> ExerciseDetailDisplay? {
        (try? ExerciseDetailAssembler.display(catalog: catalog, db: db, scratchId: scratchId,
                                              allUnlocked: settings.allUnlocked)) ?? nil
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

    /// El `Scratch` a practicar, con la **variante** ya aplicada sobre el patrón
    /// base (offset / amplitude / mirror / swing / subdivision). `dropout`
    /// (blind) no toca el patrón: es cosa de la sesión. Si la recomposición
    /// falla (dato malo), se practica la base.
    public func scratch(exerciseId: String, variantId: String = "base") -> Scratch? {
        guard let ex = catalog.exercise(id: exerciseId),
              let base = catalog.library.scratch(id: ex.scratchId) else { return nil }
        guard let v = catalog.variant(id: variantId), !v.isBase else { return base }

        switch v.transform {
        case .identity, .dropout:
            return base
        case .amplitude(let scale):
            return base.withAmplitude(scale: scale)
        case .mirror:
            return base.mirrored()
        case .swing(let ratio):
            return base.withSwing(ratio: ratio, ppq: base.ppq)
        case .subdivision(let div):
            return (try? Composer.composeWithSubdivision(
                base, to: div, ppq: base.ppq, primitives: catalog.primitives)) ?? base
        case .offset(let fraction):
            return (try? Composer.composeWithOffset(
                hand: base.hand, fader: base.fader, division: base.div, cycles: base.cycles,
                fraction: fraction, ppq: base.ppq, primitives: catalog.primitives)) ?? base
        }
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

    // MARK: - puntuar una toma grabada (practica rudimentaria)

    /// Puntua una toma (`.xfsession` grabado en la practica) contra su patron con
    /// `XFAnalysis` y va a la pantalla de resultados con el diagnostico
    /// accionable. **No persiste** ni mueve estrellas / progreso: la practica
    /// rudimentaria todavia no es una sesion de verdad (sin cuenta atras ni
    /// series, eso es XFEngine). Es "enseñar, no puntuar" sin el ciclo completo.
    public func scoreTake(_ session: XFSession, exerciseId: String, variantId: String) {
        guard let scratch = scratch(exerciseId: exerciseId, variantId: variantId) else { return }
        let take = Take(motion: session.motion, fader: session.fader, clock: session.clockMap)
        let takeBpm = Int(session.header.tempoBPM.rounded())
        let atTarget = takeBpm == (catalog.exercise(id: exerciseId)?.startBpm ?? takeBpm)
        let report = DefaultScorer().score(take, against: scratch, atTargetBpm: atTarget)

        lastResults = ResultsSummary.build(report: report, isBestScore: false)
        screen = .results
    }

    // MARK: - calentamiento adaptativo (F.0 / ADR-027)

    /// El plan de calentamiento de hoy: 4-6 ejercicios **dominados**, cada uno
    /// con una variante desbloqueada al azar distinta a la de la última vez.
    /// Puro por debajo (`WarmupPlanner`); aquí solo se leen los datos de la BD.
    func warmupPlan(now: Date = Date(),
                    rng: inout some RandomNumberGenerator) -> [WarmupPlanner.PlannedItem] {
        let mastered = (try? db.masteredExercises()) ?? []
        let candidates: [WarmupPlanner.Candidate] = mastered.compactMap { id in
            guard let ex = catalog.exercise(id: id),
                  let base = catalog.library.scratch(id: ex.scratchId) else { return nil }
            let maxScore = Double(max(1, ScoreEvents(of: base).maxScore))

            let ceiling = ((try? db.progress(exerciseId: id, variantId: "base")) ?? nil)?
                .bestScore.map { Double($0) / maxScore }

            let recent = ((try? db.attempts(exerciseId: id, variantId: "base", limit: 6)) ?? [])
                .filter { $0.countsForStars }
            let recentAvg: Double? = recent.isEmpty ? nil
                : recent.map(\.accuracy).reduce(0, +) / Double(recent.count)

            let lastWarmup = ((try? db.attempts(exerciseId: id, limit: 16)) ?? [])
                .first { $0.mode == .warmup }?.variantId

            let review = (try? db.reviewItem(exerciseId: id, variantId: "base")) ?? nil
            let lastAt = review?.lastReviewedAt
                ?? ((try? db.progress(exerciseId: id, variantId: "base")) ?? nil)?.lastAttemptAt
            let daysSince = lastAt.map { now.timeIntervalSince($0) / 86_400 } ?? 30

            let masteredAt = ((try? db.mastery(exerciseId: id)) ?? nil)?.masteredAt
            let masteryAge = masteredAt.map { now.timeIntervalSince($0) / 86_400 } ?? 30

            let unlocked = Array((try? db.unlockedVariants(exerciseId: id)) ?? ["base"])
            return WarmupPlanner.Candidate(
                exerciseId: id, name: base.name,
                familyId: catalog.family(containingScratch: ex.scratchId)?.id,
                daysSinceReview: daysSince, recentAverage: recentAvg,
                ceiling: ceiling, masteryAgeDays: masteryAge,
                unlockedVariants: unlocked.isEmpty ? ["base"] : unlocked,
                lastWarmupVariant: lastWarmup)
        }
        let adaptive = WarmupPlanner.plan(candidates, rng: &rng)
        // Sin historial (nada dominado): rutina de arranque fija en vez de una
        // pantalla vacía — Forward Cut, Reverse Cut, Chirp, Transformer, cada
        // uno 8 frases de 2 compases (F.0, feedback 2026-09-03).
        return adaptive.isEmpty ? WarmupAssembler.starterPlan(catalog: catalog) : adaptive
    }

    /// Asienta una toma de **calentamiento**: la registra (no cuenta para
    /// estrellas, ADR-027), alimenta la repetición espaciada y, si ha bajado de
    /// 2★, marca el ejercicio **oxidado** y devuelve el aviso para la UI.
    @discardableResult
    func settleWarmupTake(exerciseId: String, variantId: String,
                          score: Int, maxScore: Int, stars: Int,
                          sigmaMs: Double? = nil, biasMs: Double? = nil,
                          at date: Date = Date()) -> String? {
        let name = catalog.exercise(id: exerciseId)
            .flatMap { catalog.library.scratch(id: $0.scratchId)?.name } ?? exerciseId
        let acc = maxScore > 0 ? Double(score) / Double(maxScore) : 0
        let prior = (((try? db.progressSummary(exerciseId: exerciseId, variantId: "base")) ?? nil)?
            .averageOfLast5).map { $0 / Double(max(1, maxScore)) }

        let attempt = Attempt(id: UUID().uuidString, exerciseId: exerciseId,
                              variantId: variantId, mode: .warmup, bpm: 0, startedAt: date,
                              score: score, maxScore: maxScore, accuracy: acc, stars: stars,
                              sigmaMs: sigmaMs, biasMs: biasMs, countsForStars: false)
        try? db.saveAttempt(attempt)
        try? db.recordReviewOutcome(exerciseId: exerciseId, variantId: "base",
                                    passed: stars >= 2, at: date)

        let ox = WarmupOxidation.check(exerciseName: name, starsInWarmup: stars,
                                       accuracy: acc, priorAverage: prior)
        if ox.oxidized { try? db.setOxidized(exerciseId: exerciseId, at: date) }
        refreshHome()
        return ox.message
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
