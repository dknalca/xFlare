// SPDX-License-Identifier: GPL-3.0-only

import Foundation
import XFNotation

/// El contenido de solo lectura del producto ya cargado: la libreria de
/// scratches, los niveles del curriculo, los ejercicios y las variantes. Value
/// type; lo arma `CatalogLoader` una vez al arrancar.
public struct Catalog: Sendable {

    public var library: ScratchLibrary
    public var levels: [LevelInfo]
    public var exercises: [ExerciseInfo]
    public var variants: [VariantInfo]
    /// Primitivas de composición (`data/primitives/*.json`). Las necesitan las
    /// variantes que recomponen el patrón (`offset`, `subdivision`).
    public var primitives: PrimitiveSet

    public init(library: ScratchLibrary, levels: [LevelInfo],
                exercises: [ExerciseInfo], variants: [VariantInfo],
                primitives: PrimitiveSet = PrimitiveSet(handPatterns: [:], faderPatterns: [:])) {
        self.library = library
        self.levels = levels
        self.exercises = exercises
        self.variants = variants
        self.primitives = primitives
    }

    /// El ejercicio cuyo `scratchId` coincide, o `nil`.
    public func exercise(forScratch scratchId: String) -> ExerciseInfo? {
        exercises.first { $0.scratchId == scratchId }
    }

    public func exercise(id: String) -> ExerciseInfo? {
        exercises.first { $0.id == id }
    }

    public func variant(id: String) -> VariantInfo? {
        variants.first { $0.id == id }
    }
}

/// Un nivel de `data/curriculum/levels.json`.
public struct LevelInfo: Sendable, Codable, Equatable {
    public let id: String            // "L1"…"L6"
    public let name: String
    public let scratches: [String]
}

/// Un ejercicio de `data/curriculum/exercises.json`.
public struct ExerciseInfo: Sendable, Equatable {
    public let id: String            // "ex-l1-baby"
    public let scratchId: String     // "baby"
    public let name: String
    public let level: String         // "L1"
    public let bpmLadder: [Int]
    public let startBpm: Int
    public let bars: Int
    public let sets: Int
}

/// Una variante de `data/curriculum/variants.json`.
public struct VariantInfo: Sendable, Equatable, Identifiable {
    public struct Requirement: Sendable, Equatable {
        public let variant: String
        public let stars: Int
    }
    /// Qué transformación aplica sobre el patrón base (docs/VARIANTS.md §3).
    /// `dropout` no transforma el patrón (es lógica de sesión): aquí es identidad.
    public enum Transform: Sendable, Equatable {
        case identity
        case offset(fraction: Double)
        case amplitude(scale: Double)
        case mirror
        case swing(ratio: Double)
        case subdivision(div: String)
        case dropout
    }
    public let id: String
    public let name: String
    public let difficulty: Double
    public let transform: Transform
    /// Condicion de desbloqueo, o `nil` para las variantes de entrada.
    public let requirement: Requirement?

    public var isBase: Bool { id == "base" }

    public init(id: String, name: String, difficulty: Double,
                transform: Transform = .identity, requirement: Requirement? = nil) {
        self.id = id
        self.name = name
        self.difficulty = difficulty
        self.transform = transform
        self.requirement = requirement
    }
}
