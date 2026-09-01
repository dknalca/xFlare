// SPDX-License-Identifier: GPL-3.0-only

/// Las tablas de puntuacion de `data/curriculum/scoring.json` / `docs/SCORING.md`.
/// Se copian aqui (son el contrato, no cambian sin ADR) en vez de leer el JSON
/// en runtime: el modulo es puro y no toca disco.
public enum ScoringConstants {

    /// Cada evento evaluable vale como mucho esto.
    public static let eventValue = 100

    /// Ventanas de `click`: `(umbral_ms, puntos)`. Se aplica la primera cuyo
    /// `|desfase| <= umbral`. Fuera de todas: 0.
    public static let clickWindowsMs: [(threshold: Double, points: Int)] = [
        (20, 100), (40, 75), (70, 50), (110, 25),
    ]

    /// Bandas de `pitch` (distancia local de contorno DTW): `(umbral, puntos)`.
    public static let pitchBands: [(threshold: Double, points: Int)] = [
        (0.05, 100), (0.12, 75), (0.22, 50), (0.35, 25),
    ]

    /// Bandas de `amplitude` (error relativo de recorrido): `(umbral, puntos)`.
    public static let amplitudeBands: [(threshold: Double, points: Int)] = [
        (0.10, 100), (0.20, 75), (0.35, 50), (0.50, 25),
    ]

    /// Umbrales de estrella (ADR-025).
    public static let star1Accuracy = 0.70
    public static let star2Accuracy = 0.85
    public static let star3Accuracy = 0.95
    public static let star3SigmaMs = 15.0

    /// Puntos de una tabla de bandas para un valor dado.
    static func points(for value: Double, bands: [(threshold: Double, points: Int)]) -> Int {
        for b in bands where value <= b.threshold { return b.points }
        return 0
    }
}
