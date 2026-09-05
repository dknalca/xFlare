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
        m.startTimecodeCapture(owner: .practice)
        XCTAssertTrue(m.scopeReadings.isEmpty)
    }

    func testPararSinHaberArrancadoEsUnNoOpSeguro() throws {
        let m = try modelSinMotor()
        m.stopTimecodeCapture(owner: .practice)   // nunca se llamó a startTimecodeCapture()
        XCTAssertTrue(m.scopeReadings.isEmpty)
    }

    func testArrancarYPararSinMotorVariasVecesNoRevienta() throws {
        let m = try modelSinMotor()
        for _ in 0..<3 {
            m.startTimecodeCapture(owner: .practice)
            m.stopTimecodeCapture(owner: .practice)
        }
        XCTAssertTrue(m.scopeReadings.isEmpty)
    }

    func testOnTimecodeSampleNoSeLlamaSinMotor() throws {
        let m = try modelSinMotor()
        var calls = 0
        m.onTimecodeSample = { _ in calls += 1 }
        m.startTimecodeCapture(owner: .practice)
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
        m.startTimecodeCapture(owner: .practice)
        XCTAssertEqual(calls, 0, "sin motor no hay nada que capturar ni que publicar")
    }

    /// F.76 (ADR-080) — diagnóstico de deriva: arranca "sin dato" (no hay
    /// nada con qué comparar todavía) y sin motor se queda así, como el
    /// resto de este fichero. El cálculo real (`pollTimecode`, con
    /// `TimecodeMotionSource.absoluteLock` de verdad) necesita CoreAudio con
    /// un dispositivo delante, igual que el resto de esta suite.
    func testDiagnosticoDeDerivaArrancaSinDatoYSinMotorSeQuedaAsi() throws {
        let m = try modelSinMotor()
        XCTAssertNil(m.timecodeDriftMs)
        XCTAssertEqual(m.timecodeLockedFraction, 0)
        m.startTimecodeCapture(owner: .practice)
        XCTAssertNil(m.timecodeDriftMs, "sin motor no hay lecturas que comparar")
        XCTAssertEqual(m.timecodeLockedFraction, 0)
    }

    // MARK: - F.87 (ADR-089): "quién manda" en la captura de timecode

    /// El bug real en la Rane 72: `LivePracticeView` (`onDisappear`) y
    /// `AppRootView` (`onChange(of: model.screen)`) reaccionan CADA UNA a su
    /// propia transición de pantalla al entrar/salir de Calibración, sin que
    /// SwiftUI garantice el orden. Sin esta regla, una llamada tardía de la
    /// pantalla que ya perdió la carrera paraba la captura que la otra
    /// ACABABA de abrir — sonido doblado, instrumental desajustada de la
    /// rejilla, hasta una dirección de giro mal detectada a mitad de
    /// scratch (dos decoders leyendo el mismo audio a la vez).
    func testStopSoloActuaSiElOwnerCoincideConQuienAbrioLaCaptura() {
        XCTAssertTrue(AppModel.shouldActOnStopRequest(owner: .practice, current: .practice))
        XCTAssertTrue(AppModel.shouldActOnStopRequest(owner: .calibration, current: .calibration))
    }

    func testStopDeUnaPantallaQuePerdioLaCarreraEsUnNoOp() {
        // AppRootView entró en Calibración y ya abrió su propia captura,
        // pero el onDisappear (tardío) de la práctica vieja todavía llega:
        // no debe tocar la captura de Calibración.
        XCTAssertFalse(AppModel.shouldActOnStopRequest(owner: .practice, current: .calibration))
        // Y al revés: Calibración cerrando algo que ya es de práctica.
        XCTAssertFalse(AppModel.shouldActOnStopRequest(owner: .calibration, current: .practice))
    }

    func testStopSinNadieQueLaAbrieraEsUnNoOpSeguro() {
        XCTAssertFalse(AppModel.shouldActOnStopRequest(owner: .practice, current: nil))
        XCTAssertFalse(AppModel.shouldActOnStopRequest(owner: .calibration, current: nil))
    }

    // MARK: - F.76 (ADR-080): el cálculo puro de la deriva

    /// El primer enganche fija el ancla y no reporta deriva todavía (0 por
    /// definición: no ha habido tiempo de separarse de nada).
    func testTimecodeDriftElPrimerEngancheFijaElAnclaEnCero() {
        let (drift, anchor) = AppModel.timecodeDrift(
            integratedNow: 0.02, absoluteNow: 136.567, anchor: nil)
        XCTAssertEqual(drift, 0)
        XCTAssertEqual(anchor.integrated, 0.02)
        XCTAssertEqual(anchor.absolute, 136.567)
    }

    /// Reproduce EXACTAMENTE el bug encontrado con la Rane 72 real: la
    /// primera versión de esta función (sin ancla, `integrada - absoluta` a
    /// pelo) daba "-136567 ms" porque comparaba el reloj del motor (arranca
    /// en 0) contra el reloj del vinilo físico (dondequiera que esté la
    /// aguja en el disco de ~12 min) sin anclar los ceros primero. Con la
    /// misma posición absoluta enorme, si la integrada avanza EXACTAMENTE
    /// igual que la absoluta desde el ancla (sin deriva real de por medio),
    /// el resultado tiene que ser ~0 -- no la posición del disco.
    func testTimecodeDriftNoConfundeLaPosicionDelDiscoConDeriva() {
        let anchor = (integrated: 0.02, absolute: 136.567)
        // 3 segundos después, las dos avanzaron lo mismo (3 s): CERO deriva.
        let (drift, _) = AppModel.timecodeDrift(
            integratedNow: 0.02 + 3.0, absoluteNow: 136.567 + 3.0, anchor: anchor)
        XCTAssertEqual(drift, 0, accuracy: 1e-9,
                       "misma posición absoluta enorme, pero SIN separarse -> deriva 0, no -136567 ms")
    }

    /// Si las dos posiciones SÍ se separan desde el ancla, esa separación (no
    /// la posición absoluta en sí) es la deriva, en milisegundos.
    func testTimecodeDriftMideSoloLaSeparacionDesdeElAncla() {
        let anchor = (integrated: 10.0, absolute: 500.0)
        // integrada avanza 2.010 s, absoluta avanza 2.000 s -> se separan 10 ms.
        let (drift, _) = AppModel.timecodeDrift(
            integratedNow: 10.0 + 2.010, absoluteNow: 500.0 + 2.000, anchor: anchor)
        XCTAssertEqual(drift, 10.0, accuracy: 1e-6)
    }

    /// El ancla, una vez fijada, no cambia en llamadas siguientes (se sigue
    /// devolviendo la MISMA referencia).
    func testTimecodeDriftElAnclaNoCambiaTrasFijarse() {
        let anchor = (integrated: 1.0, absolute: 2.0)
        let (_, sameAnchor) = AppModel.timecodeDrift(
            integratedNow: 5.0, absoluteNow: 6.0, anchor: anchor)
        XCTAssertEqual(sameAnchor.integrated, 1.0)
        XCTAssertEqual(sameAnchor.absolute, 2.0)
    }
}
