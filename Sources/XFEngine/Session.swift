// SPDX-License-Identifier: GPL-3.0-only

/// La puerta de entrada de XFEngine: una sesion de gimnasio completa, con sus
/// tres piezas ya cableadas entre si.
///
/// - `SessionMachine` — por que fase vamos (calentamiento, series, descanso,
///   boss, resultados).
/// - `BPMLadder` — a que BPM se toca ahora; sube o baja con el resultado de cada
///   serie.
/// - `UnlockTracker` — cuenta los compases buenos **seguidos** para el
///   desbloqueo (no de media).
///
/// El que conduce la sesion (en `XFApp`, con el driver de audio contando
/// compases con `XFClock`) habla **solo con `Session`**: `beginSeries()` cuando
/// acaba el calentamiento, `recordBar(accuracy:)` al cerrar cada compas con la
/// precision que da `XFAnalysis`, `endRest()` cuando termina el descanso,
/// `recordBoss(accuracy:)` con la toma del boss. Todo lo demas lo lleva `Session`
/// por dentro.
///
/// Es un **valor** (`struct`), como sus tres piezas: sin hilo, sin reloj,
/// determinista y testeable sin tiempo real. El scoring corre fuera del hilo de
/// audio (PLAN.md Hito E), y esto tambien: nunca se llama desde el callback.
///
/// **Que hace pasar una serie** (decision de ADR-034): una serie **se aprueba si
/// TODOS sus compases llegan al umbral de precision** (`UnlockRule.accuracy`); un
/// solo compas flojo la suspende. Es coherente con "no por media"
/// (`docs/CURRICULUM.md` §2) y con las 3 estrellas (ADR-025). El `minBPM` de la
/// regla **no** entra aqui: la escalera ya decide el tempo, gatearlo seria
/// circular. El `minBPM` solo lo aplica `UnlockTracker` para el desbloqueo.
public struct Session: Equatable, Sendable {

    /// Que ha pasado al registrar un compas con `recordBar(accuracy:)`.
    public enum BarEvent: Equatable, Sendable {
        /// No estabamos en una serie (calentamiento, descanso, boss, resultados):
        /// el compas se ignora.
        case ignored
        /// Compas contado; la serie continua.
        case barRecorded
        /// Este compas ha cerrado la serie. `passed` = todos sus compases
        /// llegaron al umbral. `bpmStep` = que hizo la escalera con ese
        /// resultado (puede que el siguiente `currentBPM` haya cambiado).
        case seriesEnded(passed: Bool, bpmStep: BPMLadder.Step)
    }

    /// Resumen final, disponible solo cuando la sesion llega a resultados.
    public struct Summary: Equatable, Sendable {
        /// Aprobado/suspenso de cada serie, en orden.
        public let seriesOutcomes: [Bool]
        /// BPM al que se acabo el bloque principal (y al que se toco el boss).
        public let finalBPM: Int
        /// Precision de la toma del boss, `0...1`.
        public let bossAccuracy: Double
        /// `true` si se consiguio la racha de desbloqueo en algun momento.
        public let unlocked: Bool
        /// Racha de compases buenos mas larga de toda la sesion.
        public let bestStreak: Int
    }

    public private(set) var machine: SessionMachine
    public private(set) var ladder: BPMLadder
    public private(set) var unlock: UnlockTracker

    // Progreso dentro de la serie en curso.
    private var barsInCurrentSeries: Int
    private var currentSeriesClean: Bool

    // Toma del boss, 0 hasta que se registra.
    private var bossAccuracy: Double

    public init(config: SessionConfig = .standard,
                ladder: BPMLadder,
                unlock: UnlockTracker) {
        self.machine = SessionMachine(config: config)
        self.ladder = ladder
        self.unlock = unlock
        self.barsInCurrentSeries = 0
        self.currentSeriesClean = true
        self.bossAccuracy = 0
    }

    // MARK: - consultas de conveniencia

    public var phase: SessionPhase { machine.phase }
    public var currentBPM: Int { ladder.currentBPM }
    public var isUnlocked: Bool { unlock.isUnlocked }
    public var isFinished: Bool { machine.isFinished }

    /// Compases buenos que faltan para el desbloqueo (0 si ya esta).
    public var barsToUnlock: Int { unlock.barsRemaining }

    /// Disponible solo en la fase de resultados.
    public var summary: Summary? {
        guard machine.isFinished else { return nil }
        return Summary(seriesOutcomes: machine.seriesOutcomes,
                       finalBPM: ladder.currentBPM,
                       bossAccuracy: bossAccuracy,
                       unlocked: unlock.isUnlocked,
                       bestStreak: unlock.bestStreak)
    }

    // MARK: - eventos

    /// Calentamiento terminado: entra en la primera serie. No-op fuera del
    /// calentamiento.
    public mutating func beginSeries() {
        machine.beginSeries()
    }

    /// Registra un compas de la serie en curso con su precision (`0...1`).
    ///
    /// Alimenta la racha de desbloqueo con `(accuracy, currentBPM)`, lleva la
    /// cuenta de compases de la serie y, al llegar a `barsPerSeries`, la cierra:
    /// decide aprobado/suspenso, mueve la escalera de BPM y prepara la siguiente.
    @discardableResult
    public mutating func recordBar(accuracy: Double) -> BarEvent {
        guard machine.currentSeriesIndex != nil else { return .ignored }

        unlock.record(barAccuracy: accuracy, bpm: ladder.currentBPM)

        barsInCurrentSeries += 1
        if accuracy < unlock.rule.accuracy {
            currentSeriesClean = false
        }

        guard barsInCurrentSeries >= machine.config.barsPerSeries else {
            return .barRecorded
        }

        let passed = currentSeriesClean
        machine.completeSeries(passed: passed)
        let step = ladder.record(passed: passed)
        barsInCurrentSeries = 0
        currentSeriesClean = true
        return .seriesEnded(passed: passed, bpmStep: step)
    }

    /// Descanso terminado: entra en la siguiente serie. No-op fuera del descanso.
    public mutating func endRest() {
        machine.endRest()
    }

    /// Registra la toma del boss con su precision (`0...1`) y pasa a resultados.
    /// El boss no alimenta la racha de desbloqueo (es "sin red", una medida
    /// aparte). No-op fuera de la fase de boss.
    public mutating func recordBoss(accuracy: Double) {
        guard machine.phase == .boss else { return }
        bossAccuracy = accuracy
        machine.completeBoss()
    }

    /// Reinicia la sesion entera para "otra vez": calentamiento, escalera en su
    /// BPM de partida, racha a cero.
    public mutating func reset() {
        machine.reset()
        ladder.reset()
        unlock.reset()
        barsInCurrentSeries = 0
        currentSeriesClean = true
        bossAccuracy = 0
    }
}
