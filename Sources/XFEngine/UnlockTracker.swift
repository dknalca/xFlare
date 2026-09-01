// SPDX-License-Identifier: GPL-3.0-only

/// Lleva la cuenta de compases buenos **seguidos** contra una `UnlockRule` y
/// decide cuando algo queda superado (`docs/CURRICULUM.md` §2).
///
/// La clave es que un solo compas flojo pone el contador a 0: no se hace media,
/// se cuenta la racha. Por eso "un 88% con un fallo suelto" no basta (misma
/// filosofia que las 3 estrellas, ADR-025).
///
/// Es un **valor** (`struct`), como `SessionMachine` y `BPMLadder`: sin hilo, sin
/// reloj. Quien conduce la sesion llama a `record(barAccuracy:bpm:)` al cerrar
/// cada compas, con la precision que le da `XFAnalysis` y el BPM al que se toco
/// ese compas.
///
/// `isUnlocked` **se queda pegado** en cuanto se consigue la racha: un compas
/// posterior malo ya no lo quita. Para reutilizar el tracker en otro intento,
/// `reset()`.
public struct UnlockTracker: Equatable, Sendable {

    /// La condicion que se esta persiguiendo.
    public let rule: UnlockRule

    /// Compases buenos seguidos ahora mismo. Vuelve a 0 con cualquier compas que
    /// no cuente.
    public private(set) var currentStreak: Int

    /// La racha mas larga alcanzada (para "te has quedado en 5 de 8"). No se
    /// resetea al romperse la racha, solo con `reset()`.
    public private(set) var bestStreak: Int

    /// `true` una vez conseguida la racha pedida. No se vuelve atras.
    public private(set) var isUnlocked: Bool

    public init(rule: UnlockRule) {
        self.rule = rule
        self.currentStreak = 0
        self.bestStreak = 0
        self.isUnlocked = false
    }

    // MARK: - consultas

    /// Compases buenos que faltan para el desbloqueo. 0 si ya esta desbloqueado.
    public var barsRemaining: Int {
        isUnlocked ? 0 : max(0, rule.consecutiveBars - currentStreak)
    }

    // MARK: - evento

    /// Registra un compas. `barAccuracy` en `0...1`, `bpm` el tempo al que se
    /// toco. Devuelve `isUnlocked` tras procesarlo.
    ///
    /// Un compas cuenta si su precision llega al umbral **y** (si la regla pide
    /// BPM) se toco a ese BPM o mas. Si no cuenta, la racha se va a 0.
    @discardableResult
    public mutating func record(barAccuracy: Double, bpm: Int) -> Bool {
        let meetsAccuracy = barAccuracy >= rule.accuracy
        let meetsBPM = rule.minBPM.map { bpm >= $0 } ?? true

        if meetsAccuracy && meetsBPM {
            currentStreak += 1
            bestStreak = max(bestStreak, currentStreak)
            if currentStreak >= rule.consecutiveBars {
                isUnlocked = true
            }
        } else {
            currentStreak = 0
        }
        return isUnlocked
    }

    /// Vuelve al estado inicial (nueva toma / nuevo ejercicio). Olvida tambien el
    /// desbloqueo: si hay que recordarlo entre sesiones, eso es `XFPersistence`.
    public mutating func reset() {
        currentStreak = 0
        bestStreak = 0
        isUnlocked = false
    }
}
