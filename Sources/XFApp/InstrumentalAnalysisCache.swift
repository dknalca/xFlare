// SPDX-License-Identifier: GPL-3.0-only

import Foundation

/// Análisis de tempo de una instrumental YA HECHO, guardado en disco. Analizar
/// una pista de varios minutos tarda ~1 s; con esto, añadir un fichero a la
/// librería lo analiza UNA vez y en la práctica se carga al instante.
///
/// `fileBytes` + `mtime` invalidan la entrada si el fichero cambió; `sampleRate`
/// la invalida si el motor corre a otra frecuencia (el análisis depende de ella).
public struct CachedAnalysis: Codable, Equatable, Sendable {
    public var result: TempoAnalyzer.Result
    public var fileBytes: Int64
    public var mtime: Double
    public var sampleRate: Double

    /// `true` si sigue valiendo para `path` a `sampleRate`.
    public func isFresh(for path: String, sampleRate sr: Double,
                        fileManager fm: FileManager = .default) -> Bool {
        guard abs(sampleRate - sr) < 1.0,
              let attrs = try? fm.attributesOfItem(atPath: path),
              let size = (attrs[.size] as? NSNumber)?.int64Value,
              let mod = (attrs[.modificationDate] as? Date)
        else { return false }
        return size == fileBytes && abs(mod.timeIntervalSinceReferenceDate - mtime) < 1.0
    }

    public static func make(_ result: TempoAnalyzer.Result, path: String, sampleRate: Double,
                            fileManager fm: FileManager = .default) -> CachedAnalysis {
        let attrs = try? fm.attributesOfItem(atPath: path)
        let size = ((attrs?[.size] as? NSNumber)?.int64Value) ?? 0
        let mod = ((attrs?[.modificationDate] as? Date)?.timeIntervalSinceReferenceDate) ?? 0
        return CachedAnalysis(result: result, fileBytes: size, mtime: mod, sampleRate: sampleRate)
    }
}

/// El caché de análisis de instrumentales, en `~/Library/Application Support/
/// xFlare/instrumental-analysis.json`. `ObservableObject`: la pantalla de
/// Librería se refresca cuando termina un análisis en segundo plano.
public final class InstrumentalAnalysisCache: ObservableObject {

    /// path -> análisis. `@Published` para que la vista reaccione.
    @Published public private(set) var entries: [String: CachedAnalysis] = [:]
    /// Rutas que se están analizando ahora mismo (para enseñar "analizando…").
    @Published public private(set) var analyzing: Set<String> = []

    private let fileURL: URL
    private let queue = DispatchQueue(label: "app.xflare.analysis", qos: .utility)

    public init(fileURL: URL = InstrumentalAnalysisCache.defaultURL()) {
        self.fileURL = fileURL
        load()
    }

    public static func defaultURL() -> URL {
        let base = (try? FileManager.default.url(for: .applicationSupportDirectory,
                                                 in: .userDomainMask, appropriateFor: nil, create: true))
            ?? FileManager.default.temporaryDirectory
        let dir = base.appendingPathComponent("xFlare", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("instrumental-analysis.json")
    }

    /// Análisis válido para `path` (o `nil` si no está o el fichero cambió).
    public func result(for path: String, sampleRate: Double) -> TempoAnalyzer.Result? {
        guard let c = entries[path], c.isFresh(for: path, sampleRate: sampleRate) else { return nil }
        return c.result
    }

    /// Analiza `path` en segundo plano si no hay un análisis fresco. Idempotente.
    public func analyzeIfNeeded(path: String, sampleRate: Double) {
        guard !path.isEmpty, result(for: path, sampleRate: sampleRate) == nil,
              !analyzing.contains(path) else { return }
        analyzing.insert(path)
        queue.async { [weak self] in
            let url = URL(fileURLWithPath: path)
            let hint = TempoAnalyzer.bpmHint(fromFilename: url.lastPathComponent)
            var made: CachedAnalysis?
            if let pcm = AudioAsset.loadMono(url, sampleRate: sampleRate), pcm.count > Int(sampleRate / 2),
               let r = TempoAnalyzer.analyze(pcm, sampleRate: sampleRate, hintBPM: hint) {
                made = CachedAnalysis.make(r, path: path, sampleRate: sampleRate)
            }
            DispatchQueue.main.async {
                guard let self else { return }
                self.analyzing.remove(path)
                if let made {
                    self.entries[path] = made
                    self.save()
                }
            }
        }
    }

    /// Analiza todo lo que falte de una lista de rutas.
    public func analyzeAll(_ paths: [String], sampleRate: Double) {
        for p in paths { analyzeIfNeeded(path: p, sampleRate: sampleRate) }
    }

    public func forget(_ path: String) {
        if entries.removeValue(forKey: path) != nil { save() }
    }

    // MARK: - disco

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode([String: CachedAnalysis].self, from: data)
        else { return }
        entries = decoded
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
