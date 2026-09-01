// SPDX-License-Identifier: GPL-3.0-only

import XFPrimitives

/// La app nunca habla con el hardware: habla con esto. Una `MotionSource`
/// entrega muestras del movimiento del disco, venga de donde venga (vinilo de
/// timecode, jog MIDI, teclado, una sesion grabada).
///
/// Contrato (docs/ARCHITECTURE.md §3):
/// - `latest()` devuelve la ultima muestra disponible, o `nil` si aun no hay.
/// - `start()` puede fallar (dispositivo ocupado, permiso denegado...).
/// - Es `AnyObject`: las implementaciones tienen identidad (un puerto, un fichero).
public protocol MotionSource: AnyObject {
    /// `true` si la fuente esta lista para entregar muestras.
    var isConnected: Bool { get }
    /// Arranca la captura. Lanza si no se puede.
    func start() throws
    /// Detiene la captura. Idempotente.
    func stop()
    /// La muestra mas reciente, o `nil` si todavia no hay ninguna.
    func latest() -> MotionSample?
}
