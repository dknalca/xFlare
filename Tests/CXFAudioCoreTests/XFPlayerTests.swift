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

    /// Renderiza `nframes` a velocidad constante `v` (F.46: `xf_player_render`
    /// toma inicio/fin de rampa; velocidad constante = mismo valor en los dos).
    private func render(_ p: OpaquePointer, nframes: Int, v: Double) -> [Float] {
        var out = [Float](repeating: 0, count: nframes)
        out.withUnsafeMutableBufferPointer {
            xf_player_render(p, $0.baseAddress, Int32(nframes), v, v)
        }
        return out
    }

    /// Renderiza `nframes` con la velocidad OBJETIVO en rampa lineal de
    /// `vStart` a `vEnd` a lo largo del bloque (F.46).
    private func renderRamp(_ p: OpaquePointer, nframes: Int, vStart: Double, vEnd: Double) -> [Float] {
        var out = [Float](repeating: 0, count: nframes)
        out.withUnsafeMutableBufferPointer {
            xf_player_render(p, $0.baseAddress, Int32(nframes), vStart, vEnd)
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

    // MARK: - rampa de velocidad dentro del bloque (F.46)

    func testLaVelocidadObjetivoVaEnRampaNoEnEscalon() {
        // Con glide=0 la velocidad REAL sigue exactamente a la OBJETIVO en
        // cada muestra (sin suavizado): asi el avance del cabezal mide
        // directamente que objetivo vio cada muestra.
        //   - constante a V todo el bloque -> avanza V * nframes
        //   - rampa de 0 a V             -> avanza ~V * nframes / 2 (media de
        //     una progresion aritmetica 0..V)
        let src = [Float](repeating: 0, count: 200_000)   // silencio: solo importa el cabezal
        let nframes = 1000
        let v = 10.0

        let constant = src.withUnsafeBufferPointer { buf -> Double in
            let p = xf_player_create(buf.baseAddress, Int64(src.count), 48_000)!
            defer { xf_player_destroy(p) }
            xf_player_set_glide_ms(p, 0)
            _ = render(p, nframes: nframes, v: v)
            return xf_player_playhead(p)
        }
        let ramped = src.withUnsafeBufferPointer { buf -> Double in
            let p = xf_player_create(buf.baseAddress, Int64(src.count), 48_000)!
            defer { xf_player_destroy(p) }
            xf_player_set_glide_ms(p, 0)
            _ = renderRamp(p, nframes: nframes, vStart: 0, vEnd: v)
            return xf_player_playhead(p)
        }

        XCTAssertEqual(constant, v * Double(nframes), accuracy: 1.0,
                       "velocidad constante: el cabezal avanza v*nframes, como antes")
        XCTAssertEqual(ramped, v * Double(nframes) / 2.0, accuracy: 1.0,
                       "rampa 0->v: el cabezal avanza la MEDIA de la rampa, no v*nframes")
        XCTAssertLessThan(ramped, constant * 0.6,
                          "la rampa no le plantea al player un escalon a v desde la muestra 0")
    }

    func testVelocidadConstanteEnLaRampaEsIgualQueAntes() {
        // start == end (F.44/F.01 ya mandan velocidad estable la mayor parte
        // del tiempo entre gestos): la rampa colapsa al comportamiento viejo.
        let src = sine(1000)
        src.withUnsafeBufferPointer { buf in
            let p = xf_player_create(buf.baseAddress, Int64(src.count), 48_000)!
            defer { xf_player_destroy(p) }
            xf_player_set_glide_ms(p, 0)
            let a = renderRamp(p, nframes: 4096, vStart: 1.0, vEnd: 1.0)
            let body = Array(a[64...])
            let ref = Array(src[64..<(64 + body.count)])
            XCTAssertEqual(rms(body), rms(ref), accuracy: 0.01)
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

    // MARK: - puerta por velocidad: taper suave + bloqueador de DC (F.47)

    func testLaPuertaUsaUnTaperDeCosenoNoUnaRampaLineal() {
        // gate=0.1; a v = 0,25·gate (g=0,25) el taper de coseno alzado da
        // amp = 0,5 - 0,5·cos(pi·0,25) ≈ 0,146 — bien por debajo del 0,25 que
        // daría la rampa lineal de antes (con pendiente cero en los extremos,
        // en vez de la esquina dura que había en g=1).
        let gate = 0.1
        let v = 0.25 * gate
        // 15 kHz a v=0,025 sale a ~375 Hz: por encima del corte del
        // bloqueador de DC (~38 Hz), así no contamina la medida de amplitud.
        let src = sine(15_000, amp: 0.8)
        src.withUnsafeBufferPointer { buf in
            let pOff = xf_player_create(buf.baseAddress, Int64(src.count), 48_000)!
            defer { xf_player_destroy(pOff) }
            xf_player_set_glide_ms(pOff, 0)
            let ref = Array(render(pOff, nframes: 8192, v: v)[512...])   // SIN puerta

            let pOn = xf_player_create(buf.baseAddress, Int64(src.count), 48_000)!
            defer { xf_player_destroy(pOn) }
            xf_player_set_glide_ms(pOn, 0)
            xf_player_set_speed_gate(pOn, gate)
            let gated = Array(render(pOn, nframes: 8192, v: v)[512...])   // CON puerta

            let measuredAmp = rms(gated) / rms(ref)
            XCTAssertEqual(measuredAmp, 0.1464, accuracy: 0.03,
                           "coseno alzado: amp(g=0,25) ≈ 0,146")
            XCTAssertLessThan(measuredAmp, 0.20,
                              "más atenuado en g=0,25 que la rampa lineal de antes (0,25)")
        }
    }

    func testElBloqueadorDeDCVaciaElZumbidoDelCabezalCasiQuieto() {
        let dc = [Float](repeating: 1.0, count: 4096)
        dc.withUnsafeBufferPointer { buf in
            // SIN puerta: la DC pasa a ganancia 1 (igual que testGananciaDCUnidad),
            // a cualquier velocidad — es lo que habría que oír como zumbido.
            let pOff = xf_player_create(buf.baseAddress, Int64(dc.count), 48_000)!
            defer { xf_player_destroy(pOff) }
            xf_player_set_glide_ms(pOff, 0)
            let unblocked = Array(render(pOff, nframes: 2048, v: 0.05)[64...])
            XCTAssertEqual(rms(unblocked), 1.0, accuracy: 1e-3, "sin puerta: DC a ganancia 1 (el zumbido)")

            // CON puerta, justo DENTRO de la zona (g≈0,995 -> amp≈1: el taper
            // apenas atenúa, así que esto mide sobre todo el bloqueador de DC)
            // el mismo tramo constante se vacía con el tiempo en vez de sonar
            // como un zumbido sostenido. (El bloqueador solo actúa DENTRO de
            // la zona de puerta, `av < gate`: en `v == gate` exacto ya no.)
            let gate = 0.05
            let pOn = xf_player_create(buf.baseAddress, Int64(dc.count), 48_000)!
            defer { xf_player_destroy(pOn) }
            xf_player_set_glide_ms(pOn, 0)
            xf_player_set_speed_gate(pOn, gate)
            let blocked = Array(render(pOn, nframes: 2048, v: gate * 0.995)[64...])
            XCTAssertLessThan(rms(Array(blocked.suffix(200))), 0.01,
                              "el bloqueador de DC vacía el zumbido tras unos ms")
        }
    }

    func testFueraDeLaZonaDePuertaLaSenalNoSeToca() {
        // Regresión: la primera versión de F.47 aplicaba el bloqueador de DC
        // SIEMPRE que la puerta estaba configurada, aunque la velocidad fuera
        // normal (amp=1) — eso borraba el contenido grave/casi-DC de CUALQUIER
        // sample en cuanto la puerta tenía un valor > 0 (que es el caso por
        // defecto). Un sample con grave real a velocidad normal debe sonar
        // EXACTAMENTE igual con la puerta configurada que sin ella.
        let dc = [Float](repeating: 0.95, count: 8192)
        dc.withUnsafeBufferPointer { buf in
            let pOff = xf_player_create(buf.baseAddress, Int64(dc.count), 48_000)!
            defer { xf_player_destroy(pOff) }
            xf_player_set_glide_ms(pOff, 0)
            let withoutGate = Array(render(pOff, nframes: 4096, v: 1.0)[64...])

            let pOn = xf_player_create(buf.baseAddress, Int64(dc.count), 48_000)!
            defer { xf_player_destroy(pOn) }
            xf_player_set_glide_ms(pOn, 0)
            xf_player_set_speed_gate(pOn, 0.04)   // el default del motor (F.47)
            let withGate = Array(render(pOn, nframes: 4096, v: 1.0)[64...])   // muy por encima de la puerta

            XCTAssertEqual(rms(withGate), rms(withoutGate), accuracy: 1e-6,
                           "a velocidad normal, con puerta o sin ella suena IGUAL")
            XCTAssertEqual(rms(withGate), 0.95, accuracy: 1e-3)
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

    // MARK: - silencio infinito antes del principio (F.70, ADR-076)

    /// Con timecode real el vinilo puede seguir girando hacia atras mas alla
    /// del principio del sample: antes el cabezal se clavaba a 0 (perdiendo
    /// cuanto habia girado de mas); ahora sigue negativo y la salida es
    /// silencio, no un chasquido ni el ultimo frame repetido.
    func testCabezalNoSeSaturaAlPrincipioYSaleSilencio() {
        let src = sine(1000)
        src.withUnsafeBufferPointer { buf in
            let p = xf_player_create(buf.baseAddress, Int64(src.count), 48_000)!
            defer { xf_player_destroy(p) }
            xf_player_set_glide_ms(p, 0)
            xf_player_set_playhead(p, 100)
            let out = render(p, nframes: 300, v: -1.0)   // cruza 0 a mitad de bloque
            XCTAssertLessThan(xf_player_playhead(p), 0,
                              "mas alla del principio el cabezal sigue negativo, no se clava a 0")
            XCTAssertEqual(out.last!, 0.0, "una vez en la zona anterior al sample, silencio")
        }
    }

    /// La razon de no saturar: si vas 150 frames "de mas" hacia atras y luego
    /// recorres esos mismos 150 frames hacia delante, el cabezal debe volver
    /// EXACTAMENTE a donde estaba -- ese es el "mantener la referencia" con el
    /// vinilo real. Con el clamp viejo el cabezal se habria quedado pegado a 0
    /// todo el tramo negativo y habria arrancado a sonar demasiado pronto.
    func testTrasIrseAntesDelPrincipioVuelveAlMismoFrame() {
        let src = sine(1000)
        src.withUnsafeBufferPointer { buf in
            let p = xf_player_create(buf.baseAddress, Int64(src.count), 48_000)!
            defer { xf_player_destroy(p) }
            xf_player_set_glide_ms(p, 0)
            xf_player_set_playhead(p, 50)
            _ = render(p, nframes: 200, v: -1.0)    // 50 -> -150
            XCTAssertEqual(xf_player_playhead(p), -150, accuracy: 1e-6)
            _ = render(p, nframes: 200, v: 1.0)     // -150 -> 50, el mismo recorrido de vuelta
            XCTAssertEqual(xf_player_playhead(p), 50, accuracy: 1e-6)
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
