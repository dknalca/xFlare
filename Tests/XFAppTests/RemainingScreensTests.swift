// SPDX-License-Identifier: GPL-3.0-only
import XCTest
@testable import XFApp
import XFPersistence

/// B11.12 / B11.14 / B11.15 / B11.16.
final class RemainingScreensTests: XCTestCase {

    // MARK: - B11.12 permiso de micrófono

    func testMicSinDeterminarSePuedePedir() {
        XCTAssertTrue(MicPermission.notDetermined.canRequest)
        XCTAssertFalse(MicPermission.notDetermined.canCapture)
        XCTAssertTrue(MicPermission.notDetermined.helpSteps.isEmpty)
    }

    func testMicDenegadoExplicaQueHacer() {
        let steps = MicPermission.denied.helpSteps
        XCTAssertFalse(steps.isEmpty, "si dice que no, la app explica qué hacer")
        XCTAssertTrue(steps.contains { $0.contains("Ajustes del Sistema") })
        XCTAssertFalse(MicPermission.denied.canRequest, "ya no se puede reabrir el diálogo")
    }

    func testMicConcedido() {
        XCTAssertTrue(MicPermission.granted.canCapture)
        XCTAssertTrue(MicPermission.granted.helpSteps.isEmpty)
    }

    // MARK: - B11.14 progreso por ejercicio y variante

    private func summary() -> ProgressSummary {
        let p = ExerciseProgress(
            exerciseId: "e", variantId: "base", attempts: 7,
            bestScore: 3840, bestScoreAt: Date(timeIntervalSince1970: 1_723_593_600), // 2024-08-14
            lastScore: 3510, lastAttemptAt: nil, stars: 2,
            bestBpmWith3Stars: nil, meanBiasMs: 14.6, totalPracticeMs: 4_380_000) // 73 min
        return ProgressSummary(progress: p, averageOfLast5: 3512.4,
                               recentScores: [3400, 3450, 3510])
    }

    func testProgresoSeFormateaSegunScoring3() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let d = ExerciseProgressDisplay.build(summary(), calendar: cal)
        XCTAssertEqual(d.attempts, 7)
        XCTAssertEqual(d.bestScore, "3.840")
        XCTAssertEqual(d.bestScoreDate, "2024-08-14")
        XCTAssertEqual(d.averageOfLast5, "3.512")
        XCTAssertEqual(d.bestBpmWith3Stars, "—", "aún no hay 3★")
        XCTAssertEqual(d.meanBias, "+15 ms", "sesgo con signo, redondeado")
        XCTAssertEqual(d.totalPracticeTime, "1 h 13 min")
        XCTAssertEqual(d.sparkline, [3400, 3450, 3510])
    }

    func testSesgoNegativoYCero() {
        XCTAssertEqual(ExerciseProgressDisplay.signedMs(-8.2), "−8 ms")
        XCTAssertEqual(ExerciseProgressDisplay.signedMs(0.3), "0 ms")
        XCTAssertEqual(ExerciseProgressDisplay.duration(ms: 45_000), "0 min")
        XCTAssertEqual(ExerciseProgressDisplay.duration(ms: 3_600_000), "1 h 0 min")
    }

    // MARK: - B11.15 selector de variantes

    func testVariantesBloqueadasDicenLaCondicion() {
        let base = VariantOption.build(variantId: "base", name: "Base", difficulty: 1.0,
                                       requires: nil, starsInRequired: 0, requiredVariantName: "")
        XCTAssertEqual(base.lock, .unlocked)

        let off50Locked = VariantOption.build(
            variantId: "off50", name: "Entrada a la mitad", difficulty: 1.25,
            requires: ("base", 2), starsInRequired: 1, requiredVariantName: "Base")
        XCTAssertEqual(off50Locked.lock, .locked(condition: "★★ en Base"))
        XCTAssertFalse(off50Locked.isUnlocked)

        let off50Open = VariantOption.build(
            variantId: "off50", name: "Entrada a la mitad", difficulty: 1.25,
            requires: ("base", 2), starsInRequired: 2, requiredVariantName: "Base")
        XCTAssertTrue(off50Open.isUnlocked)
    }

    // MARK: - B11.16 Rosetta

    func testDeteccionDeRosetta() {
        XCTAssertTrue(RosettaCheck.translated(reader: { 1 }), "1 = traducido")
        XCTAssertFalse(RosettaCheck.translated(reader: { 0 }), "0 = nativo")
        XCTAssertFalse(RosettaCheck.translated(reader: { -1 }), "-1 = no disponible")
    }

    func testAvisoDeRosettaSoloSiEsRelevante() {
        // en la máquina de test (nativa) no debe avisar
        XCTAssertNil(RosettaCheck.calibrationWarning)
    }
}
