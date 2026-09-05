// SPDX-License-Identifier: GPL-3.0-only
import XCTest
@testable import XFApp

/// F.79 (ADR-083) — con un crossfader de HARDWARE real (Rane 72, MIDI CC del
/// MAG FOUR), el propio mezclador ya corta el audio por su circuito
/// analógico cuando el usuario cierra el fader de verdad: silenciar también
/// por software lo corta dos veces, con dos curvas distintas, y el autor lo
/// reportó como "la mesa se comporta raro". Solo se prueba la función pura
/// (`mustMuteScratchInSoftware`) — el resto de `LivePracticeView` es SwiftUI
/// con CoreAudio real detrás, como el resto de la práctica.
final class LivePracticeViewTests: XCTestCase {

    func testFaderAbiertoNuncaSilenciaAunqueNoHayaHardware() {
        XCTAssertFalse(LivePracticeView.mustMuteScratchInSoftware(
            faderClosed: false, hardwareCrossfader: false, machineDrivesFader: false))
        XCTAssertFalse(LivePracticeView.mustMuteScratchInSoftware(
            faderClosed: false, hardwareCrossfader: true, machineDrivesFader: false))
    }

    func testSinHardwareDeVerdadElSoftwareSigueSilenciandoComoSiempre() {
        // raton / trackpad: no hay ningun circuito fisico cortando el audio.
        XCTAssertTrue(LivePracticeView.mustMuteScratchInSoftware(
            faderClosed: true, hardwareCrossfader: false, machineDrivesFader: false))
    }

    func testConHardwareRealYElUsuarioLlevandoElFaderNoSeSilenciaPorSoftware() {
        // la Rane 72 ya corto la señal por su circuito analogico -- hacerlo
        // tambien aqui era el doble corte que sonaba raro.
        XCTAssertFalse(LivePracticeView.mustMuteScratchInSoftware(
            faderClosed: true, hardwareCrossfader: true, machineDrivesFader: false))
    }

    func testConHardwareRealPeroElFantasmaLlevandoElFaderSiSeSilenciaPorSoftware() {
        // en la escucha del "repite conmigo" el fader fisico no se mueve en
        // sincronia con el patron -- ahi el software SI tiene que callar.
        XCTAssertTrue(LivePracticeView.mustMuteScratchInSoftware(
            faderClosed: true, hardwareCrossfader: true, machineDrivesFader: true))
    }
}
