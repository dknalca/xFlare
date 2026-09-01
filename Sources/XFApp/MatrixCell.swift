// SPDX-License-Identifier: GPL-3.0-only

import XFPersistence

/// Una celda de la rejilla de la matriz del Home (`docs/UI_DESIGN.md` §3.2): un
/// scratch y en qué estado está para este usuario. Apagada si está bloqueada,
/// con brillo si está dominada.
public struct MatrixCell: Equatable, Sendable, Identifiable {

    public enum State: Equatable, Sendable {
        case locked                     // el nivel aún no da acceso
        case available                  // se puede practicar, sin estrellas todavía
        case practiced(stars: Int)      // 1 o 2 estrellas en la base
        case mastered                   // dominado (3★ base + 2★ en tres variantes)
    }

    public var scratchId: String
    public var name: String
    public var level: String            // "L1"…"L6"
    public var state: State

    public var id: String { scratchId }

    public init(scratchId: String, name: String, level: String, state: State) {
        self.scratchId = scratchId
        self.name = name
        self.level = level
        self.state = state
    }

    /// Construye la celda a partir del estado guardado de la **variante base**.
    public static func build(scratchId: String, name: String, level: String,
                             baseUnlocked: Bool,
                             baseProgress: ExerciseProgress?,
                             mastery: ExerciseMastery?) -> MatrixCell {
        let state: State
        if !baseUnlocked {
            state = .locked
        } else if mastery?.isMastered == true {
            state = .mastered
        } else if let stars = baseProgress?.stars, stars > 0 {
            state = .practiced(stars: min(stars, 2))
        } else {
            state = .available
        }
        return MatrixCell(scratchId: scratchId, name: name, level: level, state: state)
    }
}
