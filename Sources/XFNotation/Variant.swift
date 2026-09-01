// SPDX-License-Identifier: GPL-3.0-only

import XFClock

/// Transformaciones de variante `Scratch -> Scratch` (ADR-026, docs/VARIANTS.md).
/// `offset` / `amplitude` / `mirror` / `swing` portadas de `tools/xfn_core.py`.
///
/// `subdivision` (abajo, en `Composer`) **no** estaba en la referencia Python: se
/// implementa recomponiendo con otra `division` y ajustando los ciclos para que
/// la longitud musical no cambie.
///
/// `dropout` (variante `blind` de `variants.json`) **no vive en este modulo**: no
/// transforma el patron, solo apaga la guia visual en algunos compases y decide
/// que compases puntuan. Eso es logica de sesion (`XFEngine`), no de notacion.
public extension Scratch {

    /// `amplitude(scale)` — escala el recorrido del disco sin tocar el tiempo.
    /// Cambia `pFrom`/`pTo`/`dist` (lo fisico); `from`/`to` nominales se quedan.
    func withAmplitude(scale: Double) -> Scratch {
        var out = self
        out.record = record.map { p in
            var q = p
            q.pFrom = p.pFrom * scale
            q.pTo = p.pTo * scale
            q.dist = p.dist * scale
            return q
        }
        return out
    }

    /// `mirror` — invierte el sentido del gesto (no es el modo hamster, que es
    /// del perfil de mesa). Niega `pFrom`/`pTo`/`dist` e intercambia fwd<->rev.
    func mirrored() -> Scratch {
        var out = self
        out.record = record.map { p in
            var q = p
            q.pFrom = -p.pFrom
            q.pTo = -p.pTo
            q.dist = -p.dist
            switch p.dir {
            case .fwd: q.dir = .rev
            case .rev: q.dir = .fwd
            case .hold: q.dir = .hold
            }
            return q
        }
        return out
    }

    /// `swing(ratio)` — deforma la rejilla de corcheas. `0.5` recto, `0.62` swing
    /// marcado, `0.66` tresillo. Los clicks se desplazan CON la rejilla.
    func withSwing(ratio: Double, ppq: Int = XFClock.ppq) -> Scratch {
        let unit = ppq / 2
        let pair = unit * 2
        func warp(_ t: Int) -> Int {
            let n = t / pair
            let r = t % pair
            let nr: Double = (r <= unit)
                ? Double(r) * (2.0 * ratio)
                : Double(pair) * ratio + Double(r - unit) * 2.0 * (1.0 - ratio)
            return Int((Double(n * pair) + nr).rounded(.toNearestOrEven))
        }
        var out = self
        out.record = record.map { p in
            var q = p
            q.t = warp(p.t)
            q.dur = max(warp(p.t + p.dur) - warp(p.t), 1)
            return q
        }
        out.faderEvents = faderEvents.map { FaderEvent(t: warp($0.t), state: $0.state) }
        return out
    }
}

public extension Composer {

    /// `subdivision(newDivision)` — "doble tiempo". Recompone el mismo patron de
    /// mano y fader con otra subdivision, ajustando los ciclos para que la
    /// **longitud musical no cambie**: asi tiene el doble de clicks (y el doble
    /// de puntos posibles), no es "lo mismo mas rapido" (docs/VARIANTS.md §3).
    ///
    /// `nuevosCiclos = round(ciclos * unidadVieja / unidadNueva)`. Para el
    /// 2-Click Flare (1/8, 4 ciclos) pasando a 1/16: 4 * 240/120 = 8 ciclos,
    /// misma longitud (1920 ticks), 32 clicks.
    static func composeWithSubdivision(
        _ scratch: Scratch,
        to newDivText: String,
        ppq: Int = XFClock.ppq,
        primitives: PrimitiveSet
    ) throws -> Scratch {
        guard let oldDiv = Division(scratch.div), let newDiv = Division(newDivText) else {
            throw XFNError.invalidDivision(scratch.div + " / " + newDivText)
        }
        let oldUnit = oldDiv.unitTicks(ppq: ppq)
        let newUnit = newDiv.unitTicks(ppq: ppq)
        let newCycles = Int((Double(scratch.cycles) * Double(oldUnit) / Double(newUnit)).rounded(.toNearestOrEven))
        return try compose(hand: scratch.hand, fader: scratch.fader, division: newDivText,
                           cycles: max(1, newCycles), ppq: ppq, primitives: primitives,
                           id: scratch.id, name: scratch.name, level: scratch.level,
                           family: scratch.family, notes: scratch.notes)
    }

    /// `offset(fraction)` — entrar desplazado. Se compone con un ciclo de mas y
    /// se recorta la ventana desplazada (por eso hace falta recomponer, no basta
    /// con un `Scratch` ya hecho). Portado de `v_offset`.
    static func composeWithOffset(
        hand handID: String,
        fader faderID: String,
        division divText: String,
        cycles: Int,
        fraction: Double,
        ppq: Int = XFClock.ppq,
        primitives: PrimitiveSet
    ) throws -> Scratch {
        let ext = try compose(hand: handID, fader: faderID, division: divText,
                              cycles: cycles + 1, ppq: ppq, primitives: primitives)
        let cyc = ext.lengthTicks / (cycles + 1)
        let start = Int((fraction * Double(cyc)).rounded(.toNearestOrEven))
        return ext.cropped(from: start, to: start + cyc * cycles)
    }
}
