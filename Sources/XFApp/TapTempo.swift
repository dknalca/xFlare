// SPDX-License-Identifier: GPL-3.0-only

import Foundation

/// TAP tempo **puro**: acumula los instantes de los golpes y, en cuanto hay dos o
/// más seguidos, devuelve el BPM de la media de los últimos intervalos. Una pausa
/// mayor que `resetAfter` se toma como "empiezo otra vez" y reinicia la cuenta.
///
/// La detección automática de tempo (`TempoAnalyzer`) afina bien pero no siempre
/// clava; esto deja rematarlo dando al ritmo con el dedo.
struct TapTempo {

    /// Cuántos golpes recientes se promedian.
    var window = 8
    /// Pausa (s) que reinicia la secuencia de golpes.
    var resetAfter: TimeInterval = 2.0
    /// Intervalo mínimo/máximo aceptado entre golpes (≈ 250 y 30 BPM).
    var minInterval: TimeInterval = 0.24
    var maxInterval: TimeInterval = 2.0

    private(set) var times: [Date] = []

    /// Registra un golpe en `now`. Devuelve el BPM redondeado si ya hay bastantes
    /// golpes y el ritmo es plausible; si no, `nil`.
    mutating func tap(at now: Date = Date()) -> Int? {
        if let last = times.last, now.timeIntervalSince(last) > resetAfter {
            times.removeAll(keepingCapacity: true)
        }
        times.append(now)
        if times.count > window { times.removeFirst(times.count - window) }

        guard times.count >= 2 else { return nil }
        let gaps = zip(times.dropFirst(), times).map { $0.timeIntervalSince($1) }
        let avg = gaps.reduce(0, +) / Double(gaps.count)
        guard avg >= minInterval, avg <= maxInterval else { return nil }
        return Int((60.0 / avg).rounded())
    }

    mutating func reset() { times.removeAll(keepingCapacity: true) }
}
