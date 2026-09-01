// SPDX-License-Identifier: GPL-3.0-only

/// Una muestra del movimiento del disco en un instante. La produce cualquier
/// `MotionSource` (timecode, jog MIDI, teclado, replay) y la consume el analisis.
///
/// Campos segun `docs/ARCHITECTURE.md` §3.
public struct MotionSample: Equatable, Sendable {

    /// Instante de la muestra en el reloj del sistema (`mach_absolute_time`).
    /// Mismo dominio que `FaderSample.hostTime` y que CoreAudio/CoreMIDI.
    public let hostTime: UInt64

    /// Posicion acumulada del disco en **vueltas**. El signo indica el sentido
    /// de giro (creciente = adelante). No se envuelve: sigue subiendo o bajando.
    public let position: Double

    /// Velocidad instantanea. `1.0` = 33⅓ rpm nominal (reproduccion normal),
    /// `0.0` = disco parado, negativo = hacia atras.
    public let velocity: Double

    /// Calidad de la lectura, `0..1`. Con timecode baja al levantar la aguja o
    /// con senal sucia; las fuentes sinteticas (teclado, replay) suelen dar `1`.
    public let confidence: Float

    public init(hostTime: UInt64, position: Double, velocity: Double, confidence: Float) {
        self.hostTime = hostTime
        self.position = position
        self.velocity = velocity
        self.confidence = confidence
    }
}
