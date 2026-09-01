// SPDX-License-Identifier: GPL-3.0-only

import XFClock
import XFNotation
import XFPrimitives

/// Empareja los cierres de fader del patron objetivo con los del usuario y
/// calcula el desfase con signo (B8.1).
enum ClickMatcher {

    /// Ventana maxima para considerar que un click del usuario "es" un click del
    /// patron. Fuera de esto, el click del patron se cuenta como perdido.
    static let matchWindowMs = 150.0

    /// Instantes (`hostTime`) en que el fader del usuario CIERRA (pasa de abierto
    /// a cortado). Es un evento discreto, como en el patron.
    static func userCloseEvents(_ fader: [FaderSample]) -> [UInt64] {
        var closes: [UInt64] = []
        var wasOpen = true
        for s in fader {
            if wasOpen && !s.isOpen { closes.append(s.hostTime) }
            wasOpen = s.isOpen
        }
        return closes
    }

    /// Empareja. Devuelve un `ClickOffset` por cada cierre del patron, en orden.
    static func match(target scratch: Scratch, take: Take) -> [ClickOffset] {
        let clock = take.clock
        let nsPerHostTick = clock.host.nanoseconds(fromHostTicks: 1)

        // cierres del patron, en hostTime
        let targetTicks = scratch.faderEvents.filter { $0.state == .closed }.map(\.t)
        let userCloses = userCloseEvents(take.fader)
        var used = [Bool](repeating: false, count: userCloses.count)

        var result: [ClickOffset] = []
        for tt in targetTicks {
            let targetHost = clock.hostTime(fromTick: tt)
            // el cierre de usuario libre mas cercano
            var bestIdx: Int? = nil
            var bestAbsMs = Double.greatestFiniteMagnitude
            for (i, uc) in userCloses.enumerated() where !used[i] {
                let deltaMs = (Double(Int64(uc) - Int64(targetHost)) * nsPerHostTick) / 1_000_000.0
                if abs(deltaMs) < bestAbsMs {
                    bestAbsMs = abs(deltaMs)
                    bestIdx = i
                }
            }

            if let idx = bestIdx, bestAbsMs <= matchWindowMs {
                used[idx] = true
                let uc = userCloses[idx]
                let offsetMs = (Double(Int64(uc) - Int64(targetHost)) * nsPerHostTick) / 1_000_000.0
                let pts = ScoringConstants.points(for: abs(offsetMs), bands: ScoringConstants.clickWindowsMs)
                result.append(ClickOffset(targetTick: tt, userHostTime: uc, offsetMs: offsetMs, score: pts))
            } else {
                result.append(ClickOffset(targetTick: tt, userHostTime: nil, offsetMs: nil, score: 0))
            }
        }
        return result
    }
}
