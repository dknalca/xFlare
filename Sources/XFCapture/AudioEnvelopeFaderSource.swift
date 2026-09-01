// SPDX-License-Identifier: GPL-3.0-only

import Foundation
import XFClock
import XFPrimitives

/// Fallback **de ultimo recurso** para el crossfader (B6.4): un seguidor de
/// envolvente sobre el retorno del master. Sin tono piloto ni MIDI — solo "hay
/// audio fuerte en el retorno" = fader abierto.
///
/// Es mas basto que `AudioReturnFaderSource` (tono piloto): si suena el sample
/// bajito o hay silencios en la frase, se puede leer mal. Se usa cuando no hay
/// MIDI y el tono piloto tampoco funciona.
///
/// Mismo reparto que las demas fuentes: `submit(...)` recibe el PCM (lo drena un
/// consumidor normal desde el ring buffer), se calcula el RMS por hop, se
/// normaliza contra el nivel con el fader abierto y se pasa al `FaderBinarizer`.
public final class AudioEnvelopeFaderSource: FaderSource {

    public struct Config: Sendable {
        public var sampleRate: Double
        public var hopFrames: Int
        public var cutIn: Float
        public var hysteresis: Float
        public var hamster: Bool
        /// RMS esperado con el fader abierto. Se auto-ajusta al alza;
        /// `calibrate(openLevel:)` lo fija.
        public var referenceLevel: Double

        public init(sampleRate: Double = 48_000, hopFrames: Int = 256,
                    cutIn: Float = 0.2, hysteresis: Float = 0.1,
                    hamster: Bool = false, referenceLevel: Double = 0.1) {
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
    private var running = false
    private var binarizer: FaderBinarizer
    private var reference: Double
    private var carry: [Float] = []
    private var carryHostTime: UInt64 = 0
    private var current: FaderSample?
    private var lastEnvelope: Double = 0

    public init(config: Config = .init(), host: HostClock = HostClock()) {
        self.config = config
        self.host = host
        self.binarizer = FaderBinarizer(cutIn: config.cutIn, hysteresis: config.hysteresis,
                                        hamster: config.hamster)
        self.reference = max(config.referenceLevel, 1e-6)
    }

    public var isConnected: Bool { running }

    public func start() throws {
        running = true
        binarizer = FaderBinarizer(cutIn: config.cutIn, hysteresis: config.hysteresis,
                                   hamster: config.hamster)
        reference = max(config.referenceLevel, 1e-6)
        carry.removeAll(keepingCapacity: true)
        current = nil
        lastEnvelope = 0
    }

    public func stop() { running = false }
    public func latest() -> FaderSample? { current }

    /// Envolvente normalizada del ultimo hop (`0..1`).
    public var envelope: Double { lastEnvelope }

    public func calibrate(openLevel: Double) { reference = max(openLevel, 1e-6) }

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
            var sum = 0.0
            for i in off..<(off + hop) { sum += Double(carry[i]) * Double(carry[i]) }
            let rms = (sum / Double(hop)).squareRoot()

            reference = max(rms, reference - reference * 2e-5)
            let value = Float(min(1.0, max(0.0, rms / reference)))
            lastEnvelope = Double(value)

            let ns = Double(off) / config.sampleRate * 1_000_000_000
            let hopHost = carryHostTime &+ host.hostTicks(fromNanoseconds: ns)
            samples.append(contentsOf: binarizer.binarize([(hopHost, value)]))
            off += hop
        }
        if off > 0 {
            carry.removeFirst(off)
            let consumedNs = Double(off) / config.sampleRate * 1_000_000_000
            carryHostTime &+= host.hostTicks(fromNanoseconds: consumedNs)
        }
        if let s = samples.last { current = s }
        return samples
    }

    @discardableResult
    public func submit(_ pcm: [Int16], hostTime: UInt64) -> [FaderSample] {
        pcm.withUnsafeBufferPointer { buf in
            guard let base = buf.baseAddress else { return [] }
            return submit(pcm: base, frames: buf.count / 2, hostTime: hostTime)
        }
    }
}
