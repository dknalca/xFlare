// SPDX-License-Identifier: GPL-3.0-only

extension Scratch {

    /// Recorta la ventana `[t0, t1)` del scratch. Cuando el corte cae en mitad de
    /// una fase, esta conserva un **tramo parcial de su curva** (`u0`/`u1`) en
    /// lugar de partirse en rectas, asi que el gesto sigue siendo exacto
    /// (criterio de B3.4). Portado de `crop()` en `tools/xfn_core.py`.
    ///
    /// La base de la variante `offset` (B3.5): se compone con un ciclo de mas y
    /// se recorta la ventana desplazada.
    public func cropped(from t0: Int, to t1: Int) -> Scratch {
        precondition(t1 > t0, "la ventana de recorte necesita t1 > t0")

        var newRecord: [RecordPhase] = []
        for ph in record {
            let a = ph.t
            let b = ph.t + ph.dur
            if b <= t0 || a >= t1 { continue }          // fase fuera de la ventana
            let na = max(a, t0)
            let nb = min(b, t1)
            let q0 = ph.dur == 0 ? 0.0 : Double(na - a) / Double(ph.dur)
            let q1 = ph.dur == 0 ? 1.0 : Double(nb - a) / Double(ph.dur)
            var cut = ph
            cut.t = na - t0
            cut.dur = nb - na
            cut.u0 = ph.u0 + q0 * (ph.u1 - ph.u0)
            cut.u1 = ph.u0 + q1 * (ph.u1 - ph.u0)
            // from/to/pFrom/pTo/dist/dir/curve se conservan tal cual (igual que
            // `dict(ph, ...)` en Python).
            newRecord.append(cut)
        }

        // estado del fader al entrar en la ventana
        var stateAtT0: FaderState = .open
        for e in faderEvents {
            if e.t <= t0 { stateAtT0 = e.state } else { break }
        }
        var raw: [FaderEvent] = [FaderEvent(t: 0, state: stateAtT0)]
        for e in faderEvents where e.t > t0 && e.t < t1 {
            raw.append(FaderEvent(t: e.t - t0, state: e.state))
        }
        var clean: [FaderEvent] = []
        var last: FaderState? = nil
        for e in raw where e.state != last {
            clean.append(e)
            last = e.state
        }

        var out = self
        out.record = newRecord
        out.faderEvents = clean
        out.lengthTicks = t1 - t0
        out.clickCount = clean.filter { $0.state == .closed }.count
        return out
    }
}
