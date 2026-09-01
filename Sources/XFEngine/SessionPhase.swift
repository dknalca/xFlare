// SPDX-License-Identifier: GPL-3.0-only

/// Las fases por las que pasa una sesion de gimnasio, en orden
/// (`docs/CURRICULUM.md` §3):
///
/// ```
/// warmup ──▶ series(0) ──▶ rest(0) ──▶ series(1) ──▶ rest(1) ──▶ series(2) ──▶ boss ──▶ results
/// ```
///
/// El descanso solo aparece **entre** series, no despues de la ultima. El numero
/// de series lo fija `SessionConfig.seriesCount` (3 por defecto).
///
/// Esta tarea (B9.1) solo define y encadena estas fases. La escalera de BPM
/// (B9.2) y el desbloqueo por compases seguidos (B9.3) se apoyan encima sin
/// añadir fases nuevas.
public enum SessionPhase: Equatable, Sendable {

    /// Calentamiento: baby scratch libre para calibrar mano y fader. **No
    /// puntua** (`docs/CURRICULUM.md` §3).
    case warmup

    /// Serie `index` del bloque principal en curso (0-based). Cada serie son
    /// `SessionConfig.barsPerSeries` compases. Puntua.
    case series(index: Int)

    /// Descanso tras la serie `afterSeries` (0-based). No puntua.
    case rest(afterSeries: Int)

    /// La toma del "boss": el patron al BPM objetivo, una sola vez y sin red
    /// (`docs/CURRICULUM.md` §3). Puntua.
    case boss

    /// Fin de la sesion: pantalla de resultados. Fase terminal.
    case results
}
