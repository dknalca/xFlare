// SPDX-License-Identifier: GPL-3.0-only
import XCTest
@testable import XFApp
import XFPersistence

/// B11.1 — asistente de calibración de 4 pasos (`CalibrationWizardModel`).
final class CalibrationWizardTests: XCTestCase {

    private func ready(_ m: CalibrationWizardModel) {
        // deja los 4 pasos en verde
        m.inputDeviceName = "Rane 72 In"
        m.outputDeviceName = "Rane 72 Out"
        m.reportLatency(roundTripMs: 8.5)
        m.reportTimecode(confidence: 0.9, forwards: true, suggestedHamster: true)
        for _ in 0..<10 { m.reportFaderCut(cutIn: 0.44, hysteresis: 0.07) }
    }

    // MARK: - navegación

    func testArrancaEnAudioYNoAvanzaSinNada() {
        let m = CalibrationWizardModel()
        XCTAssertEqual(m.step, .audio)
        XCTAssertFalse(m.canAdvance)
        m.advance()
        XCTAssertEqual(m.step, .audio, "no avanza sin elegir dispositivos")
    }

    func testAudioListoConLasDosEntradas() {
        let m = CalibrationWizardModel()
        m.inputDeviceName = "in"
        XCTAssertFalse(m.canAdvance)
        m.outputDeviceName = "out"
        XCTAssertTrue(m.canAdvance)
        m.advance()
        XCTAssertEqual(m.step, .latency)
    }

    func testAtrasFuncionaYNoSePasaDelPrincipio() {
        let m = CalibrationWizardModel()
        m.inputDeviceName = "in"; m.outputDeviceName = "out"
        m.advance()
        m.back()
        XCTAssertEqual(m.step, .audio)
        m.back()
        XCTAssertEqual(m.step, .audio, "no hay paso 0")
    }

    func testNoSePasaDelUltimoPaso() {
        let m = CalibrationWizardModel()
        ready(m)
        m.advance(); m.advance(); m.advance()   // audio -> latency -> timecode -> fader
        XCTAssertEqual(m.step, .fader)
        m.advance()
        XCTAssertEqual(m.step, .fader, "fader es el último")
    }

    // MARK: - latencia

    func testLatenciaNoBloqueaPeroPideMedir() {
        let m = CalibrationWizardModel()
        m.inputDeviceName = "in"; m.outputDeviceName = "out"; m.advance()
        XCTAssertEqual(m.step, .latency)
        XCTAssertFalse(m.canAdvance)
        m.reportLatency(roundTripMs: 22)          // rojo, pero medido
        XCTAssertTrue(m.canAdvance, "el semáforo avisa, no bloquea")
        XCTAssertEqual(m.latencyVerdict, .tooHigh)
    }

    func testSemaforoDeLatencia() {
        XCTAssertEqual(LatencyVerdict(roundTripMs: 7),    .good)
        XCTAssertEqual(LatencyVerdict(roundTripMs: 10),   .good)
        XCTAssertEqual(LatencyVerdict(roundTripMs: 10.5), .acceptable)
        XCTAssertEqual(LatencyVerdict(roundTripMs: 15),   .acceptable)
        XCTAssertEqual(LatencyVerdict(roundTripMs: 15.1), .tooHigh)
        XCTAssertTrue(LatencyVerdict(roundTripMs: 9).passesGate)
        XCTAssertFalse(LatencyVerdict(roundTripMs: 18).passesGate)
    }

    // MARK: - timecode

    func testTimecodeNecesitaSenalYPasaLaHamsterDetectada() {
        let m = CalibrationWizardModel()
        m.reportTimecode(confidence: 0.3, forwards: false, suggestedHamster: true)
        XCTAssertFalse(m.isReady(.timecode))
        XCTAssertTrue(m.hamster, "la autodetección propone hamster")
        XCTAssertFalse(m.detectedForwards)

        m.reportTimecode(confidence: 0.75, forwards: true, suggestedHamster: false)
        XCTAssertTrue(m.isReady(.timecode))
        XCTAssertFalse(m.hamster)
    }

    // MARK: - fader

    func testFaderNecesitaDiezCortes() {
        let m = CalibrationWizardModel()
        for i in 1...9 {
            m.reportFaderCut(cutIn: 0.5, hysteresis: 0.08)
            XCTAssertFalse(m.isReady(.fader), "con \(i) cortes aún no")
        }
        m.reportFaderCut(cutIn: 0.47, hysteresis: 0.06)
        XCTAssertTrue(m.isReady(.fader))
        XCTAssertEqual(m.faderCutIn, 0.47, accuracy: 1e-9, "el último corte refina el cut-in")
    }

    // MARK: - resultado

    func testResultadoEsNilHastaCompletarYLuegoTraeTodo() {
        let m = CalibrationWizardModel(deviceKey: "UID-RANE72", profileId: "rane-seventy-two")
        XCTAssertNil(m.result())

        ready(m)
        m.hamster = true
        m.faderCutIn = 0.42
        let now = Date(timeIntervalSince1970: 1_760_000_000)
        let cal = try! XCTUnwrap(m.result(now: now))

        XCTAssertEqual(cal.deviceKey, "UID-RANE72")
        XCTAssertEqual(cal.profileId, "rane-seventy-two")
        XCTAssertEqual(cal.faderCutIn, 0.42, accuracy: 1e-9)
        XCTAssertEqual(cal.hamster, true)
        XCTAssertEqual(cal.latencyMs, 8.5)
        XCTAssertEqual(cal.updatedAt, now)
    }

    func testDeviceKeyCaeAlNombreDeSalidaSiNoSeDaUno() {
        let m = CalibrationWizardModel()   // deviceKey vacío
        ready(m)
        XCTAssertEqual(m.result()?.deviceKey, "Rane 72 Out")
    }
}
