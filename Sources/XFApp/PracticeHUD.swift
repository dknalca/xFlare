// SPDX-License-Identifier: GPL-3.0-only

import XFDesign
import XFEngine

/// El texto de las barras de la pantalla de práctica (`docs/UI_DESIGN.md` §3.3):
/// la fina de arriba (nombre · fase · BPM · %) y la de abajo (últimos clicks +
/// **una sola** frase de feedback en vivo).
///
/// Value type puro: se arma en cada fotograma a partir de la `Session` y de lo
/// que trae el scoring. No formatea nada más que texto.
public struct PracticeHUD: Equatable, Sendable {

    public var exerciseName: String
    public var phaseLabel: String
    /// "Serie 2/3" mientras hay una serie; `nil` en calentamiento / descanso /
    /// boss / resultados.
    public var seriesLabel: String?
    public var bpm: Int
    /// Precisión en curso, 0…100. `nil` si la fase no puntúa o aún no hay dato.
    public var accuracyPercent: Int?
    /// `true` durante la cuenta atrás de dos compases (aún no se puntúa).
    public var isCountingIn: Bool
    /// Últimos clicks como niveles de acierto, para los ●●●○○ (viejo→nuevo).
    public var recentClicks: [HitLevel]
    /// La frase de feedback en vivo. **Como mucho una.**
    public var liveFeedback: String?

    public static func build(session: Session,
                             exerciseName: String,
                             accuracy: Double?,
                             countInBarsRemaining: Int,
                             recentClickOffsetsMs: [Double],
                             liveFeedback: String?) -> PracticeHUD {

        let phaseLabel: String
        var seriesLabel: String?
        switch session.phase {
        case .warmup:
            phaseLabel = "Calentamiento"
        case .series(let i):
            phaseLabel = "Serie \(i + 1)/\(session.machine.config.seriesCount)"
            seriesLabel = phaseLabel
        case .rest:
            phaseLabel = "Descanso"
        case .boss:
            phaseLabel = "Boss"
        case .results:
            phaseLabel = "Resultados"
        }

        let counting = countInBarsRemaining > 0
        let pct: Int?
        if session.machine.isScored, !counting, let a = accuracy {
            pct = Int((min(1, max(0, a)) * 100).rounded())
        } else {
            pct = nil
        }

        return PracticeHUD(
            exerciseName: exerciseName,
            phaseLabel: phaseLabel,
            seriesLabel: seriesLabel,
            bpm: session.currentBPM,
            accuracyPercent: pct,
            isCountingIn: counting,
            recentClicks: recentClickOffsetsMs.suffix(5).map { HitLevel(absOffsetMs: abs($0)) },
            liveFeedback: liveFeedback)
    }
}
