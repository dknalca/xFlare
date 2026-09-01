// SPDX-License-Identifier: GPL-3.0-only

import Foundation
import XFClock
import XFPrimitives

/// Captura del crossfader por el **retorno de audio con tono piloto** (ADR-021),
/// que es el metodo primario en mesas de batalla como la Rane 72: su crossfader
/// no expone la posicion por MIDI.
///
/// Idea: el motor mezcla un tono inaudible (19,5 kHz por defecto) en el master;
/// cuando el crossfader abre, el tono pasa al retorno USB; cuando cierra, el
/// crossfader lo atenua. Midiendo el **nivel** de ese tono en el retorno sabemos
/// como de abierto esta el fader.
///
/// Aqui se hace **solo el analisis**: `submit(...)` recibe el PCM del retorno
/// (lo drena un consumidor de prioridad normal desde el ring buffer, como
/// `TimecodeMotionSource`), corre un **Goertzel** de un bin por hop de 64
/// muestras, normaliza contra el nivel de piloto con el fader abierto, y pasa el
/// valor continuo al `FaderBinarizer` (cut-in + histeresis, ADR-017), que
/// resuelve `isOpen`. El detector `Goertzel` + histeresis viene del spike
/// `spike/b1-pilot-fader/`.
public final class AudioReturnFaderSource: FaderSource {

    public struct Config: Sendable {
        /// Frecuencia del tono piloto, en Hz. Del `[crossfader]` del perfil.
        public var pilotHz: Double
        /// Frecuencia de muestreo del retorno, en Hz.
        public var sampleRate: Double
        /// Muestras por analisis Goertzel (resolucion temporal = hop/sr).
        public var hopFrames: Int
        /// Punto de corte sobre el nivel de piloto normalizado (`0..1`).
        public var cutIn: Float
        /// Ancho de la banda muerta alrededor del cut-in.
        public var hysteresis: Float
        /// Crossfader invertido (`reverse_default` del perfil, ADR-008).
        public var hamster: Bool
        /// Nivel de piloto (magnitud lineal) esperado con el fader del todo
        /// abierto. Se auto-ajusta al alza; `calibrate(openLevel:)` lo fija.
        public var referenceLevel: Double

        public init(pilotHz: Double = 19_500, sampleRate: Double = 48_000,
                    hopFrames: Int = 64, cutIn: Float = 0.15, hysteresis: Float = 0.08,
                    hamster: Bool = false, referenceLevel: Double = 0.05) {
            self.pilotHz = pilotHz
            self.sampleRate = sampleRate
            self.hopFrames = hopFrames
            self.cutIn = cutIn
            self.hysteresis = hysteresis
            self.hamster = hamster
            self.referenceLevel = referenceLevel
        }
    }

    private let config: Config
    private let host: HostClock

    // Coeficiente Goertzel del bin del piloto (fijo, depende de hop/pilotHz/sr).
    private let goertzelCoef: Double

    private var running = false
    private var binarizer: FaderBinarizer
    private var reference: Double
    private var carry: [Float] = []            // muestras sueltas entre submits
    private var carryHostTime: UInt64 = 0      // hostTime de la 1a muestra de `carry`
    private var current: FaderSample?
    private var lastPilotLevel: Double = 0

    public init(config: Config = .init(), host: HostClock = HostClock()) {
        self.config = config
        self.host = host
        self.binarizer = FaderBinarizer(cutIn: config.cutIn, hysteresis: config.hysteresis,
                                        hamster: config.hamster)
        self.reference = max(config.referenceLevel, 1e-6)

        let bin = (Double(config.hopFrames) * config.pilotHz / config.sampleRate).rounded()
        self.goertzelCoef = 2.0 * cos(2.0 * .pi * bin / Double(config.hopFrames))
    }

    public var isConnected: Bool { running }

    public func start() throws {
        running = true
        binarizer = FaderBinarizer(cutIn: config.cutIn, hysteresis: config.hysteresis,
                                   hamster: config.hamster)
        reference = max(config.referenceLevel, 1e-6)
        carry.removeAll(keepingCapacity: true)
        current = nil
        lastPilotLevel = 0
    }

    public func stop() { running = false }

    public func latest() -> FaderSample? { current }

    /// Nivel de piloto normalizado del ultimo hop (`0..1`), para un medidor.
    public var pilotLevel: Double { lastPilotLevel }

    /// Fija el nivel de referencia (fader del todo abierto). Se llama durante la
    /// calibracion, con el usuario dejando el crossfader abierto.
    public func calibrate(openLevel: Double) {
        reference = max(openLevel, 1e-6)
    }

    // MARK: - alimentacion

    /// PCM **estereo intercalado de 16 bits** del retorno del master. Se
    /// promedian los dos canales; el piloto va correlado en ambos. Devuelve las
    /// muestras de fader producidas (una por hop completo), con `isOpen` ya
    /// resuelto — son los flancos que consume `XFAnalysis`.
    @discardableResult
    public func submit(pcm: UnsafePointer<Int16>, frames: Int, hostTime: UInt64) -> [FaderSample] {
        guard running, frames > 0 else { return [] }

        if carry.isEmpty { carryHostTime = hostTime }
        carry.reserveCapacity(carry.count + frames)
        for f in 0..<frames {
            let l = Float(pcm[f * 2 + 0]), r = Float(pcm[f * 2 + 1])
            carry.append((l + r) * 0.5 / 32_768.0)
        }

        let hop = config.hopFrames
        var samples: [FaderSample] = []
        var off = 0
        while off + hop <= carry.count {
            let mag = goertzel(carry, from: off, count: hop)

            // referencia = maximo con fuga muy lenta (recupera de un pico en ~1 min)
            reference = max(mag, reference - reference * 2e-5)
            let value = Float(min(1.0, max(0.0, mag / reference)))
            lastPilotLevel = Double(value)

            let hopHost = hopHostTime(hopIndex: off / hop)
            samples.append(contentsOf: binarizer.binarize([(hopHost, value)]))
            off += hop
        }
        if off > 0 {
            carry.removeFirst(off)
            let consumedNs = Double(off) / config.sampleRate * 1_000_000_000
            carryHostTime &+= host.hostTicks(fromNanoseconds: consumedNs)
        }
        if let last = samples.last { current = last }
        return samples
    }

    @discardableResult
    public func submit(_ pcm: [Int16], hostTime: UInt64) -> [FaderSample] {
        pcm.withUnsafeBufferPointer { buf in
            guard let base = buf.baseAddress else { return [] }
            return submit(pcm: base, frames: buf.count / 2, hostTime: hostTime)
        }
    }

    // MARK: - interno

    /// Goertzel de un bin sobre `carry[from ..< from+count]`. Devuelve la
    /// magnitud lineal (amplitud equivalente).
    private func goertzel(_ x: [Float], from: Int, count: Int) -> Double {
        var s1 = 0.0, s2 = 0.0
        for i in from..<(from + count) {
            let s0 = Double(x[i]) + goertzelCoef * s1 - s2
            s2 = s1; s1 = s0
        }
        let power = s1 * s1 + s2 * s2 - goertzelCoef * s1 * s2
        return (max(0, power)).squareRoot() * 2.0 / Double(count)
    }

    private func hopHostTime(hopIndex: Int) -> UInt64 {
        let ns = Double(hopIndex * config.hopFrames) / config.sampleRate * 1_000_000_000
        return carryHostTime &+ host.hostTicks(fromNanoseconds: ns)
    }
}
