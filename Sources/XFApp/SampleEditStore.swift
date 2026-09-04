// SPDX-License-Identifier: GPL-3.0-only

import Foundation

/// Los `SampleEdit` del usuario, uno por ruta de fichero, en
/// `~/Library/Application Support/xFlare/sample-edits.json` (JSON legible,
/// atómico). Gemelo de `InstrumentalEditStore`.
public final class SampleEditStore: ObservableObject {

    @Published public private(set) var edits: [String: SampleEdit] = [:]

    private let fileURL: URL

    public init(fileURL: URL = SampleEditStore.defaultURL()) {
        self.fileURL = fileURL
        load()
    }

    public static func defaultURL() -> URL {
        let base = (try? FileManager.default.url(for: .applicationSupportDirectory,
                                                 in: .userDomainMask, appropriateFor: nil, create: true))
            ?? FileManager.default.temporaryDirectory
        let dir = base.appendingPathComponent("xFlare", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("sample-edits.json")
    }

    public func edit(for path: String) -> SampleEdit? { edits[path] }

    public func set(_ edit: SampleEdit, for path: String) {
        if edit.isDefault {
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
              let decoded = try? JSONDecoder().decode([String: SampleEdit].self, from: data)
        else { return }
        edits = decoded
    }

    private func save() {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? e.encode(edits) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
