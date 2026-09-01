// SPDX-License-Identifier: GPL-3.0-only

/// La escalera de BPM: "el peso de la barra" (`docs/CURRICULUM.md` §1).
///
/// Cada ejercicio trae una escalera discreta de tempos en `data/curriculum/
/// exercises.json` (`bpmLadder`, p. ej. `[60, 70, 80, 90, 100]`) y un `startBpm`.
/// Durante el bloque principal, el resultado de cada serie mueve el peso
/// (`docs/CURRICULUM.md` §3):
///
/// - **2 series falladas seguidas → baja un escalon.**
/// - **3 series superadas seguidas → sube un escalon.**
///
/// Un aprobado corta la racha de fallos y viceversa. Al tocar techo o suelo, el
/// contador se reinicia igualmente (no se queda "armado" disparando en cada
/// serie siguiente).
///
/// Es un **valor** (`struct`), como `SessionMachine` y `Transport`: sin hilo, sin
/// reloj, avanza por eventos. Quien conduce la sesion llama a `record(passed:)`
/// cada vez que cierra una serie. Si esa serie **se aprueba** (umbral de
/// `docs/SCORING.md`) lo decide el scoring mas arriba; aqui solo se cuenta.
public struct BPMLadder: Equatable, Sendable {

    /// Que ha pasado con el peso tras registrar una serie.
    public enum Step: Equatable, Sendable {
        /// El peso no se ha movido.
        case hold
        /// Ha subido un escalon.
        case up
        /// Ha bajado un escalon.
        case down
    }

    /// Cuantas series seguidas hacen subir / bajar. Fijo por currículo
    /// (`docs/CURRICULUM.md` §3), no configurable.
    public static let passesToStepUp = 3
    public static let failsToStepDown = 2

    /// Los tempos de la escalera, en BPM, **estrictamente ascendentes**.
    public let rungs: [Int]

    /// Escalon actual (indice en `rungs`).
    public private(set) var index: Int

    // Escalon de partida, para `reset()` (nuevo intento del ejercicio).
    private let startIndex: Int

    // Rachas en curso. Un aprobado pone `fails` a 0; un fallo pone `passes` a 0.
    private var passes: Int
    private var fails: Int

    /// - Parameters:
    ///   - rungs: tempos de la escalera, ascendentes y sin repetidos.
    ///   - startBPM: tempo inicial; tiene que ser uno de los de `rungs`.
    public init(rungs: [Int], startBPM: Int) {
        precondition(!rungs.isEmpty, "la escalera necesita al menos un escalon")
        precondition(zip(rungs, rungs.dropFirst()).allSatisfy { $0 < $1 },
                     "los escalones de BPM tienen que ir en orden ascendente y sin repetir")
        guard let start = rungs.firstIndex(of: startBPM) else {
            preconditionFailure("startBPM \(startBPM) no esta en la escalera \(rungs)")
        }
        self.rungs = rungs
        self.index = start
        self.startIndex = start
        self.passes = 0
        self.fails = 0
    }

    // MARK: - consultas

    /// Tempo actual, en BPM.
    public var currentBPM: Int { rungs[index] }

    /// `true` si ya no se puede subir mas.
    public var isAtTop: Bool { index == rungs.count - 1 }

    /// `true` si ya no se puede bajar mas.
    public var isAtBottom: Bool { index == 0 }

    // MARK: - evento

    /// Registra el resultado de una serie y ajusta el peso si toca.
    ///
    /// Devuelve el movimiento efectivo: `.up` / `.down` solo si el escalon ha
    /// cambiado de verdad; `.hold` si no se ha movido (incluido el caso de estar
    /// en el techo con 3 aprobados o en el suelo con 2 fallos).
    @discardableResult
    public mutating func record(passed: Bool) -> Step {
        if passed {
            passes += 1
            fails = 0
            guard passes >= Self.passesToStepUp else { return .hold }
            passes = 0
            guard !isAtTop else { return .hold }
            index += 1
            return .up
        } else {
            fails += 1
            passes = 0
            guard fails >= Self.failsToStepDown else { return .hold }
            fails = 0
            guard !isAtBottom else { return .hold }
            index -= 1
            return .down
        }
    }

    /// Vuelve al escalon de partida y olvida las rachas (nuevo intento del
    /// ejercicio desde la pantalla de resultados).
    public mutating func reset() {
        index = startIndex
        passes = 0
        fails = 0
    }
}
