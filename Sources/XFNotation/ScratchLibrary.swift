// SPDX-License-Identifier: GPL-3.0-only

import Foundation

/// Una linea del catalogo (`tools/catalog.json`): "compon este scratch con estos
/// parametros". Anadir un scratch es anadir una linea, no tocar codigo.
public struct CatalogEntry: Codable, Sendable, Equatable {
    public let id: String
    public let name: String
    public let hand: String
    public let fader: String
    public let div: String
    public let cycles: Int
    public let level: Int
    public let family: String
    public let notes: String
}

/// La libreria de scratches: el catalogo ya compuesto. Equivale a
/// `data/scratches/library-v0.1.json`.
public struct ScratchLibrary: Codable, Sendable, Equatable {

    public var schemaVersion: String
    public var generatedBy: String
    public var notation: String
    public var ppq: Int
    public var scratches: [Scratch]

    public init(schemaVersion: String, generatedBy: String, notation: String,
                ppq: Int, scratches: [Scratch]) {
        self.schemaVersion = schemaVersion
        self.generatedBy = generatedBy
        self.notation = notation
        self.ppq = ppq
        self.scratches = scratches
    }

    public func scratch(id: String) -> Scratch? {
        scratches.first { $0.id == id }
    }

    /// Compone la libreria entera a partir del catalogo y las primitivas. Mismo
    /// resultado que `tools/xfn_build.py` (verificado por el golden B3.3).
    public static func build(catalog: [CatalogEntry],
                             primitives: PrimitiveSet,
                             ppq: Int = 480) throws -> ScratchLibrary {
        let scratches = try catalog.map { e in
            try Composer.compose(
                hand: e.hand, fader: e.fader, division: e.div, cycles: e.cycles,
                ppq: ppq, primitives: primitives,
                id: e.id, name: e.name, level: e.level, family: e.family, notes: e.notes
            )
        }
        return ScratchLibrary(
            schemaVersion: "0.1.0",
            generatedBy: "tools/xfn_build.py",
            notation: "XFN (xFlare Notation)",
            ppq: ppq,
            scratches: scratches
        )
    }
}
