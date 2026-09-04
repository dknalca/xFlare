// SPDX-License-Identifier: GPL-3.0-only
import XCTest
import CXFAudioCore

/// `xf_player_set_loop`: el cabezal da la vuelta en los extremos en vez de
/// saturarse (para bases instrumentales). Añadido con el audio de práctica.
final class XFPlayerLoopTests: XCTestCase {

    private let sr = 48_000.0

    private func sine(_ hz: Double, frames: Int, amp: Float = 0.5) -> [Float] {
        let w = 2.0 * Double.pi * hz / sr
        return (0..<frames).map { amp * Float(sin(w * Double($0))) }
    }

    /// Velocidad CONSTANTE (F.46: `xf_player_render` ahora toma inicio/fin de
    /// rampa; para estos tests da igual, se pasa el mismo valor en los dos).
    private func render(_ p: OpaquePointer, nframes: Int, v: Double) -> [Float] {
        var out = [Float](repeating: 0, count: nframes)
        out.withUnsafeMutableBufferPointer {
            xf_player_render(p, $0.baseAddress, Int32(nframes), v, v)
        }
        return out
    }

    private func rms(_ x: ArraySlice<Float>) -> Double {
        guard !x.isEmpty else { return 0 }
        return (x.reduce(0.0) { $0 + Double($1) * Double($1) } / Double(x.count)).squareRoot()
    }

    func testSinLoopSeSaturaYSeCongela() {
        let src = sine(1000, frames: 4_800)
        src.withUnsafeBufferPointer { buf in
            let p = xf_player_create(buf.baseAddress, Int64(src.count), 48_000)!
            defer { xf_player_destroy(p) }
            xf_player_set_glide_ms(p, 0)
            _ = render(p, nframes: 20_000, v: 1.0)          // pasa de largo el final
            XCTAssertEqual(xf_player_playhead(p), Double(src.count - 1), accuracy: 1.0)
            // saturado: el cabezal no se mueve -> la salida es constante (congelada),
            // no necesariamente cero
            let tail = render(p, nframes: 2_000, v: 1.0)
            XCTAssertLessThan(Double((tail.max() ?? 0) - (tail.min() ?? 0)), 0.005)
        }
    }

    func testConLoopElCabezalDaLaVueltaYSigueSonando() {
        let src = sine(1000, frames: 4_800)
        src.withUnsafeBufferPointer { buf in
            let p = xf_player_create(buf.baseAddress, Int64(src.count), 48_000)!
            defer { xf_player_destroy(p) }
            xf_player_set_loop(p, true)
            xf_player_set_glide_ms(p, 0)

            let out = render(p, nframes: 12_000, v: 1.0)      // 2,5 vueltas
            // el cabezal ha envuelto: sigue dentro de [0, frames)
            let head = xf_player_playhead(p)
            XCTAssertGreaterThanOrEqual(head, 0)
            XCTAssertLessThan(head, Double(src.count))
            // y la señal no se corta: RMS del último tramo ~ el de un seno
            XCTAssertEqual(rms(out[(out.count - 2_400)...]), 0.5 / 2.0.squareRoot(), accuracy: 0.03)
        }
    }

    func testLoopHaciaAtrasEnvuelvePorElOtroLado() {
        let src = sine(1000, frames: 4_800)
        src.withUnsafeBufferPointer { buf in
            let p = xf_player_create(buf.baseAddress, Int64(src.count), 48_000)!
            defer { xf_player_destroy(p) }
            xf_player_set_loop(p, true)
            xf_player_set_glide_ms(p, 0)
            xf_player_set_playhead(p, 100)

            let out = render(p, nframes: 6_000, v: -1.0)      // cruza el 0 hacia atrás
            let head = xf_player_playhead(p)
            XCTAssertGreaterThanOrEqual(head, 0)
            XCTAssertLessThan(head, Double(src.count))
            XCTAssertGreaterThan(rms(out[(out.count - 2_000)...]), 0.2)
        }
    }

    func testPuertaPorVelocidadMataElZumbidoConElPlatoParado() {
        let src = sine(1000, frames: 4_800)
        src.withUnsafeBufferPointer { buf in
            let p = xf_player_create(buf.baseAddress, Int64(src.count), 48_000)!
            defer { xf_player_destroy(p) }
            xf_player_set_glide_ms(p, 0)
            xf_player_set_playhead(p, 1_200)          // en mitad del sample, no en 0
            xf_player_set_speed_gate(p, 0.12)

            // parado: casi mudo (sin puerta, aqui habria un DC audible)
            XCTAssertLessThan(rms(render(p, nframes: 1_000, v: 0.0)[...]), 0.01)

            // a media puerta: ~media amplitud
            xf_player_set_playhead(p, 1_200)
            let half = rms(render(p, nframes: 2_000, v: 0.06)[...])
            // a plena velocidad: amplitud completa
            xf_player_set_playhead(p, 1_200)
            let full = rms(render(p, nframes: 2_000, v: 1.0)[...])
            XCTAssertGreaterThan(full, 0.2)
            XCTAssertLessThan(half, full * 0.75)
            XCTAssertGreaterThan(half, full * 0.2)
        }
    }

    // MARK: - region de bucle (editor de instrumental: loops de una parte)

    func testRegionDeBucleMantieneElCabezalDentroDeLaParte() {
        let src = sine(1000, frames: 48_000)
        src.withUnsafeBufferPointer { buf in
            let p = xf_player_create(buf.baseAddress, Int64(src.count), 48_000)!
            defer { xf_player_destroy(p) }
            xf_player_set_loop(p, true)
            xf_player_set_glide_ms(p, 0)
            xf_player_set_loop_region(p, 10_000, 14_000)   // 4000 frames
            xf_player_set_playhead(p, 10_000)

            _ = render(p, nframes: 40_000, v: 1.0)          // 10 vueltas a la región
            let head = xf_player_playhead(p)
            XCTAssertGreaterThanOrEqual(head, 10_000)
            XCTAssertLessThan(head, 14_000, "el cabezal nunca sale de [10000, 14000)")
        }
    }

    func testRegionDeBucleSigueSonandoSinCortes() {
        let src = sine(1000, frames: 48_000)
        src.withUnsafeBufferPointer { buf in
            let p = xf_player_create(buf.baseAddress, Int64(src.count), 48_000)!
            defer { xf_player_destroy(p) }
            xf_player_set_loop(p, true)
            xf_player_set_glide_ms(p, 0)
            xf_player_set_loop_region(p, 5_000, 9_000)
            xf_player_set_playhead(p, 5_000)

            let out = render(p, nframes: 20_000, v: 1.0)     // 5 vueltas
            // el bucle de la parte es tan continuo como el del sample entero:
            // el RMS del último tramo sigue siendo el de un seno a 0.5 de amplitud
            XCTAssertEqual(rms(out[(out.count - 3_000)...]), 0.5 / 2.0.squareRoot(), accuracy: 0.03)
        }
    }

    func testRegionInvalidaVuelveAlSampleEntero() {
        let src = sine(1000, frames: 10_000)
        src.withUnsafeBufferPointer { buf in
            let p = xf_player_create(buf.baseAddress, Int64(src.count), 48_000)!
            defer { xf_player_destroy(p) }
            xf_player_set_loop(p, true)
            xf_player_set_glide_ms(p, 0)
            xf_player_set_loop_region(p, 8_000, 9_000)
            xf_player_set_loop_region(p, -1, 0)             // limpiar -> entero
            xf_player_set_playhead(p, 0)

            let out = render(p, nframes: src.count, v: 1.0)  // una vuelta entera
            XCTAssertEqual(xf_player_playhead(p), 0, accuracy: 1.0)
            XCTAssertEqual(rms(out[out.startIndex..<out.endIndex]),
                           rms(src[src.startIndex..<src.endIndex]), accuracy: 0.02)
        }
    }

    func testCambiarLaRegionConElCabezalFueraLoReencaja() {
        let src = sine(1000, frames: 48_000)
        src.withUnsafeBufferPointer { buf in
            let p = xf_player_create(buf.baseAddress, Int64(src.count), 48_000)!
            defer { xf_player_destroy(p) }
            xf_player_set_loop(p, true)
            xf_player_set_glide_ms(p, 0)
            xf_player_set_playhead(p, 40_000)               // lejos de la nueva región
            xf_player_set_loop_region(p, 1_000, 3_000)

            _ = render(p, nframes: 512, v: 1.0)             // un bloque
            let head = xf_player_playhead(p)
            XCTAssertGreaterThanOrEqual(head, 1_000)
            XCTAssertLessThan(head, 3_000, "el wrap del render mete el cabezal en la región")
        }
    }

    func testUnaVueltaEnteraReproduceElSampleCompleto() {
        // a v=1 y sin glide, `frames` muestras ≈ el sample entero
        let src = sine(1000, frames: 4_800)
        src.withUnsafeBufferPointer { buf in
            let p = xf_player_create(buf.baseAddress, Int64(src.count), 48_000)!
            defer { xf_player_destroy(p) }
            xf_player_set_loop(p, true)
            xf_player_set_glide_ms(p, 0)

            let out = render(p, nframes: src.count, v: 1.0)
            XCTAssertEqual(rms(out[out.startIndex..<out.endIndex]),
                           rms(src[src.startIndex..<src.endIndex]), accuracy: 0.02)
            XCTAssertEqual(xf_player_playhead(p), 0, accuracy: 1.0)   // vuelta completa
        }
    }
}
