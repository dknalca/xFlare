// SPDX-License-Identifier: GPL-3.0-only

import XFPrimitives

/// Modo sin mesa: el crossfader se controla con una tecla (`fader.toggle` en
/// `profiles/keyboard.conf`, normalmente Espacio).
///
/// **Momentáneo**, no conmutado: tecla pulsada = fader cortado, tecla suelta =
/// fader abierto. Es lo que pide el scratch (por defecto abierto, lo cierras un
/// instante). No hay valor continuo que binarizar: el teclado ya da un booleano.
public final class KeyboardFaderSource: FaderSource {

    private var running = false
    private var pressed = false
    private var current: FaderSample?

    /// `true` si un cierre viene con el fader ya cerrado (tecla mantenida): por
    /// defecto el estado inicial es abierto.
    public init() {}

    public var isConnected: Bool { running }

    public func start() throws {
        running = true
        pressed = false
        current = nil
    }

    public func stop() {
        running = false
    }

    public func latest() -> FaderSample? { current }

    /// La tecla del fader baja / sube. `hostTime` en el dominio del reloj de audio.
    public func keyDown(hostTime: UInt64) { update(pressed: true, hostTime: hostTime) }
    public func keyUp(hostTime: UInt64)   { update(pressed: false, hostTime: hostTime) }

    private func update(pressed p: Bool, hostTime: UInt64) {
        guard running else { return }
        pressed = p
        // pulsado => cortado; suelto => abierto
        current = FaderSample(hostTime: hostTime, value: p ? 0 : 1, isOpen: !p)
    }
}
