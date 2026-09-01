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
    /// URL en disco del recurso, si el loader es de ficheros (para APIs que
    /// piden `URL` y no `Data`, p. ej. `AVAudioFile`). `nil` si no aplica o no
    /// existe.
    func url(_ relativePath: String) -> URL?
}

public extension ContentLoader {
    func list(_ directory: String, withExtension ext: String) -> [String] { [] }
    func url(_ relativePath: String) -> URL? { nil }
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

    public func url(_ relativePath: String) -> URL? {
        let u = root.appendingPathComponent(relativePath)
        return FileManager.default.fileExists(atPath: u.path) ? u : nil
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

    public func url(_ relativePath: String) -> URL? {
        let u = root.appendingPathComponent(relativePath)
        return FileManager.default.fileExists(atPath: u.path) ? u : nil
    }
}

/// Lee `data/` y `profiles/` de la carpeta de recursos del **bundle de la app**
/// (`xFlare.app/Contents/Resources/`). Es lo que usa el `.app` distribuido; en
/// `swift run` (dev) no hay bundle con recursos y se cae a `RepoContentLoader`.
///
/// El copiado fisico de `data/` y `profiles/` a `Contents/Resources/` lo hace el
/// script de empaquetado del DMG (B12a.4), no SwiftPM: los recursos de SwiftPM
/// tienen que vivir dentro de la carpeta del target y estas no lo hacen.
public struct BundleContentLoader: ContentLoader {

    private let inner: DirectoryContentLoader

    /// Ruta relativa del catalogo, la usamos como sonda de "¿hay recursos?".
    static let catalogProbe = "data/scratches/library-v0.1.json"

    /// - Parameter resourceRoot: carpeta que contiene `data/` y `profiles/`.
    public init(resourceRoot: URL) {
        self.inner = DirectoryContentLoader(root: resourceRoot)
    }

    /// A partir del bundle indicado (por defecto el de la app). `nil` si el
    /// bundle no expone carpeta de recursos.
    public init?(bundle: Bundle = .main) {
        guard let url = bundle.resourceURL else { return nil }
        self.init(resourceRoot: url)
    }

    public func data(_ relativePath: String) throws -> Data {
        try inner.data(relativePath)
    }

    public func list(_ directory: String, withExtension ext: String) -> [String] {
        inner.list(directory, withExtension: ext)
    }

    public func url(_ relativePath: String) -> URL? { inner.url(relativePath) }

    /// `true` si la carpeta de recursos trae de verdad el catalogo del producto.
    /// El arranque de la app lo consulta para decidir entre bundle y repo.
    public var hasCatalog: Bool {
        (try? data(Self.catalogProbe)) != nil
    }
}
