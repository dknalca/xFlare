// SPDX-License-Identifier: GPL-3.0-only

import Foundation
import XFPersistence
import XFProfiles

/// Reglas para saber que niveles / scratches estan disponibles. Puro: se le pasa
/// una funcion `stars(exerciseId)` con las estrellas de la variante base.
public enum LevelGate {

    /// Un nivel esta abierto si es el primero, o si **todos** los ejercicios del
    /// nivel anterior tienen al menos 1 estrella en la base. `allUnlocked` abre
    /// todos (provisional, `AppSettings.allUnlocked`).
    public static func unlockedLevels(catalog: Catalog, allUnlocked: Bool = false,
                                      stars: (String) -> Int) -> Set<String> {
        if allUnlocked { return Set(catalog.levels.map(\.id)) }
        var open: Set<String> = []
        var previousCleared = true
        for level in catalog.levels {
            if previousCleared { open.insert(level.id) }
            let exs = catalog.exercises.filter { $0.level == level.id }
            previousCleared = !exs.isEmpty && exs.allSatisfy { stars($0.id) >= 1 }
        }
        return open
    }

    /// Ids de scratch disponibles para practicar (los de un nivel abierto).
    public static func availableScratchIds(catalog: Catalog, allUnlocked: Bool = false,
                                           stars: (String) -> Int) -> Set<String> {
        let levels = unlockedLevels(catalog: catalog, allUnlocked: allUnlocked, stars: stars)
        return Set(catalog.exercises.filter { levels.contains($0.level) }.map(\.scratchId))
    }
}

// MARK: - Home

public enum HomeAssembler {

    /// Arma el `HomeSummary` leyendo el estado guardado de cada ejercicio.
    public static func summary(catalog: Catalog, db: XFDatabase,
                               continueExerciseId: String? = nil,
                               streakDays: Int = 0, minutesToday: Int = 0,
                               allUnlocked: Bool = false) throws -> HomeSummary {

        // estrellas de la base por ejercicio (una sola pasada)
        var starsByExercise: [String: Int] = [:]
        for ex in catalog.exercises {
            starsByExercise[ex.id] = try db.progress(exerciseId: ex.id, variantId: "base")?.stars ?? 0
        }
        let openLevels = LevelGate.unlockedLevels(catalog: catalog, allUnlocked: allUnlocked) {
            starsByExercise[$0] ?? 0
        }

        var cells: [MatrixCell] = []
        for ex in catalog.exercises {
            let base = try db.progress(exerciseId: ex.id, variantId: "base")
            let mastery = try db.mastery(exerciseId: ex.id)
            let name = catalog.library.scratch(id: ex.scratchId)?.name ?? ex.name
            cells.append(MatrixCell.build(
                scratchId: ex.scratchId, name: name, level: ex.level,
                baseUnlocked: openLevels.contains(ex.level),
                baseProgress: base, mastery: mastery))
        }

        var target: HomeSummary.ContinueTarget?
        if let id = continueExerciseId, let ex = catalog.exercise(id: id) {
            let name = catalog.library.scratch(id: ex.scratchId)?.name ?? ex.name
            let bpm = try db.progress(exerciseId: ex.id, variantId: "base")?.bestBpmWith3Stars
                ?? ex.startBpm
            target = .init(scratchId: ex.scratchId, name: name, bpm: bpm)
        }

        // Miniatura TTM en TODOS los scratches del currículo (barato: build es
        // puro y son ~25). Antes solo L1.
        var thumbnails: [String: TTMThumbnail] = [:]
        for ex in catalog.exercises {
            if thumbnails[ex.scratchId] == nil,
               let s = catalog.library.scratch(id: ex.scratchId) {
                thumbnails[ex.scratchId] = TTMThumbnail.build(scratch: s)
            }
        }

        return HomeSummary(cells: cells, streakDays: streakDays,
                           minutesToday: minutesToday, continueTarget: target,
                           thumbnails: thumbnails)
    }
}

// MARK: - Libreria

public enum LibraryAssembler {

    /// Trucos que NO se listan en la librería porque no son un truco distinto,
    /// solo una variante del mismo: colocación del click (lo-/hi-flare) o cambio
    /// de subdivisión (los `-16`). El truco de verdad (`flare-1c`, `baby`,
    /// `flare-2c`) sí está. Siguen en el currículo. Ver `docs/MATRIX_MAPPING.md`.
    static let hiddenInLibrary: Set<String> = [
        "flare-1c-lo", "flare-1c-hi",
        "baby-16", "flare-2c-16",
    ]

    public static func browser(catalog: Catalog, db: XFDatabase,
                               allUnlocked: Bool = false) throws -> LibraryBrowser {
        var starsByExercise: [String: Int] = [:]
        for ex in catalog.exercises {
            starsByExercise[ex.id] = try db.progress(exerciseId: ex.id, variantId: "base")?.stars ?? 0
        }
        let available = LevelGate.availableScratchIds(catalog: catalog, allUnlocked: allUnlocked) {
            starsByExercise[$0] ?? 0
        }

        // Nivel del CURRICULO (no el del scratch): asi el crab, que en la libreria
        // es nivel 6, sale en el nivel donde de verdad se practica (L4).
        func curriculumLevel(_ scratchId: String) -> Int? {
            guard let raw = catalog.exercise(forScratch: scratchId)?.level else { return nil }
            return Int(raw.drop(while: { !$0.isNumber }))
        }

        let entries = catalog.library.scratches
            .filter { !hiddenInLibrary.contains($0.id) }
            .map { s in
                LibraryEntry(scratch: s, isUnlocked: available.contains(s.id),
                             level: curriculumLevel(s.id))
            }
        return LibraryBrowser(entries: entries)
    }
}

// MARK: - Ventana de detalle de un truco

public enum ExerciseDetailAssembler {

    /// Arma la ventana de detalle de `scratchId`: dibujo TTM + descripción +
    /// historia, y la lista de variantes con las estrellas / mejor marca que se
    /// llevan sacadas. `nil` si el scratch no existe en la librería.
    public static func display(catalog: Catalog, db: XFDatabase, scratchId: String,
                               allUnlocked: Bool = false) throws -> ExerciseDetailDisplay? {
        guard let scratch = catalog.library.scratch(id: scratchId) else { return nil }
        let ex = catalog.exercise(forScratch: scratchId)

        // Nivel del CURRÍCULO (donde se practica), no el del scratch.
        let level: Int? = ex.flatMap { Int($0.level.drop(while: { !$0.isNumber })) }

        var rows: [ExerciseDetailDisplay.VariantRow] = []
        if let ex {
            let options = try VariantAssembler.options(
                catalog: catalog, exerciseId: ex.id, db: db, allUnlocked: allUnlocked)
            for opt in options {
                let p = try db.progress(exerciseId: ex.id, variantId: opt.variantId)
                rows.append(.init(
                    option: opt,
                    stars: p?.stars ?? 0,
                    bestScore: p?.bestScore.map(ExerciseProgressDisplay.grouped) ?? "—",
                    attempts: p?.attempts ?? 0))
            }
        }

        return ExerciseDetailDisplay(
            scratchId: scratch.id,
            name: scratch.name,
            family: scratch.family,
            level: level,
            technique: scratch.technique,
            description: ScratchLore.description(for: scratch),
            history: ScratchLore.history(for: scratch),
            thumbnail: TTMThumbnail.build(scratch: scratch),
            exerciseId: ex?.id,
            variants: rows)
    }
}

// MARK: - Selector de variantes

public enum VariantAssembler {

    /// Opciones de variante de un ejercicio, con la condicion de desbloqueo
    /// escrita, a partir de las estrellas guardadas.
    public static func options(catalog: Catalog, exerciseId: String, db: XFDatabase,
                               allUnlocked: Bool = false) throws -> [VariantOption] {
        var starsByVariant: [String: Int] = [:]
        for v in catalog.variants {
            starsByVariant[v.id] = try db.progress(exerciseId: exerciseId, variantId: v.id)?.stars ?? 0
        }
        return catalog.variants.map { v in
            if allUnlocked {
                return VariantOption(variantId: v.id, name: v.name,
                                     difficulty: v.difficulty, lock: .unlocked)
            }
            return VariantOption.build(
                variantId: v.id, name: v.name, difficulty: v.difficulty,
                requires: v.requirement.map { ($0.variant, $0.stars) },
                starsInRequired: v.requirement.map { starsByVariant[$0.variant] ?? 0 } ?? 0,
                requiredVariantName: v.requirement.flatMap { req in
                    catalog.variant(id: req.variant)?.name
                } ?? "")
        }
    }
}

// MARK: - Mi mesa

public enum MyTableAssembler {

    public static func table(profiles: [(profile: DeviceProfile, isUser: Bool)],
                             calibrations: [DeviceCalibration],
                             activeProfileId: String?) -> MyTable {
        let calByProfile = Dictionary(grouping: calibrations, by: \.profileId)
        let rows = profiles.map { entry -> MyTableRow in
            let cals = calByProfile[entry.profile.id] ?? []
            return MyTableRow(
                profileId: entry.profile.id,
                name: entry.profile.name,
                source: entry.isUser ? .user : .bundled,
                verified: entry.profile.verified,
                hasCalibration: !cals.isEmpty,
                latencyMs: cals.compactMap(\.latencyMs).min())
        }
        return MyTable(rows: rows, activeProfileId: activeProfileId)
    }
}
