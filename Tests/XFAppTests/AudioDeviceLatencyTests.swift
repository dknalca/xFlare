// SPDX-License-Identifier: GPL-3.0-only
import CoreAudio
import XCTest
@testable import XFApp

/// F.48. Igual que `AudioDeviceListTests`: depende del hardware de la máquina
/// que corre el test, así que solo se comprueban invariantes ESTRUCTURALES —
/// nada que dependa de qué dispositivo haya conectado, para que pase igual en
/// CI que con la Rane 72 delante.
final class AudioDeviceLatencyTests: XCTestCase {

    /// El micrófono integrado siempre tiene entrada; si CoreAudio responde,
    /// las cifras tienen que ser razonables (nunca negativas, `totalMs`
    /// coherente con `totalFrames`/`sampleRate`).
    func testMicrofonoIntegradoSiRespondeDaCifrasRazonables() throws {
        guard let mic = AudioDeviceList.inputs().first(where: { $0.name.contains("Microphone") }) else {
            throw XCTSkip("esta máquina no tiene micrófono integrado")
        }
        guard let info = AudioDeviceLatency.info(for: mic.id, scope: kAudioObjectPropertyScopeInput) else {
            throw XCTSkip("CoreAudio no expuso latencia para este dispositivo (pasa con algunos virtuales)")
        }
        XCTAssertGreaterThanOrEqual(info.deviceFrames, 0)
        XCTAssertGreaterThanOrEqual(info.safetyOffsetFrames, 0)
        XCTAssertGreaterThanOrEqual(info.bufferFrames, 0)
        XCTAssertGreaterThan(info.sampleRate, 0, "un dispositivo real siempre trae sample rate")
        XCTAssertEqual(info.totalFrames, info.deviceFrames + info.safetyOffsetFrames + info.bufferFrames)
        XCTAssertEqual(info.totalMs, 1000.0 * Double(info.totalFrames) / info.sampleRate, accuracy: 1e-9)
    }

    /// Un dispositivo sin ENTRADA (p. ej. `Built-in Output`) no tiene un lado
    /// de entrada real que declarar. CoreAudio no siempre rechaza la consulta
    /// en el lado que no existe (algunos dispositivos responden `0` en vez de
    /// fallar la propiedad) — lo que importa es que, si responde, el lado
    /// inexistente da cifras nulas/inofensivas, no un número inventado.
    func testUnDispositivoSoloDeSalidaNoTieneCifrasDeEntradaDeVerdad() throws {
        guard let out = AudioDeviceList.outputs().first(where: { $0.inputChannels == 0 }) else {
            throw XCTSkip("esta máquina no tiene un dispositivo solo-salida a mano")
        }
        if let info = AudioDeviceLatency.info(for: out.id, scope: kAudioObjectPropertyScopeInput) {
            XCTAssertEqual(info.deviceFrames, 0, "sin lado de entrada, CoreAudio no debería declarar frames ahí")
            XCTAssertEqual(info.safetyOffsetFrames, 0)
        }
    }

    /// Un `AudioDeviceID` que no existe no revienta, solo no da información.
    func testIdInventadoNoRevienta() {
        XCTAssertNil(AudioDeviceLatency.info(for: 0xFFFF_FFF0, scope: kAudioObjectPropertyScopeInput))
        XCTAssertNil(AudioDeviceLatency.info(for: 0xFFFF_FFF0, scope: kAudioObjectPropertyScopeOutput))
    }

    /// `totalMs` con `sampleRate == 0` (degenerado) da `0`, no crashea ni
    /// divide entre cero de forma silenciosa.
    func testSampleRateCeroDaTotalMsCero() {
        let info = AudioDeviceLatency.Info(deviceFrames: 10, safetyOffsetFrames: 5,
                                            bufferFrames: 64, sampleRate: 0)
        XCTAssertEqual(info.totalMs, 0)
        XCTAssertEqual(info.totalFrames, 79)
    }

    func testTotalMsSeCalculaBienConUnEjemploDeLibro() {
        // 64 (device) + 32 (safety) + 128 (buffer) = 224 frames a 48 kHz.
        let info = AudioDeviceLatency.Info(deviceFrames: 64, safetyOffsetFrames: 32,
                                            bufferFrames: 128, sampleRate: 48_000)
        XCTAssertEqual(info.totalFrames, 224)
        XCTAssertEqual(info.totalMs, 224.0 / 48_000.0 * 1000.0, accuracy: 1e-9)
    }
}
