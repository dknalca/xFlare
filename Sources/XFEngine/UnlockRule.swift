// SPDX-License-Identifier: GPL-3.0-only

/// La condicion para dar algo por superado. `docs/CURRICULUM.md` §2:
///
/// > Hay que superar el umbral de precision **en N compases seguidos**, no de
/// > media. La media perdona los fallos; el streak no.
///
/// Cubre las dos formas que hay en `data/curriculum/`:
/// - `pass` de un ejercicio (`exercises.json`): `accuracy` + `consecutiveBars`,
///   sin BPM → `minBPM == nil`.
/// - `unlock` de un nivel (`levels.json`): ademas exige que la racha ocurra a un
///   BPM minimo → `minBPM != nil`.
public struct UnlockRule: Equatable, Sendable {

    /// Precision minima de un compas para que "cuente", en `0...1`. La
    /// comparacion es `>=`: un compas justo en el umbral cuenta.
    public let accuracy: Double

    /// Compases buenos **seguidos** que hay que encadenar. `>= 1`.
    public let consecutiveBars: Int

    /// BPM minimo al que tiene que producirse la racha, o `nil` si el tempo da
    /// igual. Un compas por debajo de este BPM no cuenta y rompe la racha.
    public let minBPM: Int?

    public init(accuracy: Double, consecutiveBars: Int, minBPM: Int? = nil) {
        precondition((0.0...1.0).contains(accuracy), "accuracy va en 0...1")
        precondition(consecutiveBars >= 1, "consecutiveBars tiene que ser >= 1")
        if let minBPM { precondition(minBPM > 0, "minBPM tiene que ser > 0") }
        self.accuracy = accuracy
        self.consecutiveBars = consecutiveBars
        self.minBPM = minBPM
    }
}
