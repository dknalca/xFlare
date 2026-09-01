// SPDX-License-Identifier: GPL-3.0-only
import XCTest
@testable import XFEngine

/// B9.3 — desbloqueo por compases consecutivos, no por media
/// (`docs/CURRICULUM.md` §2).
final class UnlockTrackerTests: XCTestCase {

    // Regla tipo `pass` de ejercicio: 0.8 en 8 compases seguidos, sin BPM.
    private func exerciseTracker() -> UnlockTracker {
        UnlockTracker(rule: UnlockRule(accuracy: 0.8, consecutiveBars: 8))
    }

    func testOchoCompasesBuenosSeguidosDesbloquean() {
        var t = exerciseTracker()
        for i in 1...7 {
            XCTAssertFalse(t.record(barAccuracy: 0.85, bpm: 70))
            XCTAssertEqual(t.currentStreak, i)
            XCTAssertEqual(t.barsRemaining, 8 - i)
        }
        XCTAssertTrue(t.record(barAccuracy: 0.85, bpm: 70))
        XCTAssertTrue(t.isUnlocked)
        XCTAssertEqual(t.barsRemaining, 0)
    }

    func testUnCompasFlojoRompeLaRacha_noSeHaceMedia() {
        var t = exerciseTracker()
        for _ in 0..<7 { t.record(barAccuracy: 0.95, bpm: 70) }   // 7 excelentes
        XCTAssertEqual(t.currentStreak, 7)
        t.record(barAccuracy: 0.5, bpm: 70)                       // uno malo
        XCTAssertEqual(t.currentStreak, 0, "la media seria alta, pero el streak se va a 0")
        XCTAssertFalse(t.isUnlocked)
        // y hay que volver a encadenar los 8
        for _ in 0..<8 { t.record(barAccuracy: 0.85, bpm: 70) }
        XCTAssertTrue(t.isUnlocked)
    }

    func testUmbralJustoCuenta() {
        var t = exerciseTracker()
        for _ in 0..<8 { t.record(barAccuracy: 0.8, bpm: 70) }    // exactamente el umbral
        XCTAssertTrue(t.isUnlocked)
    }

    func testJustoPorDebajoNoCuenta() {
        var t = exerciseTracker()
        t.record(barAccuracy: 0.7999, bpm: 70)
        XCTAssertEqual(t.currentStreak, 0)
    }

    func testBestStreakRecuerdaLoMasCercaQueSeEstuvo() {
        var t = exerciseTracker()
        for _ in 0..<5 { t.record(barAccuracy: 0.9, bpm: 70) }
        t.record(barAccuracy: 0.1, bpm: 70)                       // rompe a los 5
        for _ in 0..<3 { t.record(barAccuracy: 0.9, bpm: 70) }
        XCTAssertEqual(t.currentStreak, 3)
        XCTAssertEqual(t.bestStreak, 5, "te quedaste en 5 de 8")
    }

    // MARK: - gate de BPM (regla tipo `unlock` de nivel)

    func testRachaPorDebajoDelBPMminimoNoCuenta() {
        var t = UnlockTracker(rule: UnlockRule(accuracy: 0.8, consecutiveBars: 4, minBPM: 80))
        for _ in 0..<4 { t.record(barAccuracy: 0.95, bpm: 70) }   // precisos pero lentos
        XCTAssertFalse(t.isUnlocked)
        XCTAssertEqual(t.currentStreak, 0)

        for _ in 0..<4 { t.record(barAccuracy: 0.95, bpm: 80) }   // ahora al BPM pedido
        XCTAssertTrue(t.isUnlocked)
    }

    func testUnCompasLentoEnMedioRompeLaRacha() {
        var t = UnlockTracker(rule: UnlockRule(accuracy: 0.8, consecutiveBars: 4, minBPM: 80))
        t.record(barAccuracy: 0.9, bpm: 85)
        t.record(barAccuracy: 0.9, bpm: 85)
        t.record(barAccuracy: 0.9, bpm: 60)                       // bajaste el tempo
        XCTAssertEqual(t.currentStreak, 0)
    }

    // MARK: - latch y reset

    func testDesbloqueoNoSeVaAtrasConUnCompasMalo() {
        var t = UnlockTracker(rule: UnlockRule(accuracy: 0.8, consecutiveBars: 3))
        for _ in 0..<3 { t.record(barAccuracy: 0.9, bpm: 70) }
        XCTAssertTrue(t.isUnlocked)
        t.record(barAccuracy: 0.0, bpm: 70)
        XCTAssertTrue(t.isUnlocked, "una vez desbloqueado, se queda")
        XCTAssertEqual(t.currentStreak, 0)
    }

    func testResetVuelveAlPrincipio() {
        var t = UnlockTracker(rule: UnlockRule(accuracy: 0.8, consecutiveBars: 3))
        for _ in 0..<3 { t.record(barAccuracy: 0.9, bpm: 70) }
        XCTAssertTrue(t.isUnlocked)
        t.reset()
        XCTAssertFalse(t.isUnlocked)
        XCTAssertEqual(t.currentStreak, 0)
        XCTAssertEqual(t.bestStreak, 0)
        XCTAssertEqual(t.barsRemaining, 3)
    }

    func testEsUnValor() {
        var a = UnlockTracker(rule: UnlockRule(accuracy: 0.8, consecutiveBars: 3))
        a.record(barAccuracy: 0.9, bpm: 70)
        a.record(barAccuracy: 0.9, bpm: 70)
        var b = a
        b.record(barAccuracy: 0.9, bpm: 70)   // b desbloquea, a no
        XCTAssertFalse(a.isUnlocked)
        XCTAssertTrue(b.isUnlocked)
    }
}
