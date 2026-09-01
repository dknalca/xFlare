// SPDX-License-Identifier: GPL-3.0-only

/// El resultado completo de puntuar una toma contra un patron.
public struct Report: Equatable, Sendable {

    /// Puntuacion total conseguida y maxima posible (SCORING.md §1).
    public let score: Int
    public let maxScore: Int
    /// `score / maxScore`, 0..1.
    public var accuracy: Double { maxScore > 0 ? Double(score) / Double(maxScore) : 0 }

    /// Un elemento por click del patron, con su desfase con signo.
    public let clickOffsets: [ClickOffset]

    /// Distancia DTW normalizada del contorno de tono (0 = identico). Afinacion
    /// **relativa** (ADR-005): compara forma y direccion, no valores absolutos.
    public let pitchDistance: Double

    /// Regularidad del timing: desviacion tipica de los desfases de click, en ms.
    public let sigmaMs: Double

    /// Sesgo del timing: media de los desfases con signo, en ms (+ = tarde).
    public let biasMs: Double

    /// Error relativo medio de recorrido de los trazos hacia delante (0 = exacto).
    public let amplitudeError: Double

    /// Cuantos clicks del patron no ha ejecutado el usuario.
    public let missedClicks: Int

    /// `true` si la toma llego hasta el final del patron.
    public let finished: Bool

    /// Estrellas conseguidas (0..3), por criterios ortogonales (ADR-025).
    public let stars: Int
    /// Por que NO se ha llegado a la siguiente estrella (para la UI: "las
    /// estrellas apagadas dicen que falta").
    public let starReasons: [String]

    /// Frases de diagnostico accionables (ADR-018).
    public let diagnostics: [Diagnostic]
}
