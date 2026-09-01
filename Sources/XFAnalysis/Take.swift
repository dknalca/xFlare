// SPDX-License-Identifier: GPL-3.0-only

import XFClock
import XFNotation
import XFPrimitives

/// La toma que se va a puntuar: las muestras crudas de disco y de fader mas la
/// regla para llevarlas al tiempo musical (`docs/ARCHITECTURE.md` §3).
///
/// Da igual de donde vengan las muestras (mesa real o `.xfsession`): el scoring
/// es el mismo.
public struct Take: Sendable {
    public let motion: [MotionSample]
    public let fader: [FaderSample]
    public let clock: ClockMap

    public init(motion: [MotionSample], fader: [FaderSample], clock: ClockMap) {
        self.motion = motion
        self.fader = fader
        self.clock = clock
    }

    /// `true` si hay muestras que cubren hasta (casi) el final del patron: se usa
    /// para la 1a estrella ("llegaste al final").
    public func reachedEnd(of scratch: Scratch, toleranceTicks: Tick = 240) -> Bool {
        guard let lastMotionHost = motion.last?.hostTime else { return false }
        let lastTick = clock.tick(fromHostTime: lastMotionHost)
        return lastTick >= scratch.lengthTicks - toleranceTicks
    }
}
