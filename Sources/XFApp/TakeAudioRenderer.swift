// SPDX-License-Identifier: GPL-3.0-only

import Foundation
import CXFAudioCore
import XFRender
import XFNotation
import XFClock
import XFCapture

/// F.4 (audio) — render **offline** del sonido de una toma grabada. Reproduce el
/// `xf_engine` (el motor RT de verdad, sin CoreAudio) siguiendo la velocidad,
/// posicion y fader que se grabaron, y devuelve el PCM estereo. Es lo que suena
/// en el video exportado, y sale del mismo DSP que la practica en vivo.
enum TakeAudioRenderer {

    struct Rendered {
        var left: [Float]
        var right: [Float]
        var sampleRate: Double
        var frames: Int
    }

    /// - Parameters:
    ///   - durationSeconds: normalmente el mismo total que el plan de fotogramas
    ///     del video (patron + cola).
    static func render(session: XFSession, scratch: Scratch,
                       scratchPCM: [Float]?,
                       instrumental: (pcm: [Float], nativeBPM: Double)?,
                       sampleRate: Double = 48_000,
                       durationSeconds: Double,
                       masterGain: Float = 0.85,
                       scratchGain: Float = 0.7,
                       instrumentalGain: Float = 0.6,
                       block: Int = 512) -> Rendered {

        let totalFrames = max(1, Int((durationSeconds * sampleRate).rounded()))
        var left = [Float](repeating: 0, count: totalFrames)
        var right = [Float](repeating: 0, count: totalFrames)

        guard let e = xf_engine_create(sampleRate, UInt32(block)) else {
            return Rendered(left: left, right: right, sampleRate: sampleRate, frames: totalFrames)
        }
        defer { xf_engine_destroy(e) }

        let bpm = session.header.tempoBPM > 0 ? session.header.tempoBPM : 90
        xf_engine_set_transport(e, bpm, 480, true)
        xf_engine_set_master_gain(e, masterGain)
        xf_engine_set_instrumental_gain(e, instrumentalGain)

        let full: Double
        if let s = scratchPCM, s.count > 1 {
            s.withUnsafeBufferPointer { xf_engine_load_sample(e, $0.baseAddress, Int64(s.count)) }
            full = Double(s.count - 1)
        } else {
            full = 1
        }
        if let ins = instrumental, ins.pcm.count > 1, ins.nativeBPM > 0 {
            ins.pcm.withUnsafeBufferPointer {
                xf_engine_load_instrumental(e, $0.baseAddress, Int64(ins.pcm.count), ins.nativeBPM)
            }
        }

        // conversion identica a la practica en vivo (LivePracticeView.start +
        // PracticeSession.normalizedPosition/Velocity): el pico del patron cae en
        // `scratchPatternTopFraction` del sample.
        let range = HighwayLayout(scratch: scratch).positionRange
        let posLo = range.lowerBound
        let span = max(1e-6, range.upperBound - range.lowerBound)
        let top = AudioAsset.scratchPatternTopFraction

        let tl = Timeline(session: session)

        var bufL = [Float](repeating: 0, count: block)
        var bufR = [Float](repeating: 0, count: block)
        var frame = 0
        while frame < totalFrames {
            let n = min(block, totalFrames - frame)
            let t = Double(frame) / sampleRate
            let s = tl.sample(atSecond: t)
            let normPos = min(1, max(0, (s.pos - posLo) / span * top))
            let normVel = s.vel / span * top
            xf_engine_set_scratch_target(e, normPos * full)
            xf_engine_set_velocity(e, normVel * full / sampleRate)
            xf_engine_set_scratch_gain(e, s.closed ? 0 : scratchGain)

            bufL.withUnsafeMutableBufferPointer { lp in
                bufR.withUnsafeMutableBufferPointer { rp in
                    xf_engine_render(e, nil, nil, lp.baseAddress, rp.baseAddress,
                                     Int32(n), UInt64(frame))
                }
            }
            for k in 0..<n { left[frame + k] = bufL[k]; right[frame + k] = bufR[k] }
            frame += n
        }
        return Rendered(left: left, right: right, sampleRate: sampleRate, frames: totalFrames)
    }

    // MARK: - timeline de la toma (segundos -> pos / vel / fader)

    private struct Timeline {
        let secs: [Double]
        let pos: [Double]
        let vel: [Double]
        let closed: [Bool]

        init(session s: XFSession) {
            guard let t0 = s.motion.first?.hostTime else {
                secs = []; pos = []; vel = []; closed = []; return
            }
            let hc = HostClock(numer: max(1, s.header.hostNumer), denom: max(1, s.header.hostDenom))
            func sec(_ ht: UInt64) -> Double {
                ht > t0 ? hc.nanoseconds(fromHostTicks: ht - t0) / 1_000_000_000 : 0
            }
            secs = s.motion.map { sec($0.hostTime) }
            pos = s.motion.map { $0.position }
            vel = s.motion.map { $0.velocity }

            // por cada muestra de movimiento, el estado del ultimo cambio de fader <= su tiempo
            let events = s.fader.map { (t: sec($0.hostTime), open: $0.isOpen) }
                .sorted { $0.t < $1.t }
            var c = [Bool](); c.reserveCapacity(secs.count)
            var i = 0; var open = true
            for t in secs {
                while i < events.count && events[i].t <= t { open = events[i].open; i += 1 }
                c.append(!open)
            }
            closed = c
        }

        func sample(atSecond t: Double) -> (pos: Double, vel: Double, closed: Bool) {
            guard !secs.isEmpty else { return (0, 0, false) }
            if t <= secs[0] { return (pos[0], vel[0], closed[0]) }
            let last = secs.count - 1
            if t >= secs[last] { return (pos[last], 0, closed[last]) }
            var lo = 0, hi = last
            while lo < hi { let m = (lo + hi) / 2; if secs[m] < t { lo = m + 1 } else { hi = m } }
            let a = lo - 1, b = lo
            let f = (t - secs[a]) / max(1e-9, secs[b] - secs[a])
            return (pos[a] + (pos[b] - pos[a]) * f,
                    vel[a] + (vel[b] - vel[a]) * f,
                    closed[b])
        }
    }
}
