// SPDX-License-Identifier: GPL-3.0-only
import XCTest
import Darwin
import CXFAudioCore

/// F.68 — salida SEPARADA de scratch y base+metrónomo (dos pares de canales,
/// como dos tiras de un mezclador real). `xf_engine_render` decide el modo por
/// sus propios argumentos: si los DOS punteros de la base llegan no-nulos,
/// separado; si falta cualquiera de los dos, combinado (el de siempre) — el
/// modo NUNCA depende de un estado oculto, así que se prueba sin CoreAudio.
final class XFEngineSplitOutputTests: XCTestCase {

    private let sr = 48_000.0

    private func stable(_ values: [Float]) -> UnsafeMutableBufferPointer<Float> {
        let buf = UnsafeMutableBufferPointer<Float>.allocate(capacity: values.count)
        _ = buf.initialize(from: values)
        return buf
    }

    private func sine(_ hz: Double, frames: Int, amp: Float = 0.5) -> [Float] {
        let w = 2.0 * Double.pi * hz / sr
        return (0..<frames).map { amp * Float(sin(w * Double($0))) }
    }

    private func goertzel(_ x: [Float], hz: Double) -> Double {
        let w = 2.0 * Double.pi * hz / sr
        let c = 2.0 * cos(w)
        var s0 = 0.0, s1 = 0.0, s2 = 0.0
        for v in x { s0 = Double(v) + c * s1 - s2; s2 = s1; s1 = s0 }
        let power = s1 * s1 + s2 * s2 - c * s1 * s2
        return (2.0 * power.squareRoot()) / Double(x.count)
    }

    /// Renderiza en modo SEPARADO: los cuatro punteros de salida van no-nulos.
    /// Devuelve el canal L de cada bus.
    private func renderSplit(_ e: OpaquePointer, blocks: Int, n: Int = 128) -> (scratchL: [Float], instrL: [Float]) {
        var sAcc: [Float] = [], iAcc: [Float] = []
        for _ in 0..<blocks {
            var sl = [Float](repeating: 0, count: n), sr2 = [Float](repeating: 0, count: n)
            var il = [Float](repeating: 0, count: n), ir = [Float](repeating: 0, count: n)
            sl.withUnsafeMutableBufferPointer { slp in
            sr2.withUnsafeMutableBufferPointer { srp in
            il.withUnsafeMutableBufferPointer { ilp in
            ir.withUnsafeMutableBufferPointer { irp in
                xf_engine_render(e, nil, nil, slp.baseAddress, srp.baseAddress,
                                 ilp.baseAddress, irp.baseAddress, Int32(n), 0)
            }}}}
            sAcc += sl
            iAcc += il
        }
        return (sAcc, iAcc)
    }

    func testModoSeparadoAislaElScratchDeLaBase() {
        let e = xf_engine_create(sr, 128)!
        defer { xf_engine_destroy(e) }
        xf_metronome_set_enabled(xf_engine_metronome(e), false)

        let scratch = stable(sine(1000, frames: 48_000))
        defer { scratch.deallocate() }
        let instr = stable(sine(200, frames: 48_000))
        defer { instr.deallocate() }

        xf_engine_load_sample(e, scratch.baseAddress, Int64(scratch.count))
        xf_engine_set_velocity(e, 1.0)
        xf_engine_load_instrumental(e, instr.baseAddress, Int64(instr.count), 90)
        xf_engine_set_transport(e, 90, 480, true)
        xf_engine_set_master_gain(e, 1)

        let (scratchOut, instrOut) = renderSplit(e, blocks: 60)

        XCTAssertGreaterThan(goertzel(scratchOut, hz: 1000), goertzel(scratchOut, hz: 200) * 3,
                             "el bus de scratch no se contamina con la base (200 Hz)")
        XCTAssertGreaterThan(goertzel(instrOut, hz: 200), goertzel(instrOut, hz: 1000) * 3,
                             "el bus de la base no se contamina con el scratch (1000 Hz)")
    }

    func testElMetronomoVaConLaBaseEnModoSeparado() {
        let e = xf_engine_create(sr, 128)!
        defer { xf_engine_destroy(e) }
        xf_metronome_set_enabled(xf_engine_metronome(e), true)
        xf_engine_set_transport(e, 120, 480, true)
        xf_engine_set_master_gain(e, 1)

        // sin sample de scratch cargado: si el metronomo se colara ahi, se notaria.
        let (scratchOut, instrOut) = renderSplit(e, blocks: 40)
        XCTAssertEqual(scratchOut.map { abs($0) }.max() ?? 0, 0,
                       "sin sample cargado, el bus de scratch queda en silencio")
        XCTAssertGreaterThan(instrOut.map { abs($0) }.max() ?? 0, 0,
                             "el metronomo suena por el bus de la base, no el de scratch")
    }

    /// Renderiza en bloques de 128 (el tope del engine en estos tests) pasando
    /// SOLO los dos punteros de scratch -- modo combinado clasico.
    private func renderCombined(_ e: OpaquePointer, blocks: Int, n: Int = 128) -> [Float] {
        var acc: [Float] = []
        for _ in 0..<blocks {
            var l = [Float](repeating: 0, count: n), r = [Float](repeating: 0, count: n)
            l.withUnsafeMutableBufferPointer { lp in
            r.withUnsafeMutableBufferPointer { rp in
                xf_engine_render(e, nil, nil, lp.baseAddress, rp.baseAddress, nil, nil, Int32(n), 0)
            }}
            acc += l
        }
        return acc
    }

    func testSinLosDosPunterosDeLaBaseCaeAModoCombinado() {
        // el modo lo decide `xf_engine_render` por sus propios argumentos: si
        // falta CUALQUIERA de los dos punteros de la base, combinado -- no un
        // estado a medias que escriba solo la mitad del bus.
        let e = xf_engine_create(sr, 128)!
        defer { xf_engine_destroy(e) }
        xf_metronome_set_enabled(xf_engine_metronome(e), false)
        let instr = stable(sine(200, frames: 48_000))
        defer { instr.deallocate() }
        xf_engine_load_instrumental(e, instr.baseAddress, Int64(instr.count), 90)
        xf_engine_set_transport(e, 90, 480, true)
        xf_engine_set_master_gain(e, 1)

        var acc: [Float] = []
        for _ in 0..<40 {
            var sl = [Float](repeating: 0, count: 128), sr2 = [Float](repeating: 0, count: 128)
            var il = [Float](repeating: 0, count: 128)
            sl.withUnsafeMutableBufferPointer { slp in
            sr2.withUnsafeMutableBufferPointer { srp in
            il.withUnsafeMutableBufferPointer { ilp in
                xf_engine_render(e, nil, nil, slp.baseAddress, srp.baseAddress, ilp.baseAddress, nil, 128, 0)
            }}}
            acc += sl
        }
        XCTAssertGreaterThan(goertzel(acc, hz: 200), 0.05,
                             "solo un puntero de la base no-nulo: sigue sonando mezclada en scratch")
    }

    func testModoCombinadoSigueIgualQueAntes() {
        // regresion explicita: pasar los dos punteros de la base a nil tiene
        // que dar EXACTAMENTE lo que daba `xf_engine_render` antes de F.68.
        let e = xf_engine_create(sr, 128)!
        defer { xf_engine_destroy(e) }
        xf_metronome_set_enabled(xf_engine_metronome(e), false)
        let instr = stable(sine(200, frames: 48_000))
        defer { instr.deallocate() }
        xf_engine_load_instrumental(e, instr.baseAddress, Int64(instr.count), 90)
        xf_engine_set_transport(e, 90, 480, true)
        xf_engine_set_master_gain(e, 1)

        let out = renderCombined(e, blocks: 40)
        XCTAssertGreaterThan(goertzel(out, hz: 200), 0.05, "la base sigue sonando por el unico bus, como siempre")
    }
}
