// SPDX-License-Identifier: GPL-3.0-only

import Foundation

/// Los `InstrumentalEdit` del usuario, uno por ruta de fichero, en
/// `~/Library/Application Support/xFlare/instrumental-edits.json` (JSON legible,
/// escrito de forma atómica). Aparte del caché de análisis: eso es dato
/// derivado, esto es **intención del usuario**.
///
/// `ObservableObject`: la Librería y el editor se refrescan al guardar.
public final class InstrumentalEditStore: ObservableObject {

    @Published public private(set) var edits: [String: InstrumentalEdit] = [:]

    private let fileURL: URL

    public init(fileURL: URL = InstrumentalEditStore.defaultURL()) {
        self.fileURL = fileURL
        load()
    }

    public static func defaultURL() -> URL {
        let base = (try? FileManager.default.url(for: .applicationSupportDirectory,
                                                 in: .userDomainMask, appropriateFor: nil, create: true))
            ?? FileManager.default.temporaryDirectory
        let dir = base.appendingPathComponent("xFlare", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("instrumental-edits.json")
    }

    /// El ajuste guardado para `path`, o `nil`.
    public func edit(for path: String) -> InstrumentalEdit? { edits[path] }

    /// Guarda (o borra, si queda vacío) el ajuste de `path`.
    public func set(_ edit: InstrumentalEdit, for path: String) {
        if edit.isEmpty {
            guard edits.removeValue(forKey: path) != nil else { return }
        } else {
            edits[path] = edit
        }
        save()
    }

    public func forget(_ path: String) {
        if edits.removeValue(forKey: path) != nil { save() }
    }

    // MARK: - disco

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode([String: InstrumentalEdit].self, from: data)
        else { return }
        edits = decoded
    }

    private func save() {
        guard let data = try? JSONEncoder.prettySorted.encode(edits) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}

private extension JSONEncoder {
    static var prettySorted: JSONEncoder {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }
}
