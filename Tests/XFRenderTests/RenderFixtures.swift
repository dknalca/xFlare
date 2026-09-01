// SPDX-License-Identifier: GPL-3.0-only
import Foundation
import XFNotation

/// Carga scratches reales de `data/scratches/library-v0.1.json` para los tests de
/// render. Mismo truco que `XFNFixtures`: `#filePath` sube hasta la raíz del repo.
enum RenderFixtures {

    static let repoRoot: URL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()   // Tests/XFRenderTests
        .deletingLastPathComponent()   // Tests
        .deletingLastPathComponent()   // raíz

    static func library() throws -> ScratchLibrary {
        let data = try Data(contentsOf: repoRoot
            .appendingPathComponent("data/scratches/library-v0.1.json"))
        return try JSONDecoder().decode(ScratchLibrary.self, from: data)
    }

    /// `forward-cut`: 8 fases de disco, 9 eventos de fader, 1920 ticks. Buen
    /// caso de prueba porque tiene actividad de fader de verdad.
    static func forwardCut() throws -> Scratch {
        guard let s = try library().scratch(id: "forward-cut") else {
            fatalError("falta 'forward-cut' en la librería")
        }
        return s
    }

    static func baby() throws -> Scratch {
        guard let s = try library().scratch(id: "baby") else {
            fatalError("falta 'baby' en la librería")
        }
        return s
    }
}
