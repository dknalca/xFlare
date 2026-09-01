// SPDX-License-Identifier: GPL-3.0-only
import XCTest
@testable import XFPersistence

/// B10.4 — calibración por dispositivo.
final class CalibrationTests: XCTestCase {

    private let t0 = Date(timeIntervalSince1970: 1_760_000_000)

    private func cal(_ key: String, profile: String = "rane-seventy-two",
                     cutIn: Double = 0.42, at: TimeInterval = 0) -> DeviceCalibration {
        DeviceCalibration(deviceKey: key, profileId: profile, faderCutIn: cutIn,
                          faderHysteresis: 0.08, hamster: true, latencyMs: 9.3,
                          updatedAt: t0.addingTimeInterval(at))
    }

    func testGuardaYLeeRoundTrip() throws {
        let db = try XFDatabase.inMemory()
        let c = cal("AppleUSBAudio:Rane 72")
        try db.saveCalibration(c)
        XCTAssertEqual(try db.calibration(deviceKey: "AppleUSBAudio:Rane 72"), c)
    }

    func testGuardarDosVecesReemplaza() throws {
        let db = try XFDatabase.inMemory()
        try db.saveCalibration(cal("dev", cutIn: 0.40, at: 0))
        try db.saveCalibration(cal("dev", cutIn: 0.55, at: 100))
        let back = try XCTUnwrap(db.calibration(deviceKey: "dev"))
        XCTAssertEqual(back.faderCutIn, 0.55)
        XCTAssertEqual(back.updatedAt, t0.addingTimeInterval(100))
    }

    func testListadoPorFechaDesc() throws {
        let db = try XFDatabase.inMemory()
        try db.saveCalibration(cal("viejo", at: 0))
        try db.saveCalibration(cal("nuevo", at: 500))
        try db.saveCalibration(cal("medio", at: 200))
        XCTAssertEqual(try db.allCalibrations().map(\.deviceKey), ["nuevo", "medio", "viejo"])
    }

    func testBorrar() throws {
        let db = try XFDatabase.inMemory()
        try db.saveCalibration(cal("dev"))
        try db.deleteCalibration(deviceKey: "dev")
        XCTAssertNil(try db.calibration(deviceKey: "dev"))
        XCTAssertNoThrow(try db.deleteCalibration(deviceKey: "dev"), "borrar lo que no está no falla")
    }

    func testLatenciaOpcional() throws {
        let db = try XFDatabase.inMemory()
        var c = cal("dev"); c.latencyMs = nil
        try db.saveCalibration(c)
        XCTAssertNil(try db.calibration(deviceKey: "dev")?.latencyMs)
    }
}
