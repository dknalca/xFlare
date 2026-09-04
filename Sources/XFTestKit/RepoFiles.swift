// SPDX-License-Identifier: GPL-3.0-only

import Foundation

/// Localiza ficheros del repositorio desde un test, sin depender del directorio
/// de trabajo. Sube desde el `#filePath` del que llama hasta encontrar
/// `Package.swift`.
///
/// Los goldens y los datos (`data/`, `Fixtures/`) viven en el repo, no en el
/// bundle del módulo, así que hasta ahora cada target de test se inventaba un
/// `URL(fileURLWithPath: #filePath).deletingLastPathComponent()…` con un número
/// fijo de saltos. Esto lo hace una vez y bien.
///
/// `#filePath` como valor por defecto se expande en el **sitio de la llamada**,
/// así que `RepoFiles.root()` desde un fichero de test da la raíz del repo.
public enum RepoFiles {

    /// Raíz del repositorio (la carpeta que contiene `Package.swift`).
    public static func root(from filePath: StaticString = #filePath) -> URL {
        var dir = URL(fileURLWithPath: "\(filePath)").deletingLastPathComponent()
        for _ in 0..<16 {
            if FileManager.default.fileExists(
                atPath: dir.appendingPathComponent("Package.swift").path) {
                return dir
            }
            let parent = dir.deletingLastPathComponent()
            if parent == dir { break }        // llegamos a "/"
            dir = parent
        }
        return URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    }

    /// `URL` de una ruta **relativa a la raíz del repo** (`"data/primitives/…"`,
    /// `"Fixtures/golden/highway/baby.svg"`).
    public static func url(_ relativePath: String, from filePath: StaticString = #filePath) -> URL {
        root(from: filePath).appendingPathComponent(relativePath)
    }

    /// Contenido de un fichero del repo. Lanza si no existe.
    public static func data(_ relativePath: String, from filePath: StaticString = #filePath) throws -> Data {
        try Data(contentsOf: url(relativePath, from: filePath))
    }

    /// Texto UTF-8 de un fichero del repo. Lanza si no existe o no decodifica.
    public static func text(_ relativePath: String, from filePath: StaticString = #filePath) throws -> String {
        try String(contentsOf: url(relativePath, from: filePath), encoding: .utf8)
    }
}
