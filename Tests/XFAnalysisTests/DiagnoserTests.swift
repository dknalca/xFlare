// SPDX-License-Identifier: GPL-3.0-only
import XCTest
@testable import XFAnalysis

/// `Diagnoser` (B8.4) — las frases accionables. Aquí se prueba la lógica de
/// forma directa (sesgo vs dispersión, clicks perdidos, y que **siempre** salga
/// al menos una línea). El recorrido completo con un `Take` está en
/// `ReplayScoringTests`.
final class DiagnoserTests: XCTestCase {

    /// Construye N `ClickOffset` ejecutados con el desfase dado (ms).
    private func offsets(_ ms: [Double]) -> [ClickOffset] {
        ms.enumerated().map { i, m in
            ClickOffset(targetTick: i * 240, userHostTime: 1, offsetMs: m, score: 100)
        }
    }

    func testSesgoSistematicoSeDiceComoSesgo() {
        let d = Diagnoser.diagnose(
            clickOffsets: offsets([33, 35, 31, 34, 36]),
            biasMs: 33.8, sigmaMs: 1.9, missedClicks: 0,
            amplitudeError: 0.05, pitchDistance: 0.05)
        XCTAssertTrue(d.contains { $0.kind == .timingBias && $0.text.contains("tarde") })
        XCTAssertFalse(d.contains { $0.kind == .timingSpread })
    }

    func testDispersionSeDiceComoDispersion() {
        let d = Diagnoser.diagnose(
            clickOffsets: offsets([-40, 45, -30, 38, -22]),
            biasMs: -1.8, sigmaMs: 37.0, missedClicks: 0,
            amplitudeError: 0.05, pitchDistance: 0.05)
        XCTAssertTrue(d.contains { $0.kind == .timingSpread })
        XCTAssertFalse(d.contains { $0.kind == .timingBias })
    }

    func testClicksPerdidosVanLosPrimeros() {
        let d = Diagnoser.diagnose(
            clickOffsets: offsets([5, -4]),
            biasMs: 0.5, sigmaMs: 4, missedClicks: 3,
            amplitudeError: 0.05, pitchDistance: 0.05)
        XCTAssertEqual(d.first?.kind, .missedClicks)
        XCTAssertTrue(d.first?.text.contains("3 clicks") ?? false)
    }

    /// Un patrón SIN clicks (baby) hecho limpio: antes devolvía [] y la pantalla
    /// de resultados se quedaba muda. Ahora sale una línea sobria.
    func testTomaLimpiaSinClicksNoDevuelveVacio() {
        let d = Diagnoser.diagnose(
            clickOffsets: [], biasMs: 0, sigmaMs: 0, missedClicks: 0,
            amplitudeError: 0.04, pitchDistance: 0.05)
        XCTAssertFalse(d.isEmpty, "siempre al menos una línea de feedback")
        XCTAssertEqual(d.count, 1)
        XCTAssertEqual(d.first?.kind, .good)
        XCTAssertTrue(d.first?.text.contains("Sin clicks") ?? false)
    }

    /// Con clicks y todo en orden: también una sola línea, y es de timing sólido.
    func testTomaLimpiaConClicksResumeElTiming() {
        let d = Diagnoser.diagnose(
            clickOffsets: offsets([2, -3, 1, 0, -2]),
            biasMs: -0.4, sigmaMs: 2.0, missedClicks: 0,
            amplitudeError: 0.05, pitchDistance: 0.05)
        XCTAssertEqual(d.count, 1)
        XCTAssertEqual(d.first?.kind, .good)
    }

    /// Nada de timing (1 click) pero amplitud mala: sale el diagnóstico de
    /// amplitud, no el de relleno.
    func testUnSoloClickPeroAmplitudMalaDaDiagnosticoDeAmplitud() {
        let d = Diagnoser.diagnose(
            clickOffsets: offsets([5]),
            biasMs: 5, sigmaMs: 0, missedClicks: 0,
            amplitudeError: 0.35, pitchDistance: 0.05)
        XCTAssertTrue(d.contains { $0.kind == .amplitude })
        XCTAssertFalse(d.contains { $0.kind == .timingBias })   // played < 2
    }
}
