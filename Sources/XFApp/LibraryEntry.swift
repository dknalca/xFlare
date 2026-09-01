// SPDX-License-Identifier: GPL-3.0-only

import XFNotation

/// Una fila del navegador de la librería (`docs/UI_DESIGN.md` §3.6): un scratch
/// con lo que hace falta para listarlo y filtrarlo.
public struct LibraryEntry: Equatable, Sendable, Identifiable {
    public var scratchId: String
    public var name: String
    public var family: String
    public var level: Int
    public var technique: String
    public var clickCount: Int
    public var lengthTicks: Int
    public var isUnlocked: Bool

    public var id: String { scratchId }

    public init(scratchId: String, name: String, family: String, level: Int,
                technique: String, clickCount: Int, lengthTicks: Int, isUnlocked: Bool) {
        self.scratchId = scratchId
        self.name = name
        self.family = family
        self.level = level
        self.technique = technique
        self.clickCount = clickCount
        self.lengthTicks = lengthTicks
        self.isUnlocked = isUnlocked
    }

    public init(scratch: Scratch, isUnlocked: Bool) {
        self.init(scratchId: scratch.id, name: scratch.name, family: scratch.family,
                  level: scratch.level, technique: scratch.technique,
                  clickCount: scratch.clickCount, lengthTicks: scratch.lengthTicks,
                  isUnlocked: isUnlocked)
    }
}
