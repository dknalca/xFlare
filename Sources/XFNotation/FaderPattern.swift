// SPDX-License-Identifier: GPL-3.0-only

/// Un patron de FADER: cuando abre y cierra el crossfader, expresado en
/// **fracciones de la fase** (0..1), no en ticks, para que escale con el tempo
/// y la subdivision (ADR-015 / docs/NOTATION.md §3).
///
/// Decodifica `data/primitives/fader_patterns.json` sin perdida.
public struct FaderPattern: Codable, Sendable, Equatable {

    /// Una regla "en la fraccion `frac` de la fase, el fader pasa a `state`".
    /// En el JSON es un array heterogeneo `[0.96, "closed"]`, de ahi el decode
    /// manual.
    public struct Rule: Codable, Sendable, Equatable {
        public let frac: Double
        public let state: FaderState

        public init(frac: Double, state: FaderState) {
            self.frac = frac
            self.state = state
        }

        public init(from decoder: Decoder) throws {
            var c = try decoder.unkeyedContainer()
            self.frac = try c.decode(Double.self)
            self.state = try c.decode(FaderState.self)
        }

        public func encode(to encoder: Encoder) throws {
            var c = encoder.unkeyedContainer()
            try c.encode(frac)
            try c.encode(state)
        }
    }

    public let name: String
    public let level: Int
    /// Que dedos/tecnica pide ("indice", "4 dedos contra pulgar"...).
    public let technique: String
    public let desc: String
    /// Estado del fader al empezar el scratch.
    public let initial: FaderState
    /// Reglas por sentido de fase. Claves: `"fwd"`, `"rev"`, `"hold"`, o `"any"`
    /// (se aplica a cualquier sentido que no tenga clave propia). Portado de
    /// `per_phase` en `tools/xfn_core.py`.
    public let perPhase: [String: [Rule]]

    private enum CodingKeys: String, CodingKey {
        case name, level, technique, desc, initial
        case perPhase = "per_phase"
    }

    /// Reglas aplicables a una fase con el sentido `dir`: las especificas de ese
    /// sentido si existen, si no las de `"any"`, si no ninguna. Misma resolucion
    /// que `fad["per_phase"].get(dir, fad["per_phase"].get("any", []))`.
    public func rules(for dir: Direction) -> [Rule] {
        perPhase[dir.rawValue] ?? perPhase["any"] ?? []
    }
}
