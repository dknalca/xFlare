// SPDX-License-Identifier: GPL-3.0-only

import Foundation
import XFPersistence
import XFProfiles

/// Reglas para saber que niveles / scratches estan disponibles. Puro: se le pasa
/// una funcion `stars(exerciseId)` con las estrellas de la variante base.
public enum LevelGate {

    /// Un nivel esta abierto si es el primero, o si **todos** los ejercicios del
    /// nivel anterior tienen al menos 1 estrella en la base.
    public static func unlockedLevels(catalog: Catalog,
                                      stars: (String) -> Int) -> Set<String> {
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
    public static func availableScratchIds(catalog: Catalog,
                                           stars: (String) -> Int) -> Set<String> {
        let levels = unlockedLevels(catalog: catalog, stars: stars)
        return Set(catalog.exercises.filter { levels.contains($0.level) }.map(\.scratchId))
    }
}

// MARK: - Home

public enum HomeAssembler {

    /// Arma el `HomeSummary` leyendo el estado guardado de cada ejercicio.
    public static func summary(catalog: Catalog, db: XFDatabase,
                               continueExerciseId: String? = nil,
                               streakDays: Int = 0, minutesToday: Int = 0) throws -> HomeSummary {

        // estrellas de la base por ejercicio (una sola pasada)
        var starsByExercise: [String: Int] = [:]
        for ex in catalog.exercises {
            starsByExercise[ex.id] = try db.progress(exerciseId: ex.id, variantId: "base")?.stars ?? 0
        }
        let openLevels = LevelGate.unlockedLevels(catalog: catalog) { starsByExercise[$0] ?? 0 }

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

        // Miniatura TTM en todos los scratches del primer nivel (L1).
        var thumbnails: [String: TTMThumbnail] = [:]
        if let firstLevel = catalog.levels.sorted(by: { $0.id < $1.id }).first {
            for scratchId in firstLevel.scratches {
                if let s = catalog.library.scratch(id: scratchId) {
                    thumbnails[scratchId] = TTMThumbnail.build(scratch: s)
                }
            }
        }

        return HomeSummary(cells: cells, streakDays: streakDays,
                           minutesToday: minutesToday, continueTarget: target,
                           thumbnails: thumbnails)
    }
}

// MARK: - Libreria

public enum LibraryAssembler {

    public static func browser(catalog: Catalog, db: XFDatabase) throws -> LibraryBrowser {
        var starsByExercise: [String: Int] = [:]
        for ex in catalog.exercises {
            starsByExercise[ex.id] = try db.progress(exerciseId: ex.id, variantId: "base")?.stars ?? 0
        }
        let available = LevelGate.availableScratchIds(catalog: catalog) { starsByExercise[$0] ?? 0 }

        // Nivel del CURRICULO (no el del scratch): asi el crab, que en la libreria
        // es nivel 6, sale en el nivel donde de verdad se practica (L4).
        func curriculumLevel(_ scratchId: String) -> Int? {
            guard let raw = catalog.exercise(forScratch: scratchId)?.level else { return nil }
            return Int(raw.drop(while: { !$0.isNumber }))
        }

        let entries = catalog.library.scratches.map { s in
            LibraryEntry(scratch: s, isUnlocked: available.contains(s.id),
                         level: curriculumLevel(s.id))
        }
        return LibraryBrowser(entries: entries)
    }
}

// MARK: - Selector de variantes

public enum VariantAssembler {

    /// Opciones de variante de un ejercicio, con la condicion de desbloqueo
    /// escrita, a partir de las estrellas guardadas.
    public static func options(catalog: Catalog, exerciseId: String,
                               db: XFDatabase) throws -> [VariantOption] {
        var starsByVariant: [String: Int] = [:]
        for v in catalog.variants {
            starsByVariant[v.id] = try db.progress(exerciseId: exerciseId, variantId: v.id)?.stars ?? 0
        }
        return catalog.variants.map { v in
            VariantOption.build(
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
