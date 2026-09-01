// SPDX-License-Identifier: GPL-3.0-only
import Foundation
import XFClock
import XFNotation
import XFPrimitives
@testable import XFAnalysis

/// Genera `Take` sinteticos a partir de un patron objetivo, para probar el
/// scoring sin hardware (equivalente a los `.xfsession` de B8.5 hasta que haya
/// grabaciones reales).
enum SyntheticTake {

    /// LCG determinista: mismos numeros en cada corrida y en las dos arquitecturas.
    struct RNG {
        var state: UInt64
        mutating func nextUnit() -> Double {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return Double(state >> 11) / Double(1 << 53)
        }
        /// ruido uniforme en [-amp, amp]
        mutating func noise(_ amp: Double) -> Double { (nextUnit() * 2 - 1) * amp }
    }

    static func make(
        for scratch: Scratch,
        clock: ClockMap,
        motionHz: Double = 2000,
        clickBiasMs: Double = 0,
        clickJitterMs: Double = 0,
        dropClickIndices: Set<Int> = [],
        velocityNoise: Double = 0,
        seed: UInt64 = 0xC0FFEE
    ) -> Take {
        var rng = RNG(state: seed)
        let nsPerHostTick = clock.host.nanoseconds(fromHostTicks: 1)
        let msToHostTicks = { (ms: Double) -> Int64 in Int64((ms * 1_000_000.0) / nsPerHostTick) }

        // --- motion: muestreo regular de 0 a lengthTicks ---
        let secs = clock.tempo.seconds(fromTicks: scratch.lengthTicks)
        let nSamples = max(2, Int(secs * motionHz))
        var motion: [MotionSample] = []
        motion.reserveCapacity(nSamples + 1)
        for k in 0...nSamples {
            let tick = Tick(Double(scratch.lengthTicks) * Double(k) / Double(nSamples))
            let host = clock.hostTime(fromTick: tick)
            let pos = PositionSampler.position(of: scratch, atTick: tick)
            let vel = PitchAnalyzer.targetVelocity(of: scratch, atTick: tick) + rng.noise(velocityNoise)
            motion.append(MotionSample(hostTime: host, position: pos, velocity: vel, confidence: 1))
        }

        // --- fader: cada transicion del patron, desplazada ---
        var fader: [FaderSample] = []
        for (i, ev) in scratch.faderEvents.enumerated() {
            if ev.state == .closed && dropClickIndices.contains(closedIndex(of: i, in: scratch)) {
                continue   // click que el usuario "no da"
            }
            let baseHost = clock.hostTime(fromTick: ev.t)
            let shiftMs = clickBiasMs + rng.noise(clickJitterMs)
            let host = UInt64(Int64(baseHost) + msToHostTicks(shiftMs))
            fader.append(FaderSample(hostTime: host, value: ev.state == .open ? 1 : 0,
                                     isOpen: ev.state == .open))
        }
        fader.sort { $0.hostTime < $1.hostTime }

        return Take(motion: motion, fader: fader, clock: clock)
    }

    /// indice del cierre dentro de la secuencia de cierres (para `dropClickIndices`).
    private static func closedIndex(of eventIndex: Int, in scratch: Scratch) -> Int {
        var c = -1
        for i in 0...eventIndex where scratch.faderEvents[i].state == .closed { c += 1 }
        return c
    }
}
