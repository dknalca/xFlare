// SPDX-License-Identifier: GPL-3.0-only

import XFClock

/// El compositor mano × fader. Porta literalmente `compose()` de
/// `tools/xfn_core.py`; el golden de B3.3 comprueba que da lo mismo.
public enum Composer {

    /// Redondeo a 4 decimales, medio-a-par, como `round(x, 4)` de Python. No se
    /// reutiliza `XFTestKit.Golden.round4` porque XFTestKit depende de este
    /// modulo, no al reves.
    static func round4(_ x: Double) -> Double {
        (x * 10_000).rounded(.toNearestOrEven) / 10_000
    }

    private static func round6(_ x: Double) -> Double {
        (x * 1_000_000).rounded(.toNearestOrEven) / 1_000_000
    }

    /// Entero mas cercano medio-a-par, como `int(round(x))` de Python.
    private static func iround(_ x: Double) -> Int {
        Int(x.rounded(.toNearestOrEven))
    }

    /// Compone un scratch a partir de un patron de mano, uno de fader, una
    /// subdivision y un numero de ciclos. Los parametros opcionales
    /// (`id`, `name`, `level`, `family`, `notes`) son los que trae
    /// `tools/catalog.json`; si son `nil` se derivan igual que en Python.
    public static func compose(
        hand handID: String,
        fader faderID: String,
        division divText: String = "1/8",
        cycles: Int = 4,
        bpmReference: Int = 90,
        ppq: Int = XFClock.ppq,
        primitives: PrimitiveSet,
        id: String? = nil,
        name: String? = nil,
        level: Int? = nil,
        family: String? = nil,
        notes: String? = nil
    ) throws -> Scratch {

        let hand = try primitives.hand(handID)
        let fad = try primitives.fader(faderID)
        guard let division = Division(divText) else { throw XFNError.invalidDivision(divText) }
        let unit = division.unitTicks(ppq: ppq)

        // El patron de mano debe cerrar el bucle: sum(dist) == 0.
        let closure = round6(hand.phases.reduce(0.0) { $0 + $1.dist })
        if closure != 0.0 {
            throw XFNError.handPatternDoesNotClose(id: handID, residual: closure)
        }

        var record: [RecordPhase] = []
        // se guarda tambien el indice de insercion para un orden estable al
        // ordenar por `t` (Python usa list.sort, que es estable).
        var rawFader: [(t: Int, state: FaderState, seq: Int)] = [(0, fad.initial, 0)]
        var seq = 1

        var t = 0
        var pos = 0.0
        for _ in 0..<cycles {
            for ph in hand.phases {
                let dur = iround(ph.units * Double(unit))
                let from = round4(pos)
                let to = round4(pos + ph.dist)
                record.append(RecordPhase(t: t, dur: dur, dir: ph.dir, dist: ph.dist,
                                          curve: ph.curve, from: from, to: to))
                for rule in fad.rules(for: ph.dir) {
                    rawFader.append((t + iround(rule.frac * Double(dur)), rule.state, seq))
                    seq += 1
                }
                pos += ph.dist
                t += dur
            }
        }

        // orden estable por t, y limpieza de estados repetidos consecutivos.
        let sorted = rawFader.sorted { $0.t != $1.t ? $0.t < $1.t : $0.seq < $1.seq }
        var clean: [FaderEvent] = []
        var last: FaderState? = nil
        for e in sorted where e.state != last {
            clean.append(FaderEvent(t: e.t, state: e.state))
            last = e.state
        }
        let clickCount = clean.filter { $0.state == .closed }.count

        return Scratch(
            id: id ?? "\(handID)__\(faderID)__\(divText.replacingOccurrences(of: "/", with: "-"))",
            name: name ?? "\(hand.name) \(fad.name)",
            family: family ?? String(faderID.split(separator: "_", omittingEmptySubsequences: false)[0]),
            level: level ?? max(hand.level, fad.level),
            hand: handID,
            fader: faderID,
            div: divText,
            cycles: cycles,
            technique: fad.technique,
            ppq: ppq,
            bpmReference: bpmReference,
            lengthTicks: t,
            clickCount: clickCount,
            record: record,
            faderEvents: clean,
            notes: notes ?? ""
        )
    }
}
