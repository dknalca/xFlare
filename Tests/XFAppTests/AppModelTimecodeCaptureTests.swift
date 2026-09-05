// SPDX-License-Identifier: GPL-3.0-only
import XCTest
import Combine
@testable import XFApp

/// F.62 — captura de timecode real para el scope de Calibración (paso 3).
///
/// El grueso de esto (`xf_engine_start` con entrada real, `drainInput`,
/// `TimecodeMotionSource.submit`) depende de CoreAudio con un dispositivo de
/// verdad delante — como el resto del host de audio (`xf_engine_start`
/// mismo, `MidiMonitorConnector`…), **no tiene tests de comportamiento real,
/// necesita hardware**. Lo que sí se puede — y debe — probar sin mesa es que
/// nada revienta cuando no hay motor.
final class AppModelTimecodeCaptureTests: XCTestCase {

    private func modelSinMotor() throws -> AppModel {
        let catalog = try CatalogLoader.load(from: RepoContentLoader())
        return AppModel(catalog: catalog, db: try .inMemory())   // engine: nil por defecto
    }

    func testArrancarSinMotorNoRevientaYNoDejaLecturas() throws {
        let m = try modelSinMotor()
        m.startTimecodeCapture()
        XCTAssertTrue(m.scopeReadings.isEmpty)
    }

    func testPararSinHaberArrancadoEsUnNoOpSeguro() throws {
        let m = try modelSinMotor()
        m.stopTimecodeCapture()   // nunca se llamó a startTimecodeCapture()
        XCTAssertTrue(m.scopeReadings.isEmpty)
    }

    func testArrancarYPararSinMotorVariasVecesNoRevienta() throws {
        let m = try modelSinMotor()
        for _ in 0..<3 {
            m.startTimecodeCapture()
            m.stopTimecodeCapture()
        }
        XCTAssertTrue(m.scopeReadings.isEmpty)
    }

    func testOnTimecodeSampleNoSeLlamaSinMotor() throws {
        let m = try modelSinMotor()
        var calls = 0
        m.onTimecodeSample = { _ in calls += 1 }
        m.startTimecodeCapture()
        XCTAssertEqual(calls, 0, "sin motor no hay nada que capturar ni que avisar")
    }

    /// F.65 — `motionSampleEvents` es el mismo tráfico que `onTimecodeSample`
    /// pero como publisher (lo escucha `LivePracticeView` para el vinilo real
    /// en Freestyle/práctica). Mismo criterio: sin motor, no dispara.
    func testMotionSampleEventsNoDisparaSinMotor() throws {
        let m = try modelSinMotor()
        var calls = 0
        let c = m.motionSampleEvents.sink { _ in calls += 1 }
        defer { c.cancel() }
        m.startTimecodeCapture()
        XCTAssertEqual(calls, 0, "sin motor no hay nada que capturar ni que publicar")
    }
}
