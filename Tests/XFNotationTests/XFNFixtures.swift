// SPDX-License-Identifier: GPL-3.0-only
import Foundation
import XFNotation

/// Localiza los ficheros de `data/` y `tools/` del repo desde los tests. Se usa
/// `#filePath` para subir hasta la raiz: funciona en `swift test` local y en CI
/// (el arbol de fuentes esta presente). No sirve para un bundle empaquetado, que
/// no es el caso de estos tests.
enum XFNFixtures {

    static let repoRoot: URL = URL(fileURLWithPath: #filePath)   // .../Tests/XFNotationTests/XFNFixtures.swift
        .deletingLastPathComponent()                             // .../Tests/XFNotationTests
        .deletingLastPathComponent()                             // .../Tests
        .deletingLastPathComponent()                             // repo root

    static func data(_ relativePath: String) throws -> Data {
        try Data(contentsOf: repoRoot.appendingPathComponent(relativePath))
    }

    static func primitives() throws -> PrimitiveSet {
        try PrimitiveSet(
            handPatternsJSON: try data("data/primitives/hand_patterns.json"),
            faderPatternsJSON: try data("data/primitives/fader_patterns.json")
        )
    }

    static func catalog() throws -> [CatalogEntry] {
        try JSONDecoder().decode([CatalogEntry].self, from: try data("tools/catalog.json"))
    }

    static func referenceLibrary() throws -> ScratchLibrary {
        try JSONDecoder().decode(ScratchLibrary.self,
                                 from: try data("data/scratches/library-v0.1.json"))
    }
}
