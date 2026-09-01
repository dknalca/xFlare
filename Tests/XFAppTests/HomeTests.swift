// SPDX-License-Identifier: GPL-3.0-only
import XCTest
@testable import XFApp
import XFPersistence

/// B11.2 — Home: matriz, racha, continuar.
final class HomeTests: XCTestCase {

    // MARK: - MatrixCell

    private func progress(stars: Int) -> ExerciseProgress {
        ExerciseProgress(exerciseId: "e", variantId: "base", stars: stars)
    }

    func testCeldaBloqueadaSiLaBaseNoEstaDesbloqueada() {
        let c = MatrixCell.build(scratchId: "flare-2c", name: "2-Click Flare", level: "L4",
                                 baseUnlocked: false, baseProgress: progress(stars: 3), mastery: nil)
        XCTAssertEqual(c.state, .locked)
    }

    func testCeldaDisponibleSinEstrellas() {
        let c = MatrixCell.build(scratchId: "baby", name: "Baby", level: "L1",
                                 baseUnlocked: true, baseProgress: nil, mastery: nil)
        XCTAssertEqual(c.state, .available)
    }

    func testCeldaPracticadaMuestraEstrellasYCapaA2() {
        let c1 = MatrixCell.build(scratchId: "baby", name: "Baby", level: "L1",
                                  baseUnlocked: true, baseProgress: progress(stars: 1), mastery: nil)
        XCTAssertEqual(c1.state, .practiced(stars: 1))
        let c3 = MatrixCell.build(scratchId: "baby", name: "Baby", level: "L1",
                                  baseUnlocked: true, baseProgress: progress(stars: 3), mastery: nil)
        XCTAssertEqual(c3.state, .practiced(stars: 2), "la celda no pinta 3★ salvo dominado")
    }

    func testCeldaDominada() {
        let m = ExerciseMastery(exerciseId: "e", masteredAt: Date())
        let c = MatrixCell.build(scratchId: "baby", name: "Baby", level: "L1",
                                 baseUnlocked: true, baseProgress: progress(stars: 3), mastery: m)
        XCTAssertEqual(c.state, .mastered)
    }

    // MARK: - PracticeStreak

    private let cal = Calendar(identifier: .gregorian)
    private func day(_ n: Int, from ref: Date) -> Date {
        cal.date(byAdding: .day, value: n, to: ref)!
    }

    func testRachaDeDiasConsecutivos() {
        let today = Date(timeIntervalSince1970: 1_760_000_000)
        let dates = [0, -1, -2, -3].map { day($0, from: today) }
        XCTAssertEqual(PracticeStreak.currentStreak(practiceDates: dates, today: today, calendar: cal), 4)
    }

    func testUnHuecoCortaLaRacha() {
        let today = Date(timeIntervalSince1970: 1_760_000_000)
        let dates = [0, -1, -3, -4].map { day($0, from: today) }   // falta -2
        XCTAssertEqual(PracticeStreak.currentStreak(practiceDates: dates, today: today, calendar: cal), 2)
    }

    func testSiHoyNoHayPracticaPeroAyerSiLaRachaSigueViva() {
        let today = Date(timeIntervalSince1970: 1_760_000_000)
        let dates = [-1, -2].map { day($0, from: today) }
        XCTAssertEqual(PracticeStreak.currentStreak(practiceDates: dates, today: today, calendar: cal), 2)
    }

    func testSiElUltimoDiaEsAnteayerLaRachaEs0() {
        let today = Date(timeIntervalSince1970: 1_760_000_000)
        let dates = [-2, -3, -4].map { day($0, from: today) }
        XCTAssertEqual(PracticeStreak.currentStreak(practiceDates: dates, today: today, calendar: cal), 0)
    }

    func testSinFechasLaRachaEs0() {
        XCTAssertEqual(PracticeStreak.currentStreak(practiceDates: []), 0)
    }

    func testVariasTomasElMismoDiaCuentanUnaVez() {
        let today = Date(timeIntervalSince1970: 1_760_000_000)
        let dates = [day(0, from: today), day(0, from: today).addingTimeInterval(3600),
                     day(-1, from: today)]
        XCTAssertEqual(PracticeStreak.currentStreak(practiceDates: dates, today: today, calendar: cal), 2)
    }

    // MARK: - HomeSummary

    func testAgrupaPorNivelEnOrden() {
        let cells = [
            MatrixCell(scratchId: "a", name: "A", level: "L2", state: .available),
            MatrixCell(scratchId: "b", name: "B", level: "L1", state: .available),
            MatrixCell(scratchId: "c", name: "C", level: "L1", state: .mastered),
        ]
        let s = HomeSummary(cells: cells, streakDays: 3, minutesToday: 12)
        XCTAssertEqual(s.cellsByLevel.map(\.level), ["L1", "L2"])
        XCTAssertEqual(s.cellsByLevel[0].cells.map(\.scratchId), ["b", "c"])
        XCTAssertEqual(s.masteredCount, 1)
        XCTAssertTrue(s.meetsDailyMinimum())
        XCTAssertFalse(HomeSummary(cells: [], streakDays: 0, minutesToday: 4).meetsDailyMinimum())
    }
}
