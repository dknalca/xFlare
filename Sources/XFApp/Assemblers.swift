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
        var seenFamilies: Set<String> = []
        for ex in catalog.exercises {
            // los miembros de una familia (Flare, Transformer) colapsan a UNA
            // celda; el estado es el agregado de los miembros.
            if let fam = catalog.family(containingScratch: ex.scratchId) {
                guard seenFamilies.insert(fam.id).inserted else { continue }
                cells.append(try familyCell(fam, catalog: catalog, db: db,
                                            baseUnlocked: openLevels.contains(fam.level)))
                continue
            }
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
        // puro y son ~25). Antes solo L1. Para una celda de familia se usa la
        // miniatura de su primer miembro.
        var thumbnails: [String: TTMThumbnail] = [:]
        for ex in catalog.exercises {
            if thumbnails[ex.scratchId] == nil,
               let s = catalog.library.scratch(id: ex.scratchId) {
                thumbnails[ex.scratchId] = TTMThumbnail.build(scratch: s)
            }
        }
        for fam in catalog.families {
            if let first = fam.members.first, let t = thumbnails[first] {
                thumbnails[fam.id] = t
            }
        }

        return HomeSummary(cells: cells, streakDays: streakDays,
                           minutesToday: minutesToday, continueTarget: target,
                           thumbnails: thumbnails)
    }

    /// Celda agregada de una familia: bloqueada si su nivel no está abierto;
    /// dominada si TODOS sus miembros lo están; practicada con el máximo de
    /// estrellas de un miembro si alguno tiene marca; disponible si no.
    private static func familyCell(_ fam: FamilyInfo, catalog: Catalog, db: XFDatabase,
                                   baseUnlocked: Bool) throws -> MatrixCell {
        var maxStars = 0
        var allMastered = !fam.members.isEmpty
        var any = false
        for scratchId in fam.members {
            guard let ex = catalog.exercise(forScratch: scratchId) else { allMastered = false; continue }
            let stars = try db.progress(exerciseId: ex.id, variantId: "base")?.stars ?? 0
            maxStars = max(maxStars, stars)
            if stars > 0 { any = true }
            if try db.mastery(exerciseId: ex.id)?.isMastered != true { allMastered = false }
        }
        let state: MatrixCell.State
        if !baseUnlocked        { state = .locked }
        else if allMastered     { state = .mastered }
        else if any             { state = .practiced(stars: min(2, maxStars)) }
        else                    { state = .available }
        return MatrixCell(scratchId: fam.id, name: fam.name, level: fam.level,
                          state: state, isFamily: true)
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

        // Los miembros de una familia no salen sueltos: en su lugar, una entrada
        // por familia que abre la ficha con todos los miembros.
        let members = catalog.familyMemberScratchIds
        let loose = catalog.library.scratches
            .filter { !hiddenInLibrary.contains($0.id) && !members.contains($0.id) }
            .map { s in
                LibraryEntry(scratch: s, isUnlocked: available.contains(s.id),
                             level: curriculumLevel(s.id))
            }
        let familyEntries: [LibraryEntry] = catalog.families.map { fam in
            let lvl = Int(fam.level.drop(while: { !$0.isNumber })) ?? 99
            let thumb = fam.members.first
                .flatMap { catalog.library.scratch(id: $0) }
                .map { TTMThumbnail.build(scratch: $0) }
            return LibraryEntry(
                scratchId: fam.id, name: fam.name, family: fam.name, level: lvl,
                technique: "familia", clickCount: 0, lengthTicks: 0,
                isUnlocked: fam.members.contains { available.contains($0) },
                thumbnail: thumb)
        }
        return LibraryBrowser(entries: loose + familyEntries)
    }
}

// MARK: - Ventana de detalle de un truco

public enum ExerciseDetailAssembler {

    /// Arma la ventana de detalle de `scratchId`: dibujo TTM + descripción +
    /// historia, y la lista de variantes con las estrellas / mejor marca que se
    /// llevan sacadas. `nil` si el scratch no existe en la librería.
    public static func display(catalog: Catalog, db: XFDatabase, scratchId: String,
                               allUnlocked: Bool = false) throws -> ExerciseDetailDisplay? {
        // ¿es una familia (Flare, Transformer)? -> ficha con miembros.
        if let fam = catalog.family(id: scratchId) {
            return try familyDisplay(fam, catalog: catalog, db: db, allUnlocked: allUnlocked)
        }

        guard let scratch = catalog.library.scratch(id: scratchId) else { return nil }
        let ex = catalog.exercise(forScratch: scratchId)

        // Nivel del CURRÍCULO (donde se practica), no el del scratch.
        let level: Int? = ex.flatMap { Int($0.level.drop(while: { !$0.isNumber })) }

        // Variantes DESACTIVADAS de momento (feedback 2026-09-02): la ficha solo
        // ofrece "Practicar" (base). `variantRows` sigue por si se reactivan.
        let rows: [ExerciseDetailDisplay.VariantRow] = []
        _ = allUnlocked

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

    /// Ficha de una familia: blurb + historia de la familia y un bloque por
    /// miembro (dibujo + su ejercicio para "Practicar"). Sin variantes de momento.
    private static func familyDisplay(_ fam: FamilyInfo, catalog: Catalog, db: XFDatabase,
                                      allUnlocked: Bool) throws -> ExerciseDetailDisplay {
        _ = (db, allUnlocked)
        let members: [ExerciseDetailDisplay.MemberBlock] = fam.members.compactMap { scratchId in
            guard let s = catalog.library.scratch(id: scratchId) else { return nil }
            let ex = catalog.exercise(forScratch: scratchId)
            return .init(scratchId: s.id, name: s.name,
                         thumbnail: TTMThumbnail.build(scratch: s),
                         exerciseId: ex?.id, variants: [])
        }
        return ExerciseDetailDisplay(
            scratchId: fam.id, name: fam.name, family: fam.name,
            level: Int(fam.level.drop(while: { !$0.isNumber })),
            technique: "", description: fam.blurb, history: fam.history,
            thumbnail: nil, exerciseId: nil, variants: [], members: members)
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
