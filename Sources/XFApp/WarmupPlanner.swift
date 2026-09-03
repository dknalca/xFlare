// SPDX-License-Identifier: GPL-3.0-only

import Foundation

/// F.0 / ADR-027 — el **calentamiento adaptativo** (`docs/WARMUP.md`).
///
/// Cinco minutos al empezar repasando lo que YA dominas, con una variante
/// distinta cada día. No es práctica: es despertar la mano y **detectar
/// oxidación**. No penaliza (las estrellas no bajan) pero sí registra
/// (`Attempt.mode == .warmup`, `countsForStars == false`).
///
/// Lógica **pura**: recibe un resumen por ejercicio ya leído de la BD y
/// devuelve el plan. La BD (masterExercises, unlockedVariants, progressSummary,
/// reviewItem, setOxidized, recordReviewOutcome) ya existe en `XFPersistence`
/// desde la v1; aquí solo se decide.
enum WarmupPlanner {

    /// Todo lo que el planificador necesita de UN ejercicio dominado.
    struct Candidate: Equatable {
        var exerciseId: String
        var name: String
        /// Familia (flare / transformer / …) para no sacar cuatro seguidas.
        var familyId: String?
        /// Días desde el último repaso. Mayor = más urgente (repetición
        /// espaciada: 1, 3, 7, 21 días).
        var daysSinceReview: Double
        /// Media reciente de puntuación (`0…1`). `nil` si no hay historial.
        var recentAverage: Double?
        /// Tu techo en este ejercicio (`0…1`), típicamente `bestScore/maxScore`.
        var ceiling: Double?
        /// Antigüedad del dominio, en días. Lo aprendido hace mucho se oxida
        /// distinto (peso bajo).
        var masteryAgeDays: Double
        /// Variantes desbloqueadas (siempre incluye `"base"`).
        var unlockedVariants: [String]
        /// La variante que salió la última vez que se calentó este ejercicio.
        var lastWarmupVariant: String?
    }

    struct PlannedItem: Equatable {
        var exerciseId: String
        var variantId: String
        /// Por qué ha entrado, en una línea ("hace 9 días", "media 84 % / techo 94 %").
        var reason: String
        /// Compases por frase de "repite conmigo" (2 por defecto).
        var phraseBars: Int = 2
        /// Nº de frases a hacer de este ejercicio (8 → 16 compases en total).
        var phraseCount: Int = 8
    }

    /// Rutina de arranque cuando no hay historial: estos scratches, en este
    /// orden, cada uno 8 frases de 2 compases (16 compases). El autor: "los 16
    /// primeros compases serán forward cut, los siguientes 16 reverse cut…".
    static let starterScratchOrder = ["forward-cut", "reverse-cut", "chirp", "transformer-2"]

    // MARK: - plan

    /// Escoge entre `minCount` y `maxCount` ejercicios (4-6 por defecto),
    /// ordenados por urgencia, cada uno con una variante desbloqueada **al azar
    /// distinta de la vez anterior**. Esa aleatoriedad es lo que impide que el
    /// calentamiento se convierta en otro automatismo.
    static func plan(_ candidates: [Candidate],
                     minCount: Int = 4, maxCount: Int = 6,
                     rng: inout some RandomNumberGenerator) -> [PlannedItem] {
        guard !candidates.isEmpty else { return [] }

        var scored = candidates.map { ($0, baseScore($0)) }
        var pickedFamilies: [String: Int] = [:]
        var out: [PlannedItem] = []
        let target = max(minCount, min(maxCount, candidates.count))

        while out.count < target, !scored.isEmpty {
            // penaliza a los de una familia ya elegida (x0,45 por repetición)
            let ranked = scored.map { (c, s) -> (Candidate, Double) in
                let reps = c.familyId.flatMap { pickedFamilies[$0] } ?? 0
                return (c, s * pow(0.45, Double(reps)))
            }.sorted { $0.1 > $1.1 }

            let (chosen, _) = ranked[0]
            out.append(PlannedItem(exerciseId: chosen.exerciseId,
                                   variantId: pickVariant(chosen, rng: &rng),
                                   reason: reason(chosen)))
            if let fam = chosen.familyId { pickedFamilies[fam, default: 0] += 1 }
            scored.removeAll { $0.0.exerciseId == chosen.exerciseId }
        }
        return out
    }

    /// Puntúa un candidato por urgencia (sin la variedad de familia, que se
    /// aplica al seleccionar). Pesos de `docs/WARMUP.md`.
    private static func baseScore(_ c: Candidate) -> Double {
        let spaced = min(1, max(0, c.daysSinceReview) / 21)                 // peso alto
        let falling: Double = {
            guard let avg = c.recentAverage, let ceil = c.ceiling, ceil > 0.01 else { return 0 }
            // caída ABSOLUTA respecto al techo: 20 puntos de bajón = peso pleno.
            return min(1, max(0, (ceil - avg) / 0.20))
        }()
        let aged = min(1, max(0, c.masteryAgeDays) / 180)                   // peso bajo
        return 1.6 * spaced + 1.4 * falling + 0.4 * aged
    }

    private static func reason(_ c: Candidate) -> String {
        if let avg = c.recentAverage, let ceil = c.ceiling, ceil > 0.01,
           ceil - avg >= 0.06 {
            return "media \(pct(avg)) % · techo \(pct(ceil)) %"
        }
        if c.daysSinceReview >= 1 {
            let d = Int(c.daysSinceReview.rounded())
            return "hace \(d) día\(d == 1 ? "" : "s")"
        }
        return "repaso"
    }

    private static func pickVariant(_ c: Candidate,
                                    rng: inout some RandomNumberGenerator) -> String {
        let pool = c.unlockedVariants.filter { $0 != c.lastWarmupVariant }
        return pool.randomElement(using: &rng)
            ?? c.unlockedVariants.first
            ?? "base"
    }

    private static func pct(_ x: Double) -> Int { Int((x * 100).rounded()) }
}

/// Detección de **oxidación** (`docs/WARMUP.md` §5): un ejercicio dominado que
/// baja de 2★ en el calentamiento vuelve a la rotación de práctica, con un aviso
/// amable y concreto. No le quita el dominio.
enum WarmupOxidation {

    struct Result: Equatable {
        var oxidized: Bool
        /// Frase para el usuario. `nil` si no hay oxidación.
        var message: String?
    }

    /// - Parameters:
    ///   - starsInWarmup: estrellas de la toma de calentamiento.
    ///   - accuracy: su precisión `0…1`.
    ///   - priorAverage: la media reciente ANTES de esta toma (`0…1`), para el
    ///     contraste "hoy X %, tu media era Y %".
    static func check(exerciseName name: String, starsInWarmup stars: Int,
                      accuracy: Double, priorAverage: Double?) -> Result {
        guard stars < 2 else { return Result(oxidized: false, message: nil) }
        let hoy = Int((accuracy * 100).rounded())
        if let prev = priorAverage, prev > accuracy + 0.05 {
            let media = Int((prev * 100).rounded())
            return Result(oxidized: true, message:
                "El \(name) se te está cayendo: hoy \(hoy) %, tu media era \(media) %. "
                + "Lo meto de vuelta en la rotación esta semana.")
        }
        return Result(oxidized: true, message:
            "El \(name) hoy se ha quedado en \(hoy) %. Lo devuelvo a la rotación de práctica.")
    }
}

/// Una fila del calentamiento, lista para pintar en `WarmupView`. El usuario
/// puede editarla antes de empezar: borrarla, doblar/partir su duración
/// (`phraseCount`) o añadir filas nuevas desde la librería.
struct WarmupRow: Identifiable, Equatable {
    /// Identidad ESTABLE aunque haya dos filas del mismo ejercicio (se puede
    /// añadir el mismo truco dos veces): se genera al crear la fila.
    let id: String
    let exerciseId: String
    let variantId: String
    let name: String
    /// Nombre de la variante, o `""` si es la base.
    let variantName: String
    /// Por qué ha entrado ("hace 9 días", "media 84 % · techo 94 %").
    let reason: String
    /// Compases por frase de "repite conmigo" y nº de frases.
    var phraseBars: Int = 2
    var phraseCount: Int = 8

    init(id: String = UUID().uuidString,
         exerciseId: String, variantId: String, name: String,
         variantName: String, reason: String,
         phraseBars: Int = 2, phraseCount: Int = 8) {
        self.id = id
        self.exerciseId = exerciseId
        self.variantId = variantId
        self.name = name
        self.variantName = variantName
        self.reason = reason
        self.phraseBars = phraseBars
        self.phraseCount = phraseCount
    }

    /// Total de compases del ejercicio (frases × compases por frase).
    var totalBars: Int { max(1, phraseCount) * max(1, phraseBars) }

    /// "8 frases de 2 compases · 16 en total".
    var phraseSummary: String {
        "\(phraseCount) frases de \(phraseBars) \(phraseBars == 1 ? "compás" : "compases")"
            + " · \(totalBars) en total"
    }
}

/// Un ejercicio de la librería que se puede **añadir** al calentamiento con "+".
struct WarmupPickable: Identifiable, Equatable {
    var id: String { exerciseId }
    let exerciseId: String
    let name: String
    /// Familia (flare / transformer / …), solo para agrupar el menú.
    let familyName: String
}

enum WarmupAssembler {

    /// Traduce un plan (`WarmupPlanner.PlannedItem`) a filas con el nombre del
    /// truco y de la variante resueltos contra el catálogo.
    static func rows(from plan: [WarmupPlanner.PlannedItem], catalog: Catalog) -> [WarmupRow] {
        plan.compactMap { item in
            guard let ex = catalog.exercise(id: item.exerciseId),
                  let sc = catalog.library.scratch(id: ex.scratchId) else { return nil }
            let vName = catalog.variant(id: item.variantId).map { $0.isBase ? "" : $0.name } ?? ""
            // id estable para las filas del plan (una por ejercicio); las que el
            // usuario añada con "+" llevan UUID (puede haber duplicados).
            return WarmupRow(id: item.exerciseId + "/" + item.variantId,
                             exerciseId: item.exerciseId, variantId: item.variantId,
                             name: sc.name, variantName: vName, reason: item.reason,
                             phraseBars: item.phraseBars, phraseCount: item.phraseCount)
        }
    }

    /// Rutina de arranque (sin historial): `WarmupPlanner.starterScratchOrder`
    /// resuelto contra el catálogo, cada uno 8 frases de 2 compases.
    static func starterPlan(catalog: Catalog) -> [WarmupPlanner.PlannedItem] {
        WarmupPlanner.starterScratchOrder.compactMap { scratchId in
            guard let ex = catalog.exercises.first(where: { $0.scratchId == scratchId }) else { return nil }
            return WarmupPlanner.PlannedItem(
                exerciseId: ex.id, variantId: "base",
                reason: "Rutina de arranque", phraseBars: 2, phraseCount: 8)
        }
    }
}
