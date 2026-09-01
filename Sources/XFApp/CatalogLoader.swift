// SPDX-License-Identifier: GPL-3.0-only

import Foundation
import XFNotation

/// Arma el `Catalog` a partir de un `ContentLoader` (bundle o repo). Se llama una
/// vez al arrancar la app.
public enum CatalogLoader {

    public static func load(from content: ContentLoader) throws -> Catalog {
        let library = try JSONDecoder().decode(
            ScratchLibrary.self, from: content.data("data/scratches/library-v0.1.json"))

        let levelsDoc = try JSONDecoder().decode(
            LevelsDoc.self, from: content.data("data/curriculum/levels.json"))

        let exDoc = try JSONDecoder().decode(
            ExercisesDoc.self, from: content.data("data/curriculum/exercises.json"))

        let varDoc = try JSONDecoder().decode(
            VariantsDoc.self, from: content.data("data/curriculum/variants.json"))

        return Catalog(
            library: library,
            levels: levelsDoc.levels,
            exercises: exDoc.exercises.map {
                ExerciseInfo(id: $0.id, scratchId: $0.scratchId, name: $0.name,
                             level: $0.level, bpmLadder: $0.bpmLadder, startBpm: $0.startBpm,
                             bars: $0.bars, sets: $0.sets)
            },
            variants: varDoc.variants.map {
                VariantInfo(id: $0.id, name: $0.name, difficulty: $0.difficulty,
                            requirement: $0.unlock.map {
                                .init(variant: $0.variant, stars: $0.stars)
                            })
            })
    }

    // MARK: - formas de los JSON (solo para decodificar)

    private struct LevelsDoc: Decodable { let levels: [LevelInfo] }

    private struct ExercisesDoc: Decodable {
        struct Row: Decodable {
            let id: String
            let scratchId: String
            let name: String
            let level: String
            let bpmLadder: [Int]
            let startBpm: Int
            let bars: Int
            let sets: Int
        }
        let exercises: [Row]
    }

    private struct VariantsDoc: Decodable {
        struct Unlock: Decodable { let variant: String; let stars: Int }
        struct Row: Decodable {
            let id: String
            let name: String
            let difficulty: Double
            let unlock: Unlock?
        }
        let variants: [Row]
    }
}
