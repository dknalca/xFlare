// SPDX-License-Identifier: GPL-3.0-only

/// Una fase ya compuesta del carril de disco (`record`): un tramo de movimiento
/// con su sitio en el tiempo.
///
/// `from`/`to` son los extremos "nominales" del recorrido (lo que se dibuja y lo
/// que trae `data/scratches/library-v0.1.json`). `pFrom`/`pTo` son los extremos
/// "fisicos" que usa `PositionSampler` — iguales a `from`/`to` salvo que una
/// variante de amplitud o espejo los haya cambiado. `u0`/`u1` acotan el tramo de
/// la curva que se usa (0..1 completo, salvo que un recorte de `offset` haya
/// dejado media fase). Portado de `xfn_core.py` (segundo `position_at` + `crop`).
public struct RecordPhase: Codable, Sendable, Equatable {

    public var t: Int
    public var dur: Int
    public var dir: Direction
    public var dist: Double
    public var curve: Curve
    public var from: Double
    public var to: Double
    public var u0: Double
    public var u1: Double
    public var pFrom: Double
    public var pTo: Double

    public init(t: Int, dur: Int, dir: Direction, dist: Double, curve: Curve,
                from: Double, to: Double,
                u0: Double = 0.0, u1: Double = 1.0,
                pFrom: Double? = nil, pTo: Double? = nil) {
        self.t = t
        self.dur = dur
        self.dir = dir
        self.dist = dist
        self.curve = curve
        self.from = from
        self.to = to
        self.u0 = u0
        self.u1 = u1
        self.pFrom = pFrom ?? from
        self.pTo = pTo ?? to
    }

    private enum CodingKeys: String, CodingKey {
        case t, dur, dir, dist, curve, from, to, u0, u1, pFrom, pTo
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.t = try c.decode(Int.self, forKey: .t)
        self.dur = try c.decode(Int.self, forKey: .dur)
        self.dir = try c.decode(Direction.self, forKey: .dir)
        self.dist = try c.decodeIfPresent(Double.self, forKey: .dist) ?? 0.0
        self.curve = try c.decode(Curve.self, forKey: .curve)
        self.from = try c.decode(Double.self, forKey: .from)
        self.to = try c.decode(Double.self, forKey: .to)
        // los cuatro campos de tramo parcial son opcionales: si faltan, la fase
        // usa su curva entera y sus extremos nominales (es un scratch base).
        self.u0 = try c.decodeIfPresent(Double.self, forKey: .u0) ?? 0.0
        self.u1 = try c.decodeIfPresent(Double.self, forKey: .u1) ?? 1.0
        self.pFrom = try c.decodeIfPresent(Double.self, forKey: .pFrom) ?? self.from
        self.pTo = try c.decodeIfPresent(Double.self, forKey: .pTo) ?? self.to
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(t, forKey: .t)
        try c.encode(dur, forKey: .dur)
        try c.encode(dir, forKey: .dir)
        try c.encode(dist, forKey: .dist)
        try c.encode(curve, forKey: .curve)
        try c.encode(from, forKey: .from)
        try c.encode(to, forKey: .to)
        // solo se serializan los campos de tramo parcial si aportan algo, para
        // que un scratch base salga con las mismas 7 claves que la referencia.
        if u0 != 0.0 { try c.encode(u0, forKey: .u0) }
        if u1 != 1.0 { try c.encode(u1, forKey: .u1) }
        if pFrom != from { try c.encode(pFrom, forKey: .pFrom) }
        if pTo != to { try c.encode(pTo, forKey: .pTo) }
    }
}

/// Un cambio de estado del crossfader en el carril `faderEvents`.
public struct FaderEvent: Codable, Sendable, Equatable {
    public var t: Int
    public var state: FaderState

    public init(t: Int, state: FaderState) {
        self.t = t
        self.state = state
    }
}
