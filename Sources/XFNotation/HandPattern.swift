// SPDX-License-Identifier: GPL-3.0-only

/// Un patron de MANO: la forma del movimiento del disco, sin fader.
///
/// Decodifica `data/primitives/hand_patterns.json` sin perdida. Cada fase es un
/// tramo de movimiento continuo; la suma de `dist` de todas las fases debe ser 0
/// o el patron no cierra en bucle (se comprueba en `Composer`).
public struct HandPattern: Codable, Sendable, Equatable {

    /// Una fase de movimiento continuo.
    public struct Phase: Codable, Sendable, Equatable {
        /// Sentido del movimiento.
        public let dir: Direction
        /// Duracion relativa, en "unidades" de la subdivision elegida al componer.
        public let units: Double
        /// Recorrido del disco en unidades de patron (+ adelante, − atras).
        public let dist: Double
        /// Perfil de velocidad de la fase.
        public let curve: Curve
    }

    /// Nombre legible ("Baby", "Tear (2 partes)"...).
    public let name: String
    /// Nivel de dificultad sugerido del patron (1..10).
    public let level: Int
    /// Descripcion corta para el usuario.
    public let desc: String
    /// Las fases en orden.
    public let phases: [Phase]
}
