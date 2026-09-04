// SPDX-License-Identifier: GPL-3.0-only
import XCTest
@testable import XFApp

/// Enumeración de dispositivos de audio para el asistente de calibración.
/// Depende del hardware de la máquina que corre el test, así que aquí solo se
/// comprueban invariantes ESTRUCTURALES (nunca revienta, `inputs()`/`outputs()`
/// son subconjuntos consistentes de `all()`) — nada que dependa de qué
/// dispositivos haya conectados, para que pase igual en CI que con la Rane
/// delante.
final class AudioDeviceListTests: XCTestCase {

    func testNoRevientaYLosCanalesNoSonNegativos() {
        let all = AudioDeviceList.all()
        for d in all {
            XCTAssertGreaterThanOrEqual(d.inputChannels, 0)
            XCTAssertGreaterThanOrEqual(d.outputChannels, 0)
            XCTAssertFalse(d.name.isEmpty, "todo dispositivo listado trae nombre")
            XCTAssertFalse(d.uid.isEmpty, "todo dispositivo listado trae UID (hace falta para EngineHandle.start)")
            XCTAssertGreaterThan(d.inputChannels + d.outputChannels, 0,
                                 "solo se listan dispositivos con algún canal")
        }
    }

    func testInputsYOutputsSonElFiltroCorrectoDeAll() {
        let all = AudioDeviceList.all()
        let ins = AudioDeviceList.inputs()
        let outs = AudioDeviceList.outputs()

        XCTAssertEqual(ins, all.filter { $0.inputChannels > 0 })
        XCTAssertEqual(outs, all.filter { $0.outputChannels > 0 })
        for d in ins { XCTAssertGreaterThan(d.inputChannels, 0) }
        for d in outs { XCTAssertGreaterThan(d.outputChannels, 0) }
    }

    /// No es una aserción — imprime lo que ve ESTA máquina, para verificar a
    /// ojo (p. ej. con la Rane 72 conectada) sin hardcodear un nombre de
    /// dispositivo en el test.
    func testImprimeLosDispositivosDeEstaMaquina() {
        for d in AudioDeviceList.all() {
            print("  · \(d.name)  in=\(d.inputChannels) out=\(d.outputChannels)  uid=\(d.uid)")
        }
    }
}
