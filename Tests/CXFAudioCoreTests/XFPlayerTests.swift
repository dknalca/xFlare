// SPDX-License-Identifier: GPL-3.0-only
import XCTest
import Darwin
import CXFAudioCore

/// B4.3 — reproductor con resampling por velocidad y direccion.
///
/// El foco es **"sin aliasing"**, y eso se mide: se alimenta un tono y se
/// comprueba el espectro de la salida (Goertzel), no se confia en el oido.
final class XFPlayerTests: XCTestCase {

    private let sr = 48_000.0

    // MARK: - utilidades

    /// Sample mono: seno de `hz` durante `seconds`, amplitud `amp`.
    private func sine(_ hz: Double, seconds: Double = 1.0, amp: Float = 0.5) -> [Float] {
        let n = Int(seconds * sr)
        let w = 2.0 * Double.pi * hz / sr
        return (0..<n).map { amp * Float(sin(w * Double($0))) }
    }

    /// Renderiza `nframes` a velocidad constante `v`.
    private func render(_ p: OpaquePointer, nframes: Int, v: Double) -> [Float] {
        var out = [Float](repeating: 0, count: nframes)
        out.withUnsafeMutableBufferPointer {
            xf_player_render(p, $0.baseAddress, Int32(nframes), v)
        }
        return out
    }

    private func rms(_ x: ArraySlice<Float>) -> Double {
        guard !x.isEmpty else { return 0 }
        let s = x.reduce(0.0) { $0 + Double($1) * Double($1) }
        return (s / Double(x.count)).squareRoot()
    }
    private func rms(_ x: [Float]) -> Double { rms(x[x.startIndex..<x.endIndex]) }

    /// Magnitud (amplitud pico equivalente) de la componente a `hz` en `x`.
    private func goertzel(_ x: [Float], hz: Double) -> Double {
        let w = 2.0 * Double.pi * hz / sr
        let c = 2.0 * cos(w)
        var s1 = 0.0, s2 = 0.0
        for v in x {
            let s0 = Double(v) + c * s1 - s2
            s2 = s1; s1 = s0
        }
        let power = s1 * s1 + s2 * s2 - c * s1 * s2
        return 2.0 * max(0, power).squareRoot() / Double(x.count)
    }

    // MARK: - creacion

    func testCrearInvalido() {
        var s: [Float] = [0, 0]
        XCTAssertNil(xf_player_create(nil, 48_000, 48_000))
        s.withUnsafeBufferPointer { XCTAssertNil(xf_player_create($0.baseAddress, 1, 48_000)) }
        s.withUnsafeBufferPointer { XCTAssertNil(xf_player_create($0.baseAddress, 2, 0)) }
    }

    // MARK: - pitch

    func testVelocidad1EsCasiTransparente() {
        let src = sine(1000)
        src.withUnsafeBufferPointer { buf in
            let p = xf_player_create(buf.baseAddress, Int64(src.count), 48_000)!
            defer { xf_player_destroy(p) }
            xf_player_set_glide_ms(p, 0)
            let out = render(p, nframes: 4096, v: 1.0)
            // salta el arranque (retardo de grupo del kernel)
            let body = Array(out[64...])
            let ref = Array(src[64..<(64 + body.count)])
            XCTAssertEqual(rms(body), rms(ref), accuracy: 0.01)
            // el tono de 1 kHz sale con la misma amplitud que entra (< 0,5 dB)
            XCTAssertEqual(goertzel(body, hz: 1000), goertzel(ref, hz: 1000), accuracy: 0.03)
        }
    }

    func testVelocidad2DuplicaElPitch() {
        let src = sine(1000)
        src.withUnsafeBufferPointer { buf in
            let p = xf_player_create(buf.baseAddress, Int64(src.count), 48_000)!
            defer { xf_player_destroy(p) }
            xf_player_set_glide_ms(p, 0)
            let out = Array(render(p, nframes: 8192, v: 2.0)[128...])
            XCTAssertGreaterThan(goertzel(out, hz: 2000), 0.35, "el pitch se duplica")
            XCTAssertLessThan(goertzel(out, hz: 1000), 0.02, "ya no hay energia en 1 kHz")
        }
    }

    func testVelocidadMediaBajaElPitchSinBasura() {
        let src = sine(1000)
        src.withUnsafeBufferPointer { buf in
            let p = xf_player_create(buf.baseAddress, Int64(src.count), 48_000)!
            defer { xf_player_destroy(p) }
            xf_player_set_glide_ms(p, 0)
            let out = Array(render(p, nframes: 8192, v: 0.5)[128...])
            XCTAssertGreaterThan(goertzel(out, hz: 500), 0.45)
            XCTAssertLessThan(goertzel(out, hz: 1000), 0.01)
            XCTAssertLessThan(goertzel(out, hz: 1500), 0.01, "sin imagen")
        }
    }

    // MARK: - antialiasing (la razon de ser de B4.3)

    func testAliasingSuprimidoAlAcelerar() {
        // 20 kHz esta cerca de Nyquist. A v=2.0 mapea a 40 kHz (fuera de banda):
        // con antialiasing la salida es casi silencio; con interpolacion lineal
        // el alias a |48k - 40k| = 8 kHz saldria con fuerza.
        let src = sine(20_000, amp: 0.5)
        src.withUnsafeBufferPointer { buf in
            let p = xf_player_create(buf.baseAddress, Int64(src.count), 48_000)!
            defer { xf_player_destroy(p) }
            xf_player_set_glide_ms(p, 0)
            let out = Array(render(p, nframes: 8192, v: 2.0)[256...])
            XCTAssertLessThan(rms(out), 0.03, "el contenido fuera de banda se filtra, no se pliega")
            XCTAssertLessThan(goertzel(out, hz: 8000), 0.01, "sin alias en 8 kHz")
        }
    }

    func testUnBarridoRapidoNoMeteAliasAudible() {
        // seno a 15 kHz reproducido a 3x -> 45 kHz, alias potencial en 3 kHz.
        let src = sine(15_000, amp: 0.5)
        src.withUnsafeBufferPointer { buf in
            let p = xf_player_create(buf.baseAddress, Int64(src.count), 48_000)!
            defer { xf_player_destroy(p) }
            xf_player_set_glide_ms(p, 0)
            let out = Array(render(p, nframes: 8192, v: 3.0)[256...])
            XCTAssertLessThan(goertzel(out, hz: 3000), 0.01)
        }
    }

    func testAliasingSuprimidoPorEncimaDelTechoAntiguoDe8x() {
        // F.45: la tabla de ratios sube de 7 cubos (techo 8x) a 24, hasta 16x.
        // A v=12 (fuera del rango que existia antes) un scratch rapido de
        // verdad ya no se queda pegado al kernel de 8x (sobre-filtrado, mas
        // apagado de lo necesario): usa un cubo mas fino y SIGUE sin aliasing.
        // 15 kHz a 12x -> 180 kHz aparentes; doblado a la banda de 48 kHz
        // (Nyquist 24 kHz) el alias potencial cae en 12 kHz.
        let src = sine(15_000, amp: 0.5)
        src.withUnsafeBufferPointer { buf in
            let p = xf_player_create(buf.baseAddress, Int64(src.count), 48_000)!
            defer { xf_player_destroy(p) }
            xf_player_set_glide_ms(p, 0)
            let out = Array(render(p, nframes: 8192, v: 12.0)[256...])
            XCTAssertLessThan(goertzel(out, hz: 12_000), 0.01, "sin alias en 12 kHz")
        }
    }

    // MARK: - direccion, parada, bordes

    func testReversoLeeHaciaAtras() {
        let ramp = (0..<10_000).map { Float($0) / 10_000.0 }   // rampa creciente
        ramp.withUnsafeBufferPointer { buf in
            let p = xf_player_create(buf.baseAddress, Int64(ramp.count), 48_000)!
            defer { xf_player_destroy(p) }
            xf_player_set_glide_ms(p, 0)
            xf_player_set_playhead(p, 5000)
            let out = render(p, nframes: 1000, v: -1.0)
            XCTAssertLessThan(out.last!, out.first!, "la rampa se lee al reves -> decrece")
            XCTAssertLessThan(xf_player_playhead(p), 5000)
        }
    }

    func testParadoMantieneElCabezalYSacaDC() {
        let src = sine(1000, amp: 0.9)
        src.withUnsafeBufferPointer { buf in
            let p = xf_player_create(buf.baseAddress, Int64(src.count), 48_000)!
            defer { xf_player_destroy(p) }
            xf_player_set_glide_ms(p, 0)
            xf_player_set_playhead(p, 1234.0)
            let out = render(p, nframes: 256, v: 0.0)
            XCTAssertEqual(xf_player_playhead(p), 1234.0, accuracy: 1e-9)
            // todas las muestras iguales (el cabezal no se mueve)
            XCTAssertLessThan(rms(out.map { $0 - out[0] }), 1e-6)
        }
    }

    func testGananciaDCUnidad() {
        let dc = [Float](repeating: 1.0, count: 4096)
        dc.withUnsafeBufferPointer { buf in
            let p = xf_player_create(buf.baseAddress, Int64(dc.count), 48_000)!
            defer { xf_player_destroy(p) }
            xf_player_set_glide_ms(p, 0)
            let out = Array(render(p, nframes: 2048, v: 1.0)[64...])
            XCTAssertEqual(rms(out), 1.0, accuracy: 1e-3, "el kernel esta normalizado a ganancia 1")
        }
    }

    func testCabezalSeSaturaAlFinal() {
        let src = sine(1000)
        src.withUnsafeBufferPointer { buf in
            let p = xf_player_create(buf.baseAddress, Int64(src.count), 48_000)!
            defer { xf_player_destroy(p) }
            xf_player_set_glide_ms(p, 0)
            xf_player_set_playhead(p, Double(src.count - 10))
            _ = render(p, nframes: 1000, v: 1.0)    // pide mas de lo que queda
            XCTAssertEqual(xf_player_playhead(p), Double(src.count - 1), accuracy: 1e-9)
        }
    }

    // MARK: - sin clicks

    func testSinDiscontinuidadEntreBloques() {
        let src = sine(440, amp: 0.5)
        src.withUnsafeBufferPointer { buf in
            let p = xf_player_create(buf.baseAddress, Int64(src.count), 48_000)!
            defer { xf_player_destroy(p) }
            xf_player_set_glide_ms(p, 0)
            let a = render(p, nframes: 128, v: 1.0)
            let b = render(p, nframes: 128, v: 1.0)
            let joined = a + b
            let diffs = (1..<joined.count).map { abs(joined[$0] - joined[$0 - 1]) }
            let seam = diffs[127]
            let typical = diffs.max()!
            XCTAssertLessThan(seam, typical * 1.5, "el salto en la costura no destaca")
        }
    }

    func testCambioDeVelocidadSeDesliza() {
        let src = sine(1000)
        src.withUnsafeBufferPointer { buf in
            let p = xf_player_create(buf.baseAddress, Int64(src.count), 48_000)!
            defer { xf_player_destroy(p) }
            xf_player_set_glide_ms(p, 20)          // ~20 ms para alcanzar
            _ = render(p, nframes: 1, v: 1.0)
            XCTAssertLessThan(xf_player_velocity(p), 0.2, "no salta")
            _ = render(p, nframes: 4000, v: 1.0)   // ~83 ms
            XCTAssertEqual(xf_player_velocity(p), 1.0, accuracy: 0.02)
        }
    }
}
