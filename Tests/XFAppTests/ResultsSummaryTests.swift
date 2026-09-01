// SPDX-License-Identifier: GPL-3.0-only
import XCTest
@testable import XFApp

/// B11.4 / B11.13 — pantalla de resultados: estrellas apagadas con su condición
/// y puntuación sobre el máximo.
final class ResultsSummaryTests: XCTestCase {

    func testMillaresConPunto() {
        XCTAssertEqual(ResultsSummary.grouped(3840), "3.840")
        XCTAssertEqual(ResultsSummary.grouped(4800), "4.800")
        XCTAssertEqual(ResultsSummary.grouped(999), "999")
        XCTAssertEqual(ResultsSummary.grouped(1_234_567), "1.234.567")
        XCTAssertEqual(ResultsSummary.grouped(0), "0")
    }

    func testPuntuacionSobreElMaximoYPorcentaje() {
        let s = ResultsSummary.build(score: 3840, maxScore: 4800, starCount: 2,
                                     starReasons: [], diagnostics: [], isBestScore: true)
        XCTAssertEqual(s.scoreText, "3.840 / 4.800")
        XCTAssertEqual(s.accuracyPercent, 80)
        XCTAssertTrue(s.isBestScore)
    }

    func testTresFilasDeEstrellaSiempreYLasApagadasLlevanCondicion() {
        let s = ResultsSummary.build(score: 3000, maxScore: 3600, starCount: 1,
                                     starReasons: [
                                        "★★ Limpio: se te ha caido 1 evento (a 0). Limpio = ninguno a 0.",
                                     ],
                                     diagnostics: [], isBestScore: false)
        XCTAssertEqual(s.stars.count, 3)
        XCTAssertEqual(s.stars.map(\.filled), [true, false, false])
        XCTAssertNil(s.stars[0].condition, "encendida, sin condición")
        XCTAssertEqual(s.stars[1].title, "Limpio")
        XCTAssertEqual(s.stars[1].condition,
                       "se te ha caido 1 evento (a 0). Limpio = ninguno a 0.",
                       "la condición de la 2ª estrella viene de starReasons, sin el prefijo ★★")
        XCTAssertEqual(s.stars[2].condition, "95 %, σ ≤ 15 ms y al BPM objetivo.",
                       "la 3ª, que aún no toca, usa la condición por defecto")
    }

    func testLaCondicionDeUnSlotNoSeConfundeConLaDeOtro() {
        // un reason con prefijo "★★★ " no debe caer en el slot 1 (que empieza por "★★ ")
        let s = ResultsSummary.build(score: 3500, maxScore: 3600, starCount: 2,
                                     starReasons: [
                                        "★★★ Solido: tu timing varia 22 ms; hace falta <= 15 ms.",
                                     ],
                                     diagnostics: [], isBestScore: false)
        XCTAssertNil(s.stars[0].condition)
        XCTAssertNil(s.stars[1].condition, "la 2ª está encendida")
        XCTAssertEqual(s.stars[2].condition, "tu timing varia 22 ms; hace falta <= 15 ms.")
    }

    func testTodasEncendidas() {
        let s = ResultsSummary.build(score: 3550, maxScore: 3600, starCount: 3,
                                     starReasons: [], diagnostics: ["Clavado."], isBestScore: false)
        XCTAssertEqual(s.stars.map(\.filled), [true, true, true])
        XCTAssertTrue(s.stars.allSatisfy { $0.condition == nil })
        XCTAssertEqual(s.diagnostics, ["Clavado."])
    }

    func testDiagnosticosPasanEnOrden() {
        let s = ResultsSummary.build(score: 1, maxScore: 2, starCount: 0,
                                     starReasons: ["★ Completado: necesitas al menos 70% (tienes 50%)."],
                                     diagnostics: ["Tu segundo click va 35 ms tarde.", "Recorrido corto."],
                                     isBestScore: false)
        XCTAssertEqual(s.diagnostics, ["Tu segundo click va 35 ms tarde.", "Recorrido corto."])
        XCTAssertEqual(s.stars[0].condition, "necesitas al menos 70% (tienes 50%).")
    }
}
