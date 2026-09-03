// SPDX-License-Identifier: GPL-3.0-only

import Foundation

/// TAP tempo **puro**: acumula los instantes de los golpes y, cuando ya hay unos
/// cuantos, devuelve el BPM de la **media de los intervalos**, descartando el que
/// se desvíe mucho de la mediana (un golpe a destiempo no tira la cuenta). Una
/// pausa mayor que `resetAfter` reinicia la secuencia.
///
/// La detección automática (`TempoAnalyzer`) afina bien pero no siempre clava;
/// esto deja rematarlo dando 4-8 veces al ritmo.
struct TapTempo {

    /// Golpes recientes que entran en la media (los más viejos se descartan).
    var window = 8
    /// Golpes mínimos antes de dar un BPM (con 4 la media ya es estable).
    var fireAfter = 4
    /// Pausa (s) que reinicia la secuencia de golpes.
    var resetAfter: TimeInterval = 2.0
    /// Intervalo mínimo/máximo aceptado entre golpes (≈ 250 y 30 BPM).
    var minInterval: TimeInterval = 0.24
    var maxInterval: TimeInterval = 2.0

    private(set) var times: [Date] = []

    /// Registra un golpe en `now`. Devuelve el BPM (con **un decimal**, la media
    /// de 4-8 golpes) cuando ya hay `fireAfter` golpes y el ritmo es plausible;
    /// si no, `nil`.
    mutating func tap(at now: Date = Date()) -> Double? {
        if let last = times.last, now.timeIntervalSince(last) > resetAfter {
            times.removeAll(keepingCapacity: true)
        }
        times.append(now)
        if times.count > window { times.removeFirst(times.count - window) }

        guard times.count >= fireAfter else { return nil }
        let gaps = zip(times.dropFirst(), times).map { $0.timeIntervalSince($1) }
        guard let avg = Self.trimmedMean(gaps),
              avg >= minInterval, avg <= maxInterval else { return nil }
        return ((60.0 / avg) * 10).rounded() / 10
    }

    mutating func reset() { times.removeAll(keepingCapacity: true) }

    /// Media de `xs` quitando los que se alejen más de un 35 % de la mediana
    /// (un golpe fumado). `nil` si tras el filtro no queda nada.
    static func trimmedMean(_ xs: [Double]) -> Double? {
        guard !xs.isEmpty else { return nil }
        let sorted = xs.sorted()
        let med = sorted[sorted.count / 2]
        let kept = xs.filter { abs($0 - med) <= 0.35 * med }
        let use = kept.isEmpty ? xs : kept
        return use.reduce(0, +) / Double(use.count)
    }
}
