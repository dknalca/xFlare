// SPDX-License-Identifier: GPL-3.0-only
import XCTest
import XFClock
import XFNotation
import XFTestKit
@testable import XFAnalysis

/// B8.5 — **golden** de la batería de replay: para cada patrón representativo de
/// nivel 1-4 y cada toma sintética (good / late / sloppy), se congela el `Report`
/// numérico exacto en `Fixtures/golden/analysis/`. `ReplayScoringTests` fija las
/// *invariantes* (good ≫ sloppy, late = sesgo…); esto fija los *números*, así una
/// "mejora" del scorer que mueva una puntuación 3 puntos salta aquí y se revisa
/// en el diff, igual que los goldens de `XFNotation` / `XFRender`.
///
/// Regenerar: `make golden-update` (pone `XF_GOLDEN_UPDATE=1`). REVISA EL DIFF.
///
/// Cuando lleguen los `.xfsession` grabados con hardware (cierra B8.5 y
/// desbloquea B8.8), esta misma tabla se regenera contra ellos.
final class GoldenReplayScoringTests: XCTestCase {

    private func compose(_ hand: String, _ fader: String) throws -> Scratch {
        try Composer.compose(hand: hand, fader: fader, division: "1/8", cycles: 4,
                             primitives: try AnalysisFixtures.primitives())
    }

    private func clock(bpm: Double = 90) -> ClockMap {
        ClockMap(anchorHostTime: 2_000_000_000_000, anchorTick: 0,
                 tempo: Tempo(bpm: bpm), host: HostClock(numer: 1, denom: 1))
    }

    /// (etiqueta de fichero, patrón). Un patrón por nivel, como en `ReplayScoringTests`.
    private func patterns() throws -> [(String, Scratch)] {
        [
            ("l1-forward-cut",   try compose("baby", "forward_cut")),
            ("l2-transformer-2", try compose("baby", "transformer_2")),
            ("l3-flare-1c",      try compose("baby", "flare_1c")),
            ("l4-flare-2c",      try compose("baby", "flare_2c")),
        ]
    }

    /// Las tres tomas sintéticas canónicas (mismos parámetros que `ReplayScoringTests`).
    private func takes(for sc: Scratch) -> [(String, Take)] {
        [
            ("good",   SyntheticTake.make(for: sc, clock: clock())),
            ("late",   SyntheticTake.make(for: sc, clock: clock(), clickBiasMs: 35)),
            ("sloppy", SyntheticTake.make(for: sc, clock: clock(), clickJitterMs: 45,
                                          velocityNoise: 0.02, seed: 99)),
        ]
    }

    func testGoldenDeLaBateriaDeReplay() throws {
        let update = ProcessInfo.processInfo.environment["XF_GOLDEN_UPDATE"] == "1"
        let dir = AnalysisFixtures.repoRoot
            .appendingPathComponent("Fixtures/golden/analysis", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let scorer = DefaultScorer()
        var mismatches: [String] = []

        for (patternLabel, sc) in try patterns() {
            for (takeLabel, take) in takes(for: sc) {
                let name = "\(patternLabel)__\(takeLabel)"
                let report = scorer.score(take, against: sc, atTargetBpm: true)
                let snapshot = Self.snapshot(of: report)
                let file = dir.appendingPathComponent("\(name).json")

                if update {
                    try Self.write(snapshot, to: file)
                    continue
                }
                guard let golden = try? Self.read(file) else {
                    mismatches.append("\(name) (falta el golden)")
                    continue
                }
                if let diff = Self.diff(golden: golden, actual: snapshot) {
                    mismatches.append("\(name): \(diff)")
                }
            }
        }

        if update {
            print("Goldens de replay regenerados en \(dir.path)")
        } else {
            XCTAssertTrue(mismatches.isEmpty,
                "Report distinto del golden en:\n  " + mismatches.joined(separator: "\n  ")
                + "\nSi el cambio del scorer es esperado: `make golden-update`.")
        }
    }

    // MARK: - serialización del Report (numérica, tolerante a la arquitectura)

    /// Campos numéricos redondeados a 4 decimales (ADR-028) + los discretos.
    static func snapshot(of r: Report) -> [String: Any] {
        [
            "score": r.score,
            "maxScore": r.maxScore,
            "stars": r.stars,
            "missedClicks": r.missedClicks,
            "finished": r.finished,
            "sigmaMs": Golden.round4(r.sigmaMs),
            "biasMs": Golden.round4(r.biasMs),
            "pitchDistance": Golden.round4(r.pitchDistance),
            "amplitudeError": Golden.round4(r.amplitudeError),
            "diagnosticKinds": r.diagnostics.map { $0.kind.rawValue }.sorted(),
            "starReasons": r.starReasons,
        ]
    }

    private static let numericKeys = ["sigmaMs", "biasMs", "pitchDistance", "amplitudeError"]
    private static let intKeys = ["score", "maxScore", "stars", "missedClicks"]

    /// `nil` si equivalen; si no, la primera diferencia legible.
    static func diff(golden: [String: Any], actual: [String: Any]) -> String? {
        for k in intKeys {
            let g = golden[k] as? Int ?? Int.min
            let a = actual[k] as? Int ?? Int.min
            if g != a { return "\(k) golden=\(g) actual=\(a)" }
        }
        if (golden["finished"] as? Bool) != (actual["finished"] as? Bool) {
            return "finished golden=\(golden["finished"] ?? "?") actual=\(actual["finished"] ?? "?")"
        }
        for k in numericKeys {
            let g = (golden[k] as? Double) ?? Double.nan
            let a = (actual[k] as? Double) ?? Double.nan
            if !Golden.approxEqual(g, a) { return "\(k) golden=\(g) actual=\(a)" }
        }
        let gKinds = golden["diagnosticKinds"] as? [String] ?? []
        let aKinds = actual["diagnosticKinds"] as? [String] ?? []
        if gKinds != aKinds { return "diagnosticKinds golden=\(gKinds) actual=\(aKinds)" }
        let gReasons = golden["starReasons"] as? [String] ?? []
        let aReasons = actual["starReasons"] as? [String] ?? []
        if gReasons != aReasons { return "starReasons golden=\(gReasons) actual=\(aReasons)" }
        return nil
    }

    static func write(_ snapshot: [String: Any], to file: URL) throws {
        let data = try JSONSerialization.data(
            withJSONObject: snapshot, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: file, options: .atomic)
    }

    static func read(_ file: URL) throws -> [String: Any] {
        let data = try Data(contentsOf: file)
        return try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
    }
}
