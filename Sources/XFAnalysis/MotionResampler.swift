// SPDX-License-Identifier: GPL-3.0-only

import XFClock
import XFPrimitives

/// Utilidades para leer la toma del usuario en instantes concretos del patron.
/// Las muestras llegan a su propio ritmo; aqui se interpolan a la rejilla que
/// necesita el scoring.
enum MotionResampler {

    /// Posicion del disco del usuario en el `hostTime` dado, interpolando
    /// linealmente entre las dos muestras que lo rodean. Devuelve `nil` si no hay
    /// muestras.
    static func position(_ motion: [MotionSample], atHostTime host: UInt64) -> Double? {
        guard !motion.isEmpty else { return nil }
        if host <= motion.first!.hostTime { return motion.first!.position }
        if host >= motion.last!.hostTime { return motion.last!.position }
        // busqueda binaria del primer sample con hostTime >= host
        var lo = 0, hi = motion.count - 1
        while lo < hi {
            let mid = (lo + hi) / 2
            if motion[mid].hostTime < host { lo = mid + 1 } else { hi = mid }
        }
        let b = motion[lo]
        let a = motion[lo - 1]
        let span = Double(b.hostTime - a.hostTime)
        let f = span > 0 ? Double(host - a.hostTime) / span : 0
        return a.position + (b.position - a.position) * f
    }

    /// Velocidad del usuario en el `hostTime` dado (la de la muestra mas cercana).
    /// Fuera del rango de la toma devuelve la del extremo: si el patron dura mas
    /// que lo grabado, los checkpoints que caen despues del final leen la ultima
    /// muestra en vez de reventar (resta de `UInt64` con underflow).
    static func velocity(_ motion: [MotionSample], atHostTime host: UInt64) -> Double? {
        guard !motion.isEmpty else { return nil }
        if host <= motion.first!.hostTime { return motion.first!.velocity }
        if host >= motion.last!.hostTime { return motion.last!.velocity }
        // busqueda binaria del primer sample con hostTime >= host
        var lo = 0, hi = motion.count - 1
        while lo < hi {
            let mid = (lo + hi) / 2
            if motion[mid].hostTime < host { lo = mid + 1 } else { hi = mid }
        }
        // con los guardas de arriba: 1 <= lo <= count-1, motion[lo-1] < host <= motion[lo]
        let a = motion[lo - 1], b = motion[lo]
        return (host - a.hostTime) < (b.hostTime - host) ? a.velocity : b.velocity
    }
}
