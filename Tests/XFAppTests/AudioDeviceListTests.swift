// SPDX-License-Identifier: GPL-3.0-only
import CoreAudio
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

    // MARK: - parejas estéreo (selector "como Ableton")

    /// `pairLabel` es lógica pura (sin CoreAudio): se testea directo, sin
    /// depender de qué hardware tenga la máquina que corre el test.
    func testPairLabelFundeNombresLeftRightEnUno() {
        XCTAssertEqual(AudioDeviceList.pairLabel(first: 1, nameL: "Analog 1 Left", nameR: "Analog 1 Right"),
                       "1-2 · Analog 1")
        XCTAssertEqual(AudioDeviceList.pairLabel(first: 7, nameL: "Deck 1 FX Return Left",
                                                  nameR: "Deck 1 FX Return Right"),
                       "7-8 · Deck 1 FX Return")
    }

    func testPairLabelSinNombresEsSoloElRango() {
        XCTAssertEqual(AudioDeviceList.pairLabel(first: 3, nameL: nil, nameR: nil), "3-4")
        XCTAssertEqual(AudioDeviceList.pairLabel(first: 3, nameL: "Mic", nameR: nil), "3-4")
    }

    func testPairLabelNombresIgualesQueNoSonLeftRightSeUsanTalCual() {
        XCTAssertEqual(AudioDeviceList.pairLabel(first: 5, nameL: "Mix", nameR: "Mix"), "5-6 · Mix")
    }

    func testPairLabelNombresQueNoEncajanSoloElRango() {
        // "Left"/"Right" pero de cosas distintas -> no se funden a lo tonto.
        XCTAssertEqual(AudioDeviceList.pairLabel(first: 1, nameL: "Deck 1 Left", nameR: "Deck 2 Right"), "1-2")
        // Nombres sueltos que no encajan en el patron Left/Right ni son iguales.
        XCTAssertEqual(AudioDeviceList.pairLabel(first: 1, nameL: "Mic 1", nameR: "Mic 2"), "1-2")
    }

    /// `stereoPairs` con menos de 2 canales no devuelve nada (no hay pareja
    /// que formar); con un total impar, el canal suelto del final se queda
    /// fuera (nunca a medias).
    func testStereoPairsSinCanalesSuficientesNoDaNada() {
        XCTAssertEqual(AudioDeviceList.stereoPairs(for: 0, scope: kAudioObjectPropertyScopeInput,
                                                    totalChannels: 0), [])
        XCTAssertEqual(AudioDeviceList.stereoPairs(for: 0, scope: kAudioObjectPropertyScopeInput,
                                                    totalChannels: 1), [])
    }

    /// Con un `AudioDeviceID` inventado (0 no es un dispositivo real) no hay
    /// nombres que consultar, así que las parejas salen sin fundir — pero la
    /// cuenta de parejas es correcta y no revienta.
    func testStereoPairsConIdInventadoDaElNumeroCorrectoDeParejas() {
        let pairs = AudioDeviceList.stereoPairs(for: 0xFFFF_FFF0, scope: kAudioObjectPropertyScopeInput,
                                                 totalChannels: 14)
        XCTAssertEqual(pairs.map(\.first), [1, 3, 5, 7, 9, 11, 13])
        for p in pairs { XCTAssertEqual(p.label, "\(p.first)-\(p.first + 1)") }
    }

    /// `outputChannelPairs`/`inputChannelPairs` con un dispositivo real de
    /// esta máquina no revientan y dan tantas parejas como su cuenta de
    /// canales permite.
    func testChannelPairsDeUnDispositivoRealNoRevientan() {
        for d in AudioDeviceList.outputs() {
            let pairs = AudioDeviceList.outputChannelPairs(for: d)
            XCTAssertEqual(pairs.count, d.outputChannels / 2)
        }
        for d in AudioDeviceList.inputs() {
            let pairs = AudioDeviceList.inputChannelPairs(for: d)
            XCTAssertEqual(pairs.count, d.inputChannels / 2)
        }
    }
}
