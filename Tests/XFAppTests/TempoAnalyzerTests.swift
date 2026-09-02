// SPDX-License-Identifier: GPL-3.0-only
import XCTest
@testable import XFApp

/// Detección de tempo/fase de la instrumental (para cuadrar la rejilla a los
/// golpes). Se prueba con un tren de clicks sintético de tempo conocido.
final class TempoAnalyzerTests: XCTestCase {

    /// `seconds` de clicks a `bpm`: cada negra, una ráfaga corta que decae.
    private func clickTrack(bpm: Double, seconds: Double, sr: Double = 48_000,
                            phaseFrames: Int = 0) -> [Float] {
        let n = Int(seconds * sr)
        var out = [Float](repeating: 0, count: n)
        let period = 60.0 / bpm * sr
        var t = Double(phaseFrames)
        while Int(t) < n {
            let start = Int(t)
            for i in 0..<300 {
                let idx = start + i
                if idx >= n { break }
                out[idx] += Float(exp(-Double(i) / 60.0) * sin(Double(i) * 0.6))
            }
            t += period
        }
        return out
    }

    func testDetectaUnTempoConocido() throws {
        let sr = 48_000.0
        for bpm in [90.0, 120.0, 140.0] {
            let pcm = clickTrack(bpm: bpm, seconds: 6, sr: sr)
            let r = try XCTUnwrap(TempoAnalyzer.analyze(pcm, sampleRate: sr))
            XCTAssertEqual(r.bpm, bpm, accuracy: 3.0, "bpm \(bpm) -> \(r.bpm)")
        }
    }

    func testEncuentraLaFaseDelPrimerGolpe() throws {
        let sr = 48_000.0
        let phase = 7_000
        let pcm = clickTrack(bpm: 120, seconds: 6, sr: sr, phaseFrames: phase)
        let r = try XCTUnwrap(TempoAnalyzer.analyze(pcm, sampleRate: sr))
        let period = Int(60.0 / r.bpm * sr)
        let err = [0, period, -period].map { abs(r.phaseFrames - phase + $0) }.min() ?? .max
        XCTAssertLessThan(err, 700, "fase \(r.phaseFrames) vs \(phase)")
    }

    func testCuadraSoloLosBuclesCortos() throws {
        let sr = 48_000.0
        // bucle corto de 8 negras exactas -> se cuadra
        let short = clickTrack(bpm: 120, seconds: 4.0, sr: sr)
        let rs = try XCTUnwrap(TempoAnalyzer.analyze(short, sampleRate: sr))
        XCTAssertTrue(rs.isShortLoop)
        XCTAssertEqual(rs.beats, 8)
        XCTAssertEqual(Double(rs.beats) * 60.0 / 4.0, rs.bpm, accuracy: 0.05)

        // pista larga (30 s) -> NO se cuadra, aunque el tempo sea el mismo
        let long = clickTrack(bpm: 120, seconds: 30.0, sr: sr)
        let rl = try XCTUnwrap(TempoAnalyzer.analyze(long, sampleRate: sr))
        XCTAssertFalse(rl.isShortLoop)
        XCTAssertEqual(rl.bpm, 120, accuracy: 3.0)
    }

    func testAudioMuyCortoDevuelveNil() {
        XCTAssertNil(TempoAnalyzer.analyze([Float](repeating: 0, count: 1000), sampleRate: 48_000))
        XCTAssertNil(TempoAnalyzer.analyze([Float](repeating: 0, count: 200_000), sampleRate: 48_000),
                     "silencio: sin onsets -> nil")
    }

    func testHintDelNombreDeFichero() {
        XCTAssertEqual(TempoAnalyzer.bpmHint(fromFilename: "Audio/loops/080bpm_beat.wav"), 80)
        XCTAssertEqual(TempoAnalyzer.bpmHint(fromFilename: "track_120 BPM.mp3"), 120)
        XCTAssertEqual(TempoAnalyzer.bpmHint(fromFilename: "95bpm.wav"), 95)
        XCTAssertNil(TempoAnalyzer.bpmHint(fromFilename: "cancion sin tempo.wav"))
    }

    /// La instrumental de verdad del repo, como la usa la app: con el hint del
    /// nombre (080bpm) se toca a 80 y el analisis solo saca la fase.
    func testInstrumentalRealConHint() throws {
        let content = RepoContentLoader()
        guard let url = content.url(AudioAsset.instrumentalRelPath),
              let pcm = AudioAsset.loadMono(url, sampleRate: 48_000) else {
            throw XCTSkip("no hay \(AudioAsset.instrumentalRelPath) en el repo")
        }
        let hint = TempoAnalyzer.bpmHint(fromFilename: AudioAsset.instrumentalRelPath)
        let r = try XCTUnwrap(TempoAnalyzer.analyze(pcm, sampleRate: 48_000, hintBPM: hint))
        print("TempoAnalyzer(real, hint=\(hint ?? -1)): bpm=\(r.bpm) phaseFrames=\(r.phaseFrames) "
              + "phaseSec=\(Double(r.phaseFrames) / 48_000)")
        XCTAssertEqual(r.bpm, 80, accuracy: 0.001, "con hint, el BPM es el del nombre")
        XCTAssertGreaterThanOrEqual(r.phaseFrames, 0)
        XCTAssertLessThan(r.phaseFrames, pcm.count)
    }
}
