// SPDX-License-Identifier: GPL-3.0-only

import XFPrimitives

/// Reproduce las muestras de disco de una sesion grabada. Es la base de los
/// tests de replay (docs/ARCHITECTURE.md §4) y de "revisar tu toma".
///
/// No mira ningun reloj: el driver la hace avanzar con `seek(toHostTime:)`
/// usando el reloj de AUDIO, igual que el transporte. Asi el replay es
/// determinista.
public final class ReplayMotionSource: MotionSource {

    private let samples: [MotionSample]
    private var cursor = 0          // nº de muestras ya "pasadas"
    private var running = false

    public init(_ samples: [MotionSample]) {
        self.samples = samples
    }

    public convenience init(session: XFSession) {
        self.init(session.motion)
    }

    public var isConnected: Bool { running }

    public func start() throws {
        running = true
        cursor = 0
    }

    public func stop() {
        running = false
    }

    /// La ultima muestra cuyo `hostTime` ya ha pasado, o `nil` si aun ninguna.
    public func latest() -> MotionSample? {
        guard running, cursor > 0 else { return nil }
        return samples[cursor - 1]
    }

    /// Avanza el replay hasta `hostTime` inclusive. Lo llama el driver cada
    /// bloque de audio.
    public func seek(toHostTime hostTime: UInt64) {
        while cursor < samples.count && samples[cursor].hostTime <= hostTime {
            cursor += 1
        }
    }

    /// Todas las muestras de la toma (para construir un `Take` de una sola vez,
    /// que es como las consume el scoring).
    public var allSamples: [MotionSample] { samples }

    /// `true` cuando ya se han reproducido todas.
    public var isFinished: Bool { cursor >= samples.count }
}
