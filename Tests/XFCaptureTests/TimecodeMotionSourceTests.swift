// SPDX-License-Identifier: GPL-3.0-only
import XCTest
import Darwin   // sin / Double.pi
@testable import XFCapture
import XFPrimitives

/// B6.3 — `TimecodeMotionSource` sobre `CXFTimecode`.
///
/// Se valida con **señal de cuadratura sintética** (dos portadoras senoidales
/// desfasadas 90°), igual que los tests del propio wrapper (B5.2–B5.4). Eso
/// ejercita justo lo que usa el modo relativo (ADR-004/005): velocidad por
/// frecuencia de portadora y sentido por la fase entre canales. La prueba con
/// un vinilo real es el gate de sellado de `CXFTimecode` (B5.5), no de esto.
final class TimecodeMotionSourceTests: XCTestCase {

    private let sr = 48_000.0

    /// PCM estéreo 16 bits: portadora a `carrierHz`, canal secundario
    /// (izquierdo) desfasado `secondaryPhaseDeg` grados respecto al primario
    /// (derecho). Mismo layout que `CXFTimecodeTests`.
    private func signal(carrierHz: Double, secondaryPhaseDeg: Double,
                        seconds: Double, amplitude: Double = 10_000) -> [Int16] {
        let frames = Int(seconds * sr)
        var out = [Int16](repeating: 0, count: frames * 2)
        let w = 2.0 * Double.pi * carrierHz / sr
        let ph2 = secondaryPhaseDeg * Double.pi / 180.0
        for i in 0..<frames {
            let prim = amplitude * sin(w * Double(i))
            let sec  = amplitude * sin(w * Double(i) + ph2)
            out[i * 2 + 0] = clampI16(sec)
            out[i * 2 + 1] = clampI16(prim)
        }
        return out
    }

    private func clampI16(_ x: Double) -> Int16 {
        let r = x.rounded()
        if r >= 32767 { return 32767 }
        if r <= -32767 { return -32767 }
        return Int16(r)
    }

    /// Alimenta la fuente en bloques de `chunk` frames, avanzando el `hostTime`
    /// como haria el driver de audio (1 host tick = 1 ns en el test). Devuelve
    /// el `hostTime` del último bloque entregado.
    @discardableResult
    private func feed(_ src: TimecodeMotionSource, _ pcm: [Int16],
                      startHost: UInt64 = 1_000_000, chunk: Int = 4096) -> UInt64 {
        let frames = pcm.count / 2
        var off = 0
        var host = startHost
        while off < frames {
            let n = min(chunk, frames - off)
            let slice = Array(pcm[(off * 2)..<((off + n) * 2)])
            host += UInt64(Double(n) / sr * 1_000_000_000)   // ns que dura el bloque
            src.submit(slice, hostTime: host)
            off += n
        }
        return host
    }

    // MARK: -

    func testFormatoInvalidoLanza() {
        let src = TimecodeMotionSource(config: .init(format: "no-existe"))
        XCTAssertThrowsError(try src.start()) { err in
            XCTAssertEqual(err as? TimecodeMotionSource.StartError,
                           .decoderCreationFailed(format: "no-existe", sampleRate: 48_000))
        }
        XCTAssertFalse(src.isConnected)
        XCTAssertNil(src.latest())
    }

    func testSampleRateCeroLanza() {
        let src = TimecodeMotionSource(config: .init(sampleRate: 0))
        XCTAssertThrowsError(try src.start())
        XCTAssertFalse(src.isConnected)
    }

    func testSinArrancarNoProduceMuestras() {
        let src = TimecodeMotionSource()
        XCTAssertNil(src.latest())
        src.submit([0, 0, 0, 0], hostTime: 42)   // no debe reventar ni producir nada
        XCTAssertNil(src.latest())
    }

    /// serato_2a tiene `resolution = 1000` → a 1000 Hz la velocidad ≈ 1.0.
    func testVelocidadYPosicionSiguenLaSenal() throws {
        let src = TimecodeMotionSource()
        try src.start()
        XCTAssertTrue(src.isConnected)

        feed(src, signal(carrierHz: 1000, secondaryPhaseDeg: 90, seconds: 2.0))

        let s = try XCTUnwrap(src.latest())
        XCTAssertEqual(abs(s.velocity), 1.0, accuracy: 0.35, "1000 Hz → ~1.0×, dio \(s.velocity)")
        XCTAssertGreaterThan(abs(s.position), 0.3, "la posición integra el movimiento")
        XCTAssertGreaterThan(s.confidence, 0.5, "con señal limpia, confianza alta")
    }

    /// El `hostTime` de la muestra es exactamente el del último bloque entregado.
    func testHostTimeSeConserva() throws {
        let src = TimecodeMotionSource()
        try src.start()
        let last = feed(src, signal(carrierHz: 1000, secondaryPhaseDeg: 90, seconds: 1.0))
        XCTAssertEqual(src.latest()?.hostTime, last)
    }

    /// B5.3/ADR-008 — hamster invierte el signo de la velocidad.
    func testHamsterInvierteElSigno() throws {
        let normal = TimecodeMotionSource()
        try normal.start()
        feed(normal, signal(carrierHz: 1000, secondaryPhaseDeg: 90, seconds: 2.0))
        let vNormal = try XCTUnwrap(normal.latest()).velocity

        let ham = TimecodeMotionSource(config: .init(hamster: true))
        try ham.start()
        feed(ham, signal(carrierHz: 1000, secondaryPhaseDeg: 90, seconds: 2.0))
        let vHam = try XCTUnwrap(ham.latest()).velocity

        XCTAssertGreaterThan(abs(vNormal), 0.4)
        XCTAssertGreaterThan(abs(vHam), 0.4)
        XCTAssertEqual(vNormal.sign == .minus, vHam.sign != .minus, "signos opuestos")
    }

    /// B5.4 — al levantar la aguja (silencio) la confianza cae y no se cuelga.
    func testSilencioBajaLaConfianza() throws {
        let src = TimecodeMotionSource()
        try src.start()
        feed(src, signal(carrierHz: 1000, secondaryPhaseDeg: 90, seconds: 1.5))
        XCTAssertGreaterThan(try XCTUnwrap(src.latest()).confidence, 0.5)

        feed(src, [Int16](repeating: 0, count: Int(1.5 * sr) * 2), startHost: 5_000_000)
        let s = try XCTUnwrap(src.latest())
        XCTAssertLessThan(s.confidence, 0.2, "sin señal, confianza baja")
        XCTAssertLessThan(abs(s.velocity), 0.6, "la velocidad decae hacia 0")
    }

    func testStopLiberaYSePuedeReArrancar() throws {
        let src = TimecodeMotionSource()
        try src.start()
        feed(src, signal(carrierHz: 1000, secondaryPhaseDeg: 90, seconds: 1.0))
        XCTAssertNotNil(src.latest())

        src.stop()
        XCTAssertFalse(src.isConnected)
        XCTAssertNil(src.latest())
        src.submit([0, 0], hostTime: 1)   // parada: ignora

        try src.start()                   // segundo arranque limpio
        XCTAssertTrue(src.isConnected)
        XCTAssertNil(src.latest())
    }

    func testResetPosition() throws {
        let src = TimecodeMotionSource()
        try src.start()
        feed(src, signal(carrierHz: 1000, secondaryPhaseDeg: 90, seconds: 2.0))
        XCTAssertGreaterThan(abs(try XCTUnwrap(src.latest()).position), 0.3)

        src.resetPosition()
        // un bloque corto de silencio para refrescar `latest()` sin mover el disco
        src.submit([Int16](repeating: 0, count: 128), hostTime: 9_000_000)
        XCTAssertEqual(try XCTUnwrap(src.latest()).position, 0, accuracy: 0.05)
    }
}
