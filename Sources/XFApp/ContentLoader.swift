// SPDX-License-Identifier: GPL-3.0-only

import Foundation

/// De donde salen los datos de solo lectura del producto (`data/`): la libreria
/// de scratches, el curriculo, las variantes. En la app empaquetada sera el
/// bundle; en dev/tests, la carpeta del repo. `CatalogLoader` los consume.
public protocol ContentLoader {
    /// Bytes del recurso `relativePath` (p. ej. `"data/curriculum/levels.json"`).
    func data(_ relativePath: String) throws -> Data
    /// Nombres de fichero dentro de `directory` (p. ej. `"profiles"`) con la
    /// extension `ext`. Vacio si el directorio no existe.
    func list(_ directory: String, withExtension ext: String) -> [String]
}

public extension ContentLoader {
    func list(_ directory: String, withExtension ext: String) -> [String] { [] }
}

/// Lee los ficheros directamente del repo (usando la ruta de este fichero para
/// localizar la raiz). Para dev y tests.
public struct RepoContentLoader: ContentLoader {

    private let root: URL

    /// - Parameter root: raiz del repo. Por defecto se deduce de `#filePath`
    ///   (`.../Sources/XFApp/ContentLoader.swift` -> sube 3).
    public init(root: URL? = nil) {
        self.root = root ?? URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // Sources/XFApp
            .deletingLastPathComponent()   // Sources
            .deletingLastPathComponent()   // raiz
    }

    public func data(_ relativePath: String) throws -> Data {
        try Data(contentsOf: root.appendingPathComponent(relativePath))
    }

    public func list(_ directory: String, withExtension ext: String) -> [String] {
        let dir = root.appendingPathComponent(directory)
        let items = (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
        return items.filter { $0.hasSuffix("." + ext) }.sorted()
    }
}

/// Lee de un directorio de recursos ya resuelto (el bundle de la app). Se le pasa
/// la URL de la carpeta que contiene `data/` y `profiles/`.
public struct DirectoryContentLoader: ContentLoader {
    private let root: URL
    public init(root: URL) { self.root = root }

    public func data(_ relativePath: String) throws -> Data {
        try Data(contentsOf: root.appendingPathComponent(relativePath))
    }

    public func list(_ directory: String, withExtension ext: String) -> [String] {
        let dir = root.appendingPathComponent(directory)
        let items = (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
        return items.filter { $0.hasSuffix("." + ext) }.sorted()
    }
}
