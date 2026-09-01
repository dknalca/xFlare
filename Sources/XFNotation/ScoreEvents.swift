// SPDX-License-Identifier: GPL-3.0-only

import XFClock

/// Cuenta de eventos evaluables de un scratch y su puntuacion maxima.
///
/// Criterio unificado con `docs/SCORING.md` §1 (decision del autor, 2026-09-01):
/// - `click`    — uno por cierre de fader del patron.
/// - `pitch`    — uno por **semicorchea** (`ppq/4` ticks). Es la resolucion a la
///                que se evalua el contorno de tono; da 16 para el 2-Click Flare
///                base (1920 ticks), que es lo que dice SCORING.md.
/// - `amplitude`— uno por trazo hacia delante.
///
/// Cada evento vale 100 puntos (`data/curriculum/scoring.json` -> `eventValue`).
/// Ejemplo de SCORING.md: 2-Click Flare base = 16 + 16 + 4 = 36 eventos = 3600.
public struct ScoreEvents: Equatable, Sendable {

    public let clicks: Int
    public let pitch: Int
    public let amplitude: Int

    /// Total de eventos evaluables.
    public var events: Int { clicks + pitch + amplitude }
    /// Puntuacion maxima del patron: `events * 100`.
    public var maxScore: Int { events * 100 }

    public init(of scratch: Scratch, ppq: Int = XFClock.ppq) {
        self.clicks = scratch.faderEvents.filter { $0.state == .closed }.count
        self.pitch = max(1, scratch.lengthTicks / (ppq / 4))
        self.amplitude = max(1, scratch.record.filter { $0.dir == .fwd }.count)
    }
}
