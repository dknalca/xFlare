// SPDX-License-Identifier: GPL-3.0-only
import XCTest
@testable import XFApp
import XFPersistence

/// B11.1 — asistente de calibración de 3 pasos (`CalibrationWizardModel`).
final class CalibrationWizardTests: XCTestCase {

    private func ready(_ m: CalibrationWizardModel) {
        // deja los 3 pasos en verde
        m.inputDeviceName = "Rane 72 In"
        m.outputDeviceName = "Rane 72 Out"
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
        XCTAssertEqual(m.step, .timecode)
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
        m.advance(); m.advance()   // audio -> timecode -> fader
        XCTAssertEqual(m.step, .fader)
        m.advance()
        XCTAssertEqual(m.step, .fader, "fader es el último")
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

    func testReiniciarCortesVuelveA0SinTocarLosSliders() {
        let m = CalibrationWizardModel()
        for _ in 0..<10 { m.reportFaderCut(cutIn: 0.6, hysteresis: 0.1) }
        XCTAssertTrue(m.isReady(.fader))
        m.resetFaderCuts()
        XCTAssertEqual(m.cutsDetected, 0)
        XCTAssertFalse(m.isReady(.fader), "para poder repetir los diez cortes")
        XCTAssertEqual(m.faderCutIn, 0.6, accuracy: 1e-9, "reiniciar cuenta, no toca el ajuste ya hecho")
        XCTAssertEqual(m.faderHysteresis, 0.1, accuracy: 1e-9)
    }

    // MARK: - aprender MIDI del fader (F.67)

    func testAprenderArmaYElProgresoSeVeEnVivo() {
        let m = CalibrationWizardModel()
        XCTAssertFalse(m.faderLearning)
        m.startFaderLearn()
        XCTAssertTrue(m.faderLearning)
        XCTAssertEqual(m.faderLearnSpan, 0)
        m.reportFaderLearnProgress(span: 64)
        XCTAssertEqual(m.faderLearnSpan, 64)
    }

    func testAprenderConExitoGuardaElCcYDesarma() {
        let m = CalibrationWizardModel()
        m.startFaderLearn()
        m.reportLearnedFader(channel: 16, cc: 8, rawMin: 0, rawMax: 127)
        XCTAssertFalse(m.faderLearning)
        XCTAssertEqual(m.learnedFaderChannel, 16)
        XCTAssertEqual(m.learnedFaderCC, 8)
        XCTAssertEqual(m.learnedFaderMin, 0)
        XCTAssertEqual(m.learnedFaderMax, 127)
    }

    func testAprenderConExitoReiniciaLosCortesContadosAntes() {
        // los cortes de antes de aprender pudieron ir contra el CC equivocado.
        let m = CalibrationWizardModel()
        m.reportFaderCut(cutIn: 0.5, hysteresis: 0.08)
        m.reportFaderCut(cutIn: 0.5, hysteresis: 0.08)
        XCTAssertEqual(m.cutsDetected, 2)
        m.reportLearnedFader(channel: 16, cc: 8, rawMin: 0, rawMax: 127)
        XCTAssertEqual(m.cutsDetected, 0)
    }

    func testCancelarAprenderNoPisaLoYaAprendido() {
        let m = CalibrationWizardModel()
        m.startFaderLearn()
        m.reportLearnedFader(channel: 16, cc: 8, rawMin: 0, rawMax: 127)
        m.startFaderLearn()
        m.cancelFaderLearn()
        XCTAssertFalse(m.faderLearning)
        XCTAssertEqual(m.learnedFaderCC, 8, "un intento cancelado no borra lo aprendido antes")
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
        XCTAssertEqual(cal.updatedAt, now)
    }

    func testDeviceKeyCaeAlNombreDeSalidaSiNoSeDaUno() {
        let m = CalibrationWizardModel()   // deviceKey vacío
        ready(m)
        XCTAssertEqual(m.result()?.deviceKey, "Rane 72 Out")
    }
}
