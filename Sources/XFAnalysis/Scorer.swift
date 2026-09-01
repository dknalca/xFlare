// SPDX-License-Identifier: GPL-3.0-only

import XFNotation

/// Puntua una toma contra un patron. Es un protocolo para poder cambiar la
/// implementacion (o probar una mejor con `tools/`) sin tocar a los que la usan.
public protocol Scorer {
    /// - Parameters:
    ///   - take: las muestras capturadas + su `ClockMap`.
    ///   - scratch: el patron objetivo.
    ///   - atTargetBpm: si la toma se hizo al BPM objetivo del ejercicio (lo sabe
    ///     `XFEngine`, no la toma). Necesario para la 3a estrella.
    func score(_ take: Take, against scratch: Scratch, atTargetBpm: Bool) -> Report
}

public extension Scorer {
    func score(_ take: Take, against scratch: Scratch) -> Report {
        score(take, against: scratch, atTargetBpm: true)
    }
}
