// SPDX-License-Identifier: GPL-3.0-only

import XFClock
import XFPrimitives

/// Modo libre: sin evaluación, siempre grabando **los últimos 30 s**
/// (`docs/UI_DESIGN.md` §3.5). Un búfer rodante: al llegar una muestra nueva se
/// tiran las que quedan fuera de la ventana.
///
/// No mira el reloj: el driver le pasa cada muestra con su `hostTime`. Así es
/// determinista y testeable.
public final class FreeModeRecorder {

    /// Duración de la ventana en segundos.
    public let windowSeconds: Double
    private let host: HostClock

    private(set) public var motion: [MotionSample] = []
    private(set) public var fader: [FaderSample] = []

    public init(windowSeconds: Double = 30, host: HostClock = HostClock()) {
        self.windowSeconds = windowSeconds
        self.host = host
    }

    public func append(motion sample: MotionSample) {
        motion.append(sample)
        trim(now: sample.hostTime)
    }

    public func append(fader sample: FaderSample) {
        fader.append(sample)
        trim(now: sample.hostTime)
    }

    /// Vacía el búfer (al salir del modo libre).
    public func reset() {
        motion.removeAll(keepingCapacity: true)
        fader.removeAll(keepingCapacity: true)
    }

    /// Lo grabado ahora mismo, listo para guardar como `.xfsession`.
    public var snapshot: (motion: [MotionSample], fader: [FaderSample]) {
        (motion, fader)
    }

    /// Segundos que abarca lo grabado (0 si hay menos de dos muestras).
    public var durationSeconds: Double {
        let times = (motion.map(\.hostTime) + fader.map(\.hostTime))
        guard let lo = times.min(), let hi = times.max(), hi > lo else { return 0 }
        return host.nanoseconds(fromHostTicks: hi - lo) / 1_000_000_000
    }

    // MARK: -

    private func trim(now: UInt64) {
        let cutoffNs = windowSeconds * 1_000_000_000
        let cutoffTicks = host.hostTicks(fromNanoseconds: cutoffNs)
        guard now > cutoffTicks else { return }        // aún no llena la ventana
        let oldest = now - cutoffTicks
        motion.removeAll { $0.hostTime < oldest }
        fader.removeAll { $0.hostTime < oldest }
    }
}
