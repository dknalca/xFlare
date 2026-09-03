// SPDX-License-Identifier: GPL-3.0-only
import XCTest
@testable import XFApp

/// El `.app` distribuido lee `data/` y `profiles/` de su carpeta de recursos.
/// Aqui se monta una carpeta con esa forma (copiando la del repo) y se comprueba
/// que `BundleContentLoader` sirve el catalogo igual que `RepoContentLoader`.
final class BundleContentLoaderTests: XCTestCase {

    /// Raiz del repo, deducida de la ruta de este fichero
    /// (`.../Tests/XFAppTests/BundleContentLoaderTests.swift` -> sube 3).
    private static let repoRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()   // XFAppTests
        .deletingLastPathComponent()   // Tests
        .deletingLastPathComponent()   // raiz

    /// Copia `data/` y `profiles/` del repo a un directorio temporal con la
    /// misma forma que `Contents/Resources/` del bundle.
    private func stagedResources() throws -> URL {
        let fm = FileManager.default
        let tmp = fm.temporaryDirectory
            .appendingPathComponent("xflare-res-\(UUID().uuidString)")
        try fm.createDirectory(at: tmp, withIntermediateDirectories: true)
        for name in ["data", "profiles"] {
            try fm.copyItem(at: Self.repoRoot.appendingPathComponent(name),
                            to: tmp.appendingPathComponent(name))
        }
        addTeardownBlock { try? fm.removeItem(at: tmp) }
        return tmp
    }

    func testSirveElCatalogoDesdeLaCarpetaDeRecursos() throws {
        let loader = BundleContentLoader(resourceRoot: try stagedResources())

        XCTAssertTrue(loader.hasCatalog)

        let catalog = try CatalogLoader.load(from: loader)
        XCTAssertEqual(catalog.exercises.count, 18)
        XCTAssertFalse(catalog.library.scratches.isEmpty)
    }

    func testListaLosPerfilesConf() throws {
        let loader = BundleContentLoader(resourceRoot: try stagedResources())
        let confs = loader.list("profiles", withExtension: "conf")

        XCTAssertTrue(confs.contains("rane-seventy-two.conf"))
        XCTAssertFalse(confs.contains("user_custom.conf.example"), "el .example no es .conf")
        XCTAssertGreaterThanOrEqual(confs.count, 4)
    }

    func testCarpetaSinRecursosNoTieneCatalogo() throws {
        let fm = FileManager.default
        let empty = fm.temporaryDirectory.appendingPathComponent("xflare-empty-\(UUID().uuidString)")
        try fm.createDirectory(at: empty, withIntermediateDirectories: true)
        addTeardownBlock { try? fm.removeItem(at: empty) }

        let loader = BundleContentLoader(resourceRoot: empty)
        XCTAssertFalse(loader.hasCatalog)
        XCTAssertTrue(loader.list("profiles", withExtension: "conf").isEmpty)
    }

    func testMismoResultadoQueRepoContentLoader() throws {
        let fromRepo = try CatalogLoader.load(from: RepoContentLoader())
        let fromBundle = try CatalogLoader.load(
            from: BundleContentLoader(resourceRoot: try stagedResources()))

        XCTAssertEqual(fromRepo.exercises.map(\.id), fromBundle.exercises.map(\.id))
        XCTAssertEqual(fromRepo.variants.map(\.id), fromBundle.variants.map(\.id))
    }
}
