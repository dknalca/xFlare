// SPDX-License-Identifier: GPL-3.0-only

/// Maquina de estados de la sesion de gimnasio (`docs/CURRICULUM.md` §3).
///
/// Es un **valor** (`struct`), como `Transport`: no tiene hilo propio ni mira
/// ningun reloj. Quien conduce la sesion (arriba, en `XFApp`, con el driver de
/// audio contando compases) la hace avanzar llamando a los eventos:
///
/// ```
///   var s = SessionMachine()            // .warmup
///   s.beginSeries()                     // .series(index: 0)
///   s.completeSeries(passed: true)      // .rest(afterSeries: 0)
///   s.endRest()                         // .series(index: 1)
///   s.completeSeries(passed: false)     // .rest(afterSeries: 1)
///   s.endRest()                         // .series(index: 2)
///   s.completeSeries(passed: true)      // .boss          (era la ultima serie)
///   s.completeBoss()                    // .results
/// ```
///
/// Los eventos llamados en una fase que no los admite son **no-ops**
/// silenciosos (misma politica que `Transport.advance` estando parado): la
/// maquina nunca peta por una llamada fuera de orden, simplemente no se mueve.
///
/// Lo que esta tarea (B9.1) **no** hace: decidir si una serie se aprueba, ajustar
/// el BPM (escalera adaptativa, B9.2) ni el desbloqueo por compases seguidos
/// (B9.3). Aqui solo se **registra** el resultado de cada serie en
/// `seriesOutcomes` para que B9.2 lo consuma; no se actua sobre el.
public struct SessionMachine: Equatable, Sendable {

    /// Forma de la sesion (numero de series, compases por serie).
    public let config: SessionConfig

    /// Fase actual. Arranca en `.warmup`.
    public private(set) var phase: SessionPhase

    /// Resultado (aprobada / fallada) de cada serie ya completada, en orden.
    /// Lo rellena `completeSeries(passed:)`. Insumo de la escalera de BPM (B9.2);
    /// esta tarea no lo interpreta.
    public private(set) var seriesOutcomes: [Bool]

    public init(config: SessionConfig = .standard) {
        self.config = config
        self.phase = .warmup
        self.seriesOutcomes = []
    }

    // MARK: - eventos

    /// Calentamiento terminado: entra en la primera serie. No-op si no estamos
    /// en `.warmup`.
    public mutating func beginSeries() {
        guard phase == .warmup else { return }
        phase = .series(index: 0)
    }

    /// Serie en curso terminada. `passed` lo decide el scoring mas arriba
    /// (B9.2); aqui solo se guarda. Tras registrarlo:
    /// - si quedan series, pasa a `.rest(afterSeries: i)`;
    /// - si era la ultima, pasa a `.boss`.
    ///
    /// No-op si no estamos en una serie.
    public mutating func completeSeries(passed: Bool) {
        guard case .series(let index) = phase else { return }
        seriesOutcomes.append(passed)
        if index + 1 < config.seriesCount {
            phase = .rest(afterSeries: index)
        } else {
            phase = .boss
        }
    }

    /// Descanso terminado: entra en la siguiente serie. No-op si no estamos en
    /// `.rest`.
    public mutating func endRest() {
        guard case .rest(let afterSeries) = phase else { return }
        phase = .series(index: afterSeries + 1)
    }

    /// Toma del boss terminada: pasa a resultados. No-op si no estamos en
    /// `.boss`.
    public mutating func completeBoss() {
        guard phase == .boss else { return }
        phase = .results
    }

    /// Reinicia la sesion al calentamiento y olvida los resultados. Sirve para
    /// "otra vez" desde la pantalla de resultados.
    public mutating func reset() {
        phase = .warmup
        seriesOutcomes = []
    }

    // MARK: - consultas

    /// `true` en las fases que se puntuan: series y boss. El calentamiento, el
    /// descanso y los resultados no puntuan (`docs/CURRICULUM.md` §3).
    public var isScored: Bool {
        switch phase {
        case .series, .boss: return true
        case .warmup, .rest, .results: return false
        }
    }

    /// `true` cuando la sesion ha llegado a `.results` (fase terminal).
    public var isFinished: Bool { phase == .results }

    /// Indice de la serie en curso (0-based), o `nil` si ahora mismo no hay
    /// ninguna serie activa.
    public var currentSeriesIndex: Int? {
        if case .series(let index) = phase { return index }
        return nil
    }

    /// Cuantas series se han completado ya (= numero de resultados registrados).
    public var completedSeriesCount: Int { seriesOutcomes.count }
}
