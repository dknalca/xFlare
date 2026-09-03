// SPDX-License-Identifier: GPL-3.0-only
import XCTest
import Darwin
import CXFAudioCore

/// B4.2 — nucleo RT del motor de audio (`xf_engine_render`) y parametros de
/// prioridad de tiempo real (`xf_rt`). El host CoreAudio (`xf_engine_start`) no
/// se prueba: necesita un dispositivo.
final class XFEngineRTTests: XCTestCase {

    private let sr = 48_000.0

    private func render(_ e: OpaquePointer, inL: [Float]?, inR: [Float]?,
                        n: Int, host: UInt64 = 0) -> (l: [Float], r: [Float]) {
        var outL = [Float](repeating: 0, count: n)
        var outR = [Float](repeating: 0, count: n)
        outL.withUnsafeMutableBufferPointer { ol in
            outR.withUnsafeMutableBufferPointer { or in
                func go(_ il: UnsafePointer<Float>?, _ ir: UnsafePointer<Float>?) {
                    xf_engine_render(e, il, ir, ol.baseAddress, or.baseAddress, Int32(n), host)
                }
                if let inL, let inR {
                    inL.withUnsafeBufferPointer { il in inR.withUnsafeBufferPointer { ir in
                        go(il.baseAddress, ir.baseAddress)
                    }}
                } else { go(nil, nil) }
            }
        }
        return (outL, outR)
    }

    private func drainRing(_ e: OpaquePointer, maxInt16: Int) -> [Int16] {
        let ring = xf_engine_input_ring(e)
        var buf = [Int16](repeating: 0, count: maxInt16)
        let got = buf.withUnsafeMutableBytes { xf_ring_read(ring, $0.baseAddress, $0.count) }
        return Array(buf.prefix(got / MemoryLayout<Int16>.size))
    }

    private func rms(_ x: [Float]) -> Double {
        (x.reduce(0.0) { $0 + Double($1) * Double($1) } / Double(x.count)).squareRoot()
    }

    // MARK: - xf_rt

    func testParametrosDeTimeConstraint() {
        var p: UInt32 = 0, c: UInt32 = 0, cons: UInt32 = 0
        XCTAssertTrue(xf_rt_time_constraint_params(48_000, 64, &p, &c, &cons))
        XCTAssertGreaterThan(p, 0)
        XCTAssertGreaterThan(c, 0)
        XCTAssertLessThanOrEqual(c, p, "computation <= period")
        XCTAssertGreaterThanOrEqual(cons, c, "constraint >= computation")
        XCTAssertLessThanOrEqual(cons, p, "constraint <= period")

        XCTAssertFalse(xf_rt_time_constraint_params(0, 64, &p, &c, &cons))
        XCTAssertFalse(xf_rt_time_constraint_params(48_000, 0, &p, &c, &cons))
    }

    func testBufferMasGrandePeriodoMasGrande() {
        var p64: UInt32 = 0, p128: UInt32 = 0
        var c1: UInt32 = 0, c2: UInt32 = 0, k1: UInt32 = 0, k2: UInt32 = 0
        _ = xf_rt_time_constraint_params(48_000, 64, &p64, &c1, &k1)
        _ = xf_rt_time_constraint_params(48_000, 128, &p128, &c2, &k2)
        XCTAssertEqual(Double(p128), Double(p64) * 2, accuracy: Double(p64) * 0.05)
    }

    // MARK: - creacion

    func testCrear() {
        XCTAssertNil(xf_engine_create(0, 64))
        XCTAssertNil(xf_engine_create(48_000, 0))
        let e = xf_engine_create(48_000, 128)!
        defer { xf_engine_destroy(e) }
        XCTAssertEqual(xf_engine_api_version(), 1)
        XCTAssertNotNil(xf_engine_input_ring(e))
        XCTAssertNotNil(xf_engine_metronome(e))
    }

    // MARK: - entrada -> ring

    func testLaEntradaVaAlRingComoInt16Estereo() {
        let e = xf_engine_create(sr, 128)!
        defer { xf_engine_destroy(e) }
        let inL = (0..<64).map { Float(sin(Double($0) * 0.2)) * 0.5 }
        let inR = (0..<64).map { Float(-sin(Double($0) * 0.2)) * 0.5 }
        _ = render(e, inL: inL, inR: inR, n: 64)

        let ring = xf_engine_input_ring(e)
        XCTAssertEqual(xf_ring_read_available(ring), 64 * 2 * 2, "64 frames estereo int16")
        let pcm = drainRing(e, maxInt16: 256)
        XCTAssertEqual(pcm.count, 128)
        // primer frame: L,R intercalados
        XCTAssertEqual(Int(pcm[0]), Int((inL[0] * 32767).rounded()), accuracy: 2)
        XCTAssertEqual(Int(pcm[1]), Int((inR[0] * 32767).rounded()), accuracy: 2)
    }

    func testSinEntradaNoEscribeEnElRingPeroSacaSalida() {
        let e = xf_engine_create(sr, 128)!
        defer { xf_engine_destroy(e) }
        xf_engine_set_transport(e, 120, 480, true)
        xf_metronome_set_enabled(xf_engine_metronome(e), true)
        _ = render(e, inL: nil, inR: nil, n: 64)
        XCTAssertEqual(xf_ring_read_available(xf_engine_input_ring(e)), 0, "sin entrada, ring vacio")
    }

    func testNframesSeSaturaAMaxFrames() {
        let e = xf_engine_create(sr, 128)!
        defer { xf_engine_destroy(e) }
        let bigL = [Float](repeating: 0.3, count: 256)
        _ = render(e, inL: bigL, inR: bigL, n: 256)   // pide 256, max 128
        XCTAssertEqual(xf_ring_read_available(xf_engine_input_ring(e)), 128 * 2 * 2)
    }

    // MARK: - salida: reproductor + metronomo

    /// Sample con direccion estable (no la de un Array temporal): el engine no
    /// lo copia, tiene que seguir vivo mientras se renderiza.
    private func stableSample(_ values: [Float]) -> UnsafeMutableBufferPointer<Float> {
        let buf = UnsafeMutableBufferPointer<Float>.allocate(capacity: values.count)
        _ = buf.initialize(from: values)
        return buf
    }

    func testElReproductorSuena() {
        let e = xf_engine_create(sr, 128)!
        defer { xf_engine_destroy(e) }
        let sample = stableSample((0..<48_000).map {
            Float(sin(2.0 * .pi * 1000.0 * Double($0) / 48_000)) * 0.5
        })
        defer { sample.deallocate() }
        xf_engine_load_sample(e, sample.baseAddress, Int64(sample.count))
        xf_engine_set_master_gain(e, 1)
        xf_engine_set_velocity(e, 1.0)

        // en bloques de 128 (el tope del engine); la velocidad se estabiliza
        var acc: [Float] = []
        for _ in 0..<40 { acc += render(e, inL: nil, inR: nil, n: 128).l }
        XCTAssertGreaterThan(rms(Array(acc.suffix(2048))), 0.2, "el sample suena")
    }

    func testGananciaCeroSilenciaLaSalida() {
        let e = xf_engine_create(sr, 128)!
        defer { xf_engine_destroy(e) }
        let sample = stableSample([Float](repeating: 0.8, count: 4096))
        defer { sample.deallocate() }
        xf_engine_load_sample(e, sample.baseAddress, Int64(sample.count))
        xf_engine_set_velocity(e, 1.0)
        xf_engine_set_master_gain(e, 0)
        let out = render(e, inL: nil, inR: nil, n: 512).l
        XCTAssertEqual(out.map { abs($0) }.max() ?? 0, 0, "gain 0 -> silencio")
    }

    private func goertzel(_ x: [Float], _ hz: Double) -> Double {
        let w = 2.0 * Double.pi * hz / sr
        let c = 2.0 * cos(w)
        var s1 = 0.0, s2 = 0.0
        for v in x { let s0 = Double(v) + c * s1 - s2; s2 = s1; s1 = s0 }
        return 2.0 * max(0, s1 * s1 + s2 * s2 - c * s1 * s2).squareRoot() / Double(x.count)
    }

    /// EQ del sample: subir Lo realza los graves del scratch; la base NO se toca.
    func testLaEqDelSampleRealzaSuBandaYNoTocaLaBase() {
        // --- (1) sobre el scratch: sample de 120 Hz, Lo +12 dB -> mas fuerte ---
        let e = xf_engine_create(sr, 128)!
        defer { xf_engine_destroy(e) }
        let sample = stableSample((0..<96_000).map {
            Float(sin(2.0 * .pi * 120.0 * Double($0) / 48_000)) * 0.4
        })
        defer { sample.deallocate() }
        xf_engine_load_sample(e, sample.baseAddress, Int64(sample.count))
        xf_engine_set_master_gain(e, 1)
        xf_engine_set_velocity(e, 1.0)

        func run() -> [Float] {
            xf_engine_seek_scratch(e, 0)
            var acc: [Float] = []
            for _ in 0..<80 { acc += render(e, inL: nil, inR: nil, n: 128).l }
            return Array(acc.suffix(4096))
        }
        let flat = goertzel(run(), 120)
        xf_engine_set_sample_eq(e, 12, 0, 0)
        let boosted = goertzel(run(), 120)
        XCTAssertGreaterThan(boosted / max(flat, 1e-9), 1.8, "Lo +12 dB sube los graves del scratch")

        // --- (2) sobre la base instrumental: la EQ del sample NO la toca ---
        let e2 = xf_engine_create(sr, 128)!
        defer { xf_engine_destroy(e2) }
        let loop = stableSample((0..<4_800).map {
            Float(sin(2.0 * .pi * 120.0 * Double($0) / 48_000)) * 0.4
        })
        defer { loop.deallocate() }
        xf_engine_load_instrumental(e2, loop.baseAddress, Int64(loop.count), 90)
        xf_engine_set_transport(e2, 90, 480, true)
        xf_engine_set_master_gain(e2, 1)

        func runBase() -> [Float] {
            var acc: [Float] = []
            for _ in 0..<80 { acc += render(e2, inL: nil, inR: nil, n: 128).l }
            return Array(acc.suffix(4096))
        }
        let baseFlat = goertzel(runBase(), 120)
        xf_engine_set_sample_eq(e2, 12, 0, 0)
        let baseAfter = goertzel(runBase(), 120)
        XCTAssertEqual(baseAfter, baseFlat, accuracy: baseFlat * 0.05,
                       "la EQ del sample no toca la base instrumental")
    }

    /// ADR-042 — el ancla NO mueve el cabezal (lo hace la velocidad): es un TRIM
    /// anti-deriva ACOTADO. Se comprueba que (1) con velocidad coherente el
    /// cabezal va pegado al objetivo, (2) el trim por bloque esta topado — nunca
    /// puede sonar como un barrido — y (3) soltar el ancla lo desactiva.
    func testElAnclaEsUnTrimAcotado() {
        let e = xf_engine_create(sr, 128)!
        defer { xf_engine_destroy(e) }
        let sample = stableSample((0..<96_000).map { Float(sin(Double($0) * 0.01)) * 0.3 })
        defer { sample.deallocate() }
        xf_engine_load_sample(e, sample.baseAddress, Int64(sample.count))

        // (1) velocidad 1.0 (pitch normal) + objetivo coherente con esa marcha:
        //     el cabezal sigue a la velocidad y el trim apenas pinta nada.
        xf_engine_set_velocity(e, 1.0)
        for k in 0..<300 {
            xf_engine_set_scratch_target(e, Double(k + 1) * 128.0)
            _ = render(e, inL: nil, inR: nil, n: 128)
        }
        XCTAssertEqual(xf_engine_scratch_playhead(e), 300.0 * 128.0, accuracy: 300,
                       "el cabezal va pegado al objetivo")

        // dejar que la velocidad interna del player caiga a 0 (glide 5 ms) con
        // el ancla suelta, para medir SOLO el trim despues.
        xf_engine_set_velocity(e, 0)
        xf_engine_set_scratch_target(e, -1)
        for _ in 0..<40 { _ = render(e, inL: nil, inR: nil, n: 128) }

        // (2) cabezal quieto y objetivo lejisimos: el trim esta topado a ~0.015
        //     frames/muestra -> como mucho ~1.92 frames en un bloque de 128. Una
        //     correccion asi no se oye como barrido de pitch.
        xf_engine_seek_scratch(e, 0)
        xf_engine_set_scratch_target(e, 90_000)
        let before = xf_engine_scratch_playhead(e)
        _ = render(e, inL: nil, inR: nil, n: 128)
        let step = xf_engine_scratch_playhead(e) - before
        XCTAssertGreaterThan(step, 0.0, "corrige en la direccion correcta")
        XCTAssertLessThanOrEqual(step, 2.1, "el trim esta acotado (no barre)")

        // (3) soltar el ancla (-1): sin trim, con vel 0 el cabezal se queda quieto
        xf_engine_set_scratch_target(e, -1)
        let m = xf_engine_scratch_playhead(e)
        for _ in 0..<50 { _ = render(e, inL: nil, inR: nil, n: 128) }
        XCTAssertEqual(xf_engine_scratch_playhead(e), m, accuracy: 1.0, "sin ancla no hay trim")
    }

    func testSoftClipYPicoDeSalida() {
        let e = xf_engine_create(sr, 128)!
        defer { xf_engine_destroy(e) }
        xf_metronome_set_enabled(xf_engine_metronome(e), false)
        // sample muy caliente + gain alto -> la mezcla se pasaria de 1.0
        let sample = stableSample([Float](repeating: 0.95, count: 8192))
        defer { sample.deallocate() }
        xf_engine_load_sample(e, sample.baseAddress, Int64(sample.count))
        xf_engine_set_velocity(e, 1.0)
        xf_engine_set_master_gain(e, 1.5)

        var acc: [Float] = []
        for _ in 0..<40 { acc += render(e, inL: nil, inR: nil, n: 128).l }
        let peakOut = acc.map { abs($0) }.max() ?? 0

        // la salida NO recorta duro (queda por debajo de 1.0 gracias al soft-clip)
        XCTAssertLessThan(peakOut, 1.0)
        XCTAssertGreaterThan(peakOut, 0.7, "pero sigue sonando fuerte (rodilla suave)")
        // el medidor reporta que la mezcla iba por encima de 1.0 (clipeaba)
        XCTAssertGreaterThan(xf_engine_output_peak(e), 1.0)
    }

    func testElMetronomoSeMezclaEnLaSalida() {
        let e = xf_engine_create(sr, 128)!
        defer { xf_engine_destroy(e) }
        xf_engine_set_transport(e, 120, 480, true)
        xf_engine_seek_tick(e, 0)
        let m = xf_engine_metronome(e)!

        xf_metronome_set_enabled(m, false)
        XCTAssertEqual(render(e, inL: nil, inR: nil, n: 2048).l.map { abs($0) }.max() ?? 0, 0)

        xf_engine_seek_tick(e, 0)
        xf_metronome_set_enabled(m, true)
        XCTAssertGreaterThan(render(e, inL: nil, inR: nil, n: 2048).l.map { abs($0) }.max() ?? 0, 0.1,
                             "con el metronomo activo hay click")
    }

    // MARK: - reloj musical

    func testElRelojMusicalAvanzaSoloSonando() {
        let e = xf_engine_create(sr, 128)!
        defer { xf_engine_destroy(e) }
        xf_engine_seek_tick(e, 0)
        xf_engine_set_transport(e, 120, 480, false)
        _ = render(e, inL: nil, inR: nil, n: 128)
        XCTAssertEqual(xf_engine_tick(e), 0, "parado no avanza")

        xf_engine_set_transport(e, 120, 480, true)
        // 120 BPM, ppq 480 -> 4 ticks/frame ... 128 frames -> tick avanza 128*bpm/60*480/48000
        let perBlock = 120.0 / 60.0 * 480.0 / 48_000.0 * 128.0
        _ = render(e, inL: nil, inR: nil, n: 128)   // publica tick=0, luego avanza
        XCTAssertEqual(xf_engine_tick(e), 0, "el tick publicado es el del INICIO del bloque")
        _ = render(e, inL: nil, inR: nil, n: 128)
        XCTAssertEqual(xf_engine_tick(e), perBlock, accuracy: 1e-6)
        _ = render(e, inL: nil, inR: nil, n: 128)
        XCTAssertEqual(xf_engine_tick(e), 2 * perBlock, accuracy: 1e-6)
    }

    func testSeekColocaElReloj() {
        let e = xf_engine_create(sr, 128)!
        defer { xf_engine_destroy(e) }
        xf_engine_seek_tick(e, -3840)   // 2 compases de cuenta atras
        XCTAssertEqual(xf_engine_tick(e), -3840)
    }

    // MARK: - cambio de sample sonando

    func testCambiarDeSampleSonandoNoRevienta() {
        let e = xf_engine_create(sr, 128)!
        defer { xf_engine_destroy(e) }
        let a = stableSample([Float](repeating: 0.3, count: 4096))
        let b = stableSample((0..<4096).map { Float($0) / 4096 })
        defer { a.deallocate(); b.deallocate() }

        xf_engine_load_sample(e, a.baseAddress, Int64(a.count))
        xf_engine_set_velocity(e, 1.0)
        _ = render(e, inL: nil, inR: nil, n: 256)
        xf_engine_load_sample(e, b.baseAddress, Int64(b.count))   // cambio "sonando"
        _ = render(e, inL: nil, inR: nil, n: 256)
        xf_engine_load_sample(e, nil, 0)                          // sin sample
        _ = render(e, inL: nil, inR: nil, n: 256)
        XCTAssertTrue(true, "sin crash")
    }
}
