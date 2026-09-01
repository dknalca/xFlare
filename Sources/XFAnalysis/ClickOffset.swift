// SPDX-License-Identifier: GPL-3.0-only

import XFClock

/// El resultado de un click del patron: con que click del usuario se ha
/// emparejado y cuanto desfase hay, **con signo** (+ = tarde, − = pronto).
public struct ClickOffset: Equatable, Sendable {

    /// Tick del cierre de fader en el patron objetivo.
    public let targetTick: Tick

    /// `hostTime` del cierre de fader del usuario emparejado, o `nil` si no hubo
    /// ninguno en la ventana (click perdido).
    public let userHostTime: UInt64?

    /// Desfase en milisegundos, con signo. `nil` si el click se perdio.
    public let offsetMs: Double?

    /// Puntuacion de este evento (0..100), segun las ventanas de `SCORING.md`.
    public let score: Int

    public var isMissed: Bool { userHostTime == nil }
}
