// SPDX-License-Identifier: GPL-3.0-only
import Foundation
@testable import XFProfiles

/// Carga los `.conf` reales de `profiles/` desde los tests (via `#filePath`).
enum ProfilesFixtures {

    static let profilesDir: URL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()   // Tests/XFProfilesTests
        .deletingLastPathComponent()   // Tests
        .deletingLastPathComponent()   // repo root
        .appendingPathComponent("profiles")

    /// (nombreFichero, contenido) de todos los `.conf` y `.example`.
    static func allFiles() throws -> [(filename: String, text: String)] {
        let names = try FileManager.default.contentsOfDirectory(atPath: profilesDir.path)
            .filter { $0.hasSuffix(".conf") || $0.hasSuffix(".conf.example") }
            .sorted()
        return try names.map { name in
            (name, try String(contentsOf: profilesDir.appendingPathComponent(name), encoding: .utf8))
        }
    }

    static func text(_ filename: String) throws -> String {
        try String(contentsOf: profilesDir.appendingPathComponent(filename), encoding: .utf8)
    }

    static func store() throws -> ProfileStore {
        ProfileStore(bundled: try allFiles())
    }
}
