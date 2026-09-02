// SPDX-License-Identifier: GPL-3.0-only
import XCTest
import Darwin
import CXFAudioCore

/// Base instrumental del motor: `xf_engine_load_instrumental` reproduce un loop
/// pegado al tempo de la sesión (`bpm / native_bpm`). Añadido con el audio de
/// práctica rudimentaria.
final class XFEngineInstrumentalTests: XCTestCase {

    private let sr = 48_000.0

    private func stable(_ values: [Float]) -> UnsafeMutableBufferPointer<Float> {
        let buf = UnsafeMutableBufferPointer<Float>.allocate(capacity: values.count)
        _ = buf.initialize(from: values)
        return buf
    }

    /// Motor con el metrónomo apagado, para medir solo la base.
    private func engine() -> OpaquePointer {
        let e = xf_engine_create(sr, 128)!
        xf_metronome_set_enabled(xf_engine_metronome(e), false)
        return e
    }

    private func sine(_ hz: Double, frames: Int, amp: Float = 0.5) -> [Float] {
        let w = 2.0 * Double.pi * hz / sr
        return (0..<frames).map { amp * Float(sin(w * Double($0))) }
    }

    /// Renderiza `n` frames en bloques de 128 (el tope del engine) y devuelve L.
    private func render(_ e: OpaquePointer, blocks: Int) -> [Float] {
        var acc: [Float] = []
        for _ in 0..<blocks {
            var l = [Float](repeating: 0, count: 128)
            var r = [Float](repeating: 0, count: 128)
            l.withUnsafeMutableBufferPointer { ol in
                r.withUnsafeMutableBufferPointer { or in
                    xf_engine_render(e, nil, nil, ol.baseAddress, or.baseAddress, 128, 0)
                }
            }
            acc += l
        }
        return acc
    }

    private func rms(_ x: [Float]) -> Double {
        (x.reduce(0.0) { $0 + Double($1) * Double($1) } / Double(x.count)).squareRoot()
    }

    /// Magnitud (pico equivalente) de la componente a `hz`.
    private func goertzel(_ x: [Float], hz: Double) -> Double {
        let w = 2.0 * Double.pi * hz / sr
        let c = 2.0 * cos(w)
        var s0 = 0.0, s1 = 0.0, s2 = 0.0
        for v in x { s0 = Double(v) + c * s1 - s2; s2 = s1; s1 = s0 }
        let power = s1 * s1 + s2 * s2 - c * s1 * s2
        return (2.0 * power.squareRoot()) / Double(x.count)
    }

    func testLaBaseSuenaMezclada() {
        let e = engine()
        defer { xf_engine_destroy(e) }
        let loop = stable(sine(1000, frames: 4_800))
        defer { loop.deallocate() }

        xf_engine_load_instrumental(e, loop.baseAddress, Int64(loop.count), 90)
        xf_engine_set_transport(e, 90, 480, true)             // ratio = 1
        xf_engine_set_master_gain(e, 1)

        let out = render(e, blocks: 40)
        // gain de base 0.5 por defecto, seno de amp 0.5 -> RMS ~ 0.5 * 0.354
        XCTAssertEqual(rms(out), 0.5 * (0.5 / 2.0.squareRoot()), accuracy: 0.03)
        XCTAssertGreaterThan(goertzel(out, hz: 1000), goertzel(out, hz: 500))
    }

    func testElRatioSigueAlBPMDeLaSesion() {
        let e = engine()
        defer { xf_engine_destroy(e) }
        let loop = stable(sine(1000, frames: 9_600))
        defer { loop.deallocate() }

        // grabada a 80, sesión a 160 -> se reproduce al doble: 1000 Hz -> ~2000 Hz
        xf_engine_load_instrumental(e, loop.baseAddress, Int64(loop.count), 80)
        xf_engine_set_transport(e, 160, 480, true)
        xf_engine_set_master_gain(e, 1)

        let out = render(e, blocks: 60)
        XCTAssertGreaterThan(goertzel(out, hz: 2000), goertzel(out, hz: 1000),
                             "a ratio 2 el tono se va a 2 kHz")
    }

    func testRecargarConOtroNativeBpmMantieneElPitchNatural() {
        // Simula los botones /2: base "detectada" a 160, luego se reinstala a 80
        // con el transporte tambien a 80 -> el ratio vuelve a 1.0 y el tono
        // sigue en su sitio (1000 Hz), NO se ralentiza.
        let e = engine()
        defer { xf_engine_destroy(e) }
        let loop = stable(sine(1000, frames: 9_600))
        defer { loop.deallocate() }
        xf_engine_set_master_gain(e, 1)

        xf_engine_load_instrumental(e, loop.baseAddress, Int64(loop.count), 160)
        xf_engine_set_transport(e, 160, 480, true)          // ratio 1.0
        _ = render(e, blocks: 20)

        // /2: reinstala con native 80 + transporte 80
        xf_engine_load_instrumental(e, loop.baseAddress, Int64(loop.count), 80)
        xf_engine_set_transport(e, 80, 480, true)
        let out = render(e, blocks: 60)

        XCTAssertGreaterThan(goertzel(out, hz: 1000), goertzel(out, hz: 500) * 3,
                             "sigue en 1 kHz: NO se ha ralentizado")
    }

    func testGananciaCeroSilenciaLaBase() {
        let e = engine()
        defer { xf_engine_destroy(e) }
        let loop = stable(sine(1000, frames: 4_800))
        defer { loop.deallocate() }

        xf_engine_load_instrumental(e, loop.baseAddress, Int64(loop.count), 90)
        xf_engine_set_transport(e, 90, 480, true)
        xf_engine_set_instrumental_gain(e, 0)

        XCTAssertLessThan(rms(render(e, blocks: 30)), 0.01)
    }

    func testTransportePausadoCallaLaBasePeroNoRevienta() {
        let e = engine()
        defer { xf_engine_destroy(e) }
        let loop = stable(sine(1000, frames: 4_800))
        defer { loop.deallocate() }

        xf_engine_load_instrumental(e, loop.baseAddress, Int64(loop.count), 90)
        xf_engine_set_master_gain(e, 1)
        xf_engine_set_transport(e, 90, 480, true)
        XCTAssertGreaterThan(rms(render(e, blocks: 20)), 0.05, "en marcha suena")

        xf_engine_set_transport(e, 90, 480, false)            // pausa (tecla P)
        XCTAssertLessThan(rms(render(e, blocks: 20)), 0.01, "pausado, la base calla")

        xf_engine_set_transport(e, 90, 480, true)             // reanuda
        XCTAssertGreaterThan(rms(render(e, blocks: 20)), 0.05, "vuelve a sonar")
    }

    func testQuitarLaBaseLaCalla() {
        let e = engine()
        defer { xf_engine_destroy(e) }
        let loop = stable(sine(1000, frames: 4_800))
        defer { loop.deallocate() }

        xf_engine_load_instrumental(e, loop.baseAddress, Int64(loop.count), 90)
        xf_engine_set_transport(e, 90, 480, true)
        XCTAssertGreaterThan(rms(render(e, blocks: 20)), 0.05)

        xf_engine_load_instrumental(e, nil, 0, 0)             // quitar
        XCTAssertLessThan(rms(render(e, blocks: 20)), 0.01)
    }

    func testElMuteDeScratchNoTocaLaBase() {
        let e = engine()
        defer { xf_engine_destroy(e) }
        let loop = stable(sine(1000, frames: 4_800))
        let scr  = stable(sine(300, frames: 4_800))
        defer { loop.deallocate(); scr.deallocate() }

        xf_engine_load_instrumental(e, loop.baseAddress, Int64(loop.count), 90)
        xf_engine_load_sample(e, scr.baseAddress, Int64(scr.count))
        xf_engine_set_transport(e, 90, 480, true)
        xf_engine_set_velocity(e, 1.0)
        xf_engine_set_master_gain(e, 1)

        _ = render(e, blocks: 20)                          // que se estabilice
        let both = rms(render(e, blocks: 30))

        xf_engine_set_scratch_gain(e, 0)                   // mute SOLO scratch
        _ = render(e, blocks: 20)                          // rampa de ~5 ms
        let onlyBase = render(e, blocks: 30)

        // la base sigue sonando: sube en 1 kHz, cae en 300 Hz
        XCTAssertGreaterThan(rms(onlyBase), both * 0.4)
        XCTAssertGreaterThan(goertzel(onlyBase, hz: 1000), goertzel(onlyBase, hz: 300) * 3)
    }

    func testSwapSonandoNoRevienta() {
        let e = engine()
        defer { xf_engine_destroy(e) }
        let a = stable(sine(800, frames: 4_800))
        let b = stable(sine(1200, frames: 6_000))
        defer { a.deallocate(); b.deallocate() }

        xf_engine_set_transport(e, 100, 480, true)
        xf_engine_load_instrumental(e, a.baseAddress, Int64(a.count), 100)
        _ = render(e, blocks: 10)
        xf_engine_load_instrumental(e, b.baseAddress, Int64(b.count), 100)   // "sonando"
        _ = render(e, blocks: 10)
        xf_engine_load_instrumental(e, nil, 0, 0)
        XCTAssertLessThan(rms(render(e, blocks: 10)), 0.01)
    }
}
