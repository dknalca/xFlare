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

        // Familias (`data/curriculum/families.json`): opcional. Si falta, no hay
        // agrupación y cada truco sale por su cuenta (como antes).
        let families = (try? JSONDecoder().decode(
            FamiliesDoc.self, from: content.data("data/curriculum/families.json")))?.families ?? []

        // Primitivas (`data/primitives/*.json`): las variantes que recomponen el
        // patrón (offset, subdivision) las necesitan. Si faltan, `PrimitiveSet`
        // lanza y el arranque cae a `.error(...)`.
        let primitives = try PrimitiveSet(
            handPatternsJSON: content.data("data/primitives/hand_patterns.json"),
            faderPatternsJSON: content.data("data/primitives/fader_patterns.json"))

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
                            transform: $0.parsedTransform,
                            requirement: $0.unlock.map {
                                .init(variant: $0.variant, stars: $0.stars)
                            })
            },
            families: families,
            primitives: primitives)
    }

    // MARK: - formas de los JSON (solo para decodificar)

    private struct LevelsDoc: Decodable { let levels: [LevelInfo] }

    private struct FamiliesDoc: Decodable { let families: [FamilyInfo] }

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
        struct Params: Decodable {
            let fraction: Double?
            let scale: Double?
            let ratio: Double?
            let div: String?
        }
        struct Row: Decodable {
            let id: String
            let name: String
            let difficulty: Double
            let transform: String
            let params: Params?
            let unlock: Unlock?

            /// Traduce `transform` + `params` del JSON al enum tipado. Si algún
            /// parámetro falta, cae a un valor neutro (no rompe el arranque).
            var parsedTransform: VariantInfo.Transform {
                switch transform {
                case "offset":      return .offset(fraction: params?.fraction ?? 0)
                case "amplitude":   return .amplitude(scale: params?.scale ?? 1)
                case "mirror":      return .mirror
                case "swing":       return .swing(ratio: params?.ratio ?? 0.5)
                case "subdivision": return .subdivision(div: params?.div ?? "1/8")
                case "dropout":     return .dropout
                default:            return .identity
                }
            }
        }
        let variants: [Row]
    }
}
