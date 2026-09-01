// SPDX-License-Identifier: GPL-3.0-only

/// *Dynamic Time Warping*: distancia entre dos series temporales permitiendo que
/// se estiren o encojan en el tiempo. Compara **forma**, no valores punto a
/// punto ni instante a instante — que es justo lo que pide la afinacion relativa
/// de ADR-005.
public enum DTW {

    /// Distancia DTW entre `a` y `b` con coste local `|a_i - b_j|` y una banda de
    /// Sakoe-Chiba de radio `band` (limita cuanto se puede deformar y acota el
    /// coste a O(n · band)). El resultado se **normaliza** dividiendo por la
    /// longitud del camino, para que sea comparable entre tomas de distinta
    /// duracion.
    public static func normalizedDistance(_ a: [Double], _ b: [Double], band: Int = 8) -> Double {
        let n = a.count, m = b.count
        if n == 0 || m == 0 { return n == m ? 0 : .infinity }

        let w = max(band, abs(n - m) + 1)
        let inf = Double.greatestFiniteMagnitude
        // dp[j] para la fila actual; se reutiliza entre filas.
        var prev = [Double](repeating: inf, count: m + 1)
        var curr = [Double](repeating: inf, count: m + 1)
        prev[0] = 0

        for i in 1...n {
            for k in curr.indices { curr[k] = inf }
            let jLo = max(1, i - w)
            let jHi = min(m, i + w)
            for j in jLo...jHi {
                let cost = abs(a[i - 1] - b[j - 1])
                let best = min(prev[j], min(curr[j - 1], prev[j - 1]))
                curr[j] = cost + (best == inf ? inf : best)
            }
            swap(&prev, &curr)
        }

        let raw = prev[m]
        if raw >= inf { return .infinity }
        return raw / Double(n + m)   // aprox. de la longitud del camino
    }
}
