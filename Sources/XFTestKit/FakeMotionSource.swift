// SPDX-License-Identifier: GPL-3.0-only

import Foundation
import XFPrimitives
import XFCapture

/// `MotionSource` de mentira para tests: sin hardware, sin ficheros, sin hilos.
///
/// Dos modos, combinables:
///  - **script**: cada `latest()` devuelve la siguiente muestra de la lista; al
///    llegar al final repite la última.
///  - **fija**: si no hay script, `latest()` devuelve `fixed` (que el test puede
///    reasignar en cualquier momento).
///
/// Además cuenta las llamadas a `start()` / `stop()` y puede simular un fallo de
/// arranque (`startError`), para comprobar que quien la consume propaga el error
/// y respeta el ciclo de vida (`XFCapture` §3).
public final class FakeMotionSource: MotionSource {

    /// Muestras a entregar en orden, una por `latest()`. Vacío = modo fijo.
    public var script: [MotionSample]
    /// Muestra que devuelve `latest()` cuando no hay script.
    public var fixed: MotionSample?
    /// Si no es `nil`, `start()` lo lanza (p. ej. dispositivo ocupado).
    public var startError: Error?

    public private(set) var startCount = 0
    public private(set) var stopCount = 0
    private var cursor = 0

    public init(script: [MotionSample] = [], fixed: MotionSample? = nil) {
        self.script = script
        self.fixed = fixed
    }

    public var isConnected: Bool { startCount > stopCount }

    public func start() throws {
        if let e = startError { throw e }
        startCount += 1
    }

    public func stop() {
        stopCount += 1
        cursor = 0
    }

    public func latest() -> MotionSample? {
        guard isConnected else { return nil }
        guard !script.isEmpty else { return fixed }
        let s = script[min(cursor, script.count - 1)]
        cursor += 1
        return s
    }
}
