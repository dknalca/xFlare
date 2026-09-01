// SPDX-License-Identifier: GPL-3.0-only

/// Muestrea los dos carriles de un scratch en un tick dado. Funciones puras,
/// portadas de `position_at` / `fader_at` de `tools/xfn_core.py` (la version con
/// tramo parcial de curva).
public enum PositionSampler {

    /// Posicion del disco en `tick`, en unidades de recorrido. Respeta el tramo
    /// parcial `u0..u1` y los extremos fisicos `pFrom..pTo`, asi que recortar por
    /// la mitad de un movimiento conserva la curva exacta (criterio de B3.4).
    public static func position(of scratch: Scratch, atTick tick: Int) -> Double {
        for ph in scratch.record where ph.t <= tick && tick <= ph.t + ph.dur {
            let q = ph.dur == 0 ? 0.0 : Double(tick - ph.t) / Double(ph.dur)
            let u = ph.u0 + q * (ph.u1 - ph.u0)
            return ph.pFrom + (ph.pTo - ph.pFrom) * ph.curve.value(u)
        }
        guard let last = scratch.record.last else { return 0.0 }
        return last.pFrom + (last.pTo - last.pFrom) * last.curve.value(last.u1)
    }

    /// Estado del fader en `tick`. Antes del primer evento se asume abierto.
    public static func faderState(of scratch: Scratch, atTick tick: Int) -> FaderState {
        var state: FaderState = .open
        for e in scratch.faderEvents {
            if e.t <= tick { state = e.state } else { break }
        }
        return state
    }
}
