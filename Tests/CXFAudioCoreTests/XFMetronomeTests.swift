// SPDX-License-Identifier: GPL-3.0-only
import XCTest
import Darwin
import CXFAudioCore

/// B4.4 — metronomo mezclado en la salida principal (ADR-007).
final class XFMetronomeTests: XCTestCase {

    private let sr = 48_000.0
    private let ppq = 480.0

    /// Renderiza `nframes` a `bpm` empezando en `tick0`. `preset` es el valor con
    /// el que se rellena `out` antes de mezclar (para comprobar la SUMA).
    private func render(_ m: OpaquePointer, nframes: Int, bpm: Double,
                        tick0: Double, tpf: Double? = nil, preset: Float = 0) -> [Float] {
        var out = [Float](repeating: preset, count: nframes)
        out.withUnsafeMutableBufferPointer {
            xf_metronome_render(m, $0.baseAddress, Int32(nframes), tick0, bpm)
        }
        return out
    }

    /// Indices de los arranques de click: primer flanco de subida de `|x|` sobre
    /// `thr`, con un "debounce" de `minGap` muestras para no contar cada hump del
    /// seno dentro del mismo click.
    private func onsets(_ x: [Float], thr: Float = 0.05, minGap: Int = 2000) -> [Int] {
        var res: [Int] = []
        for i in 1..<x.count where abs(x[i]) >= thr && abs(x[i - 1]) < thr {
            if res.last.map({ i - $0 >= minGap }) ?? true { res.append(i) }
        }
        return res
    }

    private func goertzel(_ x: ArraySlice<Float>, hz: Double) -> Double {
        let w = 2.0 * Double.pi * hz / sr
        let c = 2.0 * cos(w)
        var s1 = 0.0, s2 = 0.0
        for v in x { let s0 = Double(v) + c * s1 - s2; s2 = s1; s1 = s0 }
        return (max(0, s1*s1 + s2*s2 - c*s1*s2)).squareRoot() * 2 / Double(x.count)
    }

    // MARK: -

    func testCrearYDefaults() {
        XCTAssertNil(xf_metronome_create(0))
        let m = xf_metronome_create(48_000)!
        defer { xf_metronome_destroy(m) }
        XCTAssertTrue(xf_metronome_enabled(m))
    }

    func testUnClickPorNegra() {
        let m = xf_metronome_create(48_000)!
        defer { xf_metronome_destroy(m) }
        // 120 BPM -> negra cada 0,5 s = 24000 frames. 4 s -> ~8 clicks.
        let out = render(m, nframes: Int(4 * sr), bpm: 120, tick0: 0)
        let o = onsets(out)
        XCTAssertEqual(o.count, 8, "8 negras en 4 s a 120 BPM")
        // espaciado ~24000 frames
        for i in 1..<o.count {
            XCTAssertEqual(Double(o[i] - o[i - 1]), 24_000, accuracy: 400)
        }
    }

    func testPrimerTiempoAcentuado() {
        let m = xf_metronome_create(48_000)!
        defer { xf_metronome_destroy(m) }
        let out = render(m, nframes: Int(1.6 * sr), bpm: 120, tick0: 0)  // ~3 clicks
        let o = onsets(out)
        XCTAssertGreaterThanOrEqual(o.count, 3)
        // ventana de cada click
        func win(_ i: Int) -> ArraySlice<Float> { out[o[i]..<min(o[i] + 2400, out.count)] }
        let accentAt1600 = goertzel(win(0), hz: 1600)
        let accentAt1000 = goertzel(win(0), hz: 1000)
        let normalAt1600 = goertzel(win(1), hz: 1600)
        let normalAt1000 = goertzel(win(1), hz: 1000)
        XCTAssertGreaterThan(accentAt1600, accentAt1000, "el 1er tiempo es el agudo (1600 Hz)")
        XCTAssertGreaterThan(normalAt1000, normalAt1600, "los demas son 1000 Hz")
    }

    func testDesactivadoNoSuena() {
        let m = xf_metronome_create(48_000)!
        defer { xf_metronome_destroy(m) }
        xf_metronome_set_enabled(m, false)
        XCTAssertFalse(xf_metronome_enabled(m))
        let out = render(m, nframes: Int(2 * sr), bpm: 120, tick0: 0)
        XCTAssertEqual(out.map { abs($0) }.max() ?? 0, 0, "silencio absoluto")
    }

    func testReactivarNoSueltaRafaga() {
        let m = xf_metronome_create(48_000)!
        defer { xf_metronome_destroy(m) }
        // 60 BPM -> negra cada 1 s. Sonando 0,3 s (aun no ha sonado la 2a),
        // apagamos 2 s, encendemos: la siguiente negra suena, no una rafaga.
        _ = render(m, nframes: Int(0.3 * sr), bpm: 60, tick0: 0)
        xf_metronome_set_enabled(m, false)
        _ = render(m, nframes: Int(2 * sr), bpm: 60, tick0: ppq * 0.3)   // tick tras 0,3 negras
        xf_metronome_set_enabled(m, true)
        // seguimos desde tick 2,3 negras; en 1,5 s (60 BPM) cruzamos 1-2 negras
        let out = render(m, nframes: Int(1.5 * sr), bpm: 60, tick0: ppq * 2.3)
        XCTAssertLessThanOrEqual(onsets(out, minGap: 20_000).count, 2, "solo las negras nuevas")
        XCTAssertGreaterThanOrEqual(onsets(out, minGap: 20_000).count, 1)
    }

    func testElBpmCambiaElEspaciado() {
        for (bpm, expected) in [(60.0, 2), (240.0, 8)] {
            let m = xf_metronome_create(48_000)!
            defer { xf_metronome_destroy(m) }
            let out = render(m, nframes: Int(2 * sr), bpm: bpm, tick0: 0)
            XCTAssertEqual(onsets(out, minGap: 2000).count, expected, "a \(bpm) BPM en 2 s")
        }
    }

    func testSeMezclaSumandoNoPisando() {
        let m = xf_metronome_create(48_000)!
        defer { xf_metronome_destroy(m) }
        let out = render(m, nframes: Int(2 * sr), bpm: 120, tick0: 0, preset: 0.5)
        // entre clicks el valor sigue siendo el preset exacto
        let o = onsets(out.map { $0 - 0.5 })
        XCTAssertFalse(o.isEmpty)
        let quiet = out[(o[0] + 6000)..<(o[1] - 2000)]   // tramo sin click
        XCTAssertEqual(quiet.map { abs($0 - 0.5) }.max() ?? 1, 0, accuracy: 1e-6,
                       "fuera del click, out == preset (suma, no pisa)")
    }

    func testCuentaAtrasConTicksNegativos() {
        let m = xf_metronome_create(48_000)!
        defer { xf_metronome_destroy(m) }
        // 2 compases de cuenta atras: 4/4, ppq 480 -> ticksPerBar 1920, 2 -> -3840
        let out = render(m, nframes: Int(2 * sr), bpm: 120, tick0: -3840)
        let o = onsets(out)
        XCTAssertGreaterThanOrEqual(o.count, 3, "la claqueta suena tambien en negativo")
        // el primer click (tiempo -8, y -8 % 4 == 0) es acentuado
        let win0 = out[o[0]..<min(o[0] + 2400, out.count)]
        XCTAssertGreaterThan(goertzel(win0, hz: 1600), goertzel(win0, hz: 1000))
    }

    func testResyncNoDisparaElTiempoActual() {
        let m = xf_metronome_create(48_000)!
        defer { xf_metronome_destroy(m) }
        xf_metronome_resync(m, ppq * 4.0 + 100)     // a mitad del 5o tiempo
        // render corto que NO llega al 6o tiempo (a 120 BPM, negra = 24000 fr;
        // faltan ~ (480-100)/480 de negra ~ 19000 fr). Pedimos 8000.
        let out = render(m, nframes: 8000, bpm: 120, tick0: ppq * 4.0 + 100)
        XCTAssertEqual(out.map { abs($0) }.max() ?? 0, 0, "resync no re-dispara el tiempo en curso")
    }

    func testSaltoHaciaAtrasVuelveADisparar() {
        let m = xf_metronome_create(48_000)!
        defer { xf_metronome_destroy(m) }
        _ = render(m, nframes: Int(1.2 * sr), bpm: 120, tick0: 0)   // pasa varias negras
        // el transporte hace loop: vuelve a tick 0
        let out = render(m, nframes: 4000, bpm: 120, tick0: 0)
        XCTAssertGreaterThan(out.map { abs($0) }.max() ?? 0, 0.1,
                             "al cambiar el numero de tiempo (aunque baje) dispara")
    }
}
