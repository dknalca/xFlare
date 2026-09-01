// SPDX-License-Identifier: GPL-3.0-only

/// Una lectura del plato para el scope: la fase acumulada de la aguja, la
/// velocidad y la confianza de la señal. Sale de `CXFTimecode` (vía la capa de
/// captura); `XFRender` solo la dibuja.
///
/// `position` está en "vueltas de referencia" (la integral de la velocidad que
/// devuelve `xf_timecoder_position`): una vuelta entera = una vuelta del scope.
public struct ScopeReading: Equatable, Sendable {
    public var position: Double
    /// `1.0` = reproducción normal, `0` = parado, negativo = hacia atrás.
    public var velocity: Double
    /// `0...1`. Cae al levantar la aguja o con señal sucia.
    public var confidence: Double

    public init(position: Double, velocity: Double, confidence: Double) {
        self.position = position
        self.velocity = velocity
        self.confidence = confidence
    }
}
