// SPDX-License-Identifier: GPL-3.0-only

import XFPrimitives

/// Fuente de muestras del crossfader. Mismo contrato que `MotionSource` pero
/// para el fader: MIDI CC, retorno de audio con tono piloto (ADR-021), teclado,
/// o replay de una sesion grabada.
///
/// La binarizacion (`FaderSample.isOpen`) se hace en la propia fuente con el
/// *cut-in* calibrado e histeresis (ADR-017); el consumidor recibe el estado ya
/// resuelto, y ademas `value` crudo por si hace falta.
public protocol FaderSource: AnyObject {
    var isConnected: Bool { get }
    func start() throws
    func stop()
    func latest() -> FaderSample?
}
