// SPDX-License-Identifier: GPL-3.0-only

#if canImport(Darwin)
import Darwin
#endif

/// El reloj del sistema: `mach_absolute_time()`. Es el **mismo dominio** que usan
/// `AudioTimeStamp` (CoreAudio) y `MIDITimeStamp` (CoreMIDI) en macOS, asi que un
/// `hostTime` de una muestra de motion y otro de un evento de fader son
/// directamente comparables (ADR-001).
///
/// `mach_absolute_time()` cuenta en unidades opacas ("host ticks"), no en
/// nanosegundos. La conversion es `ns = hostTicks * numer / denom`, donde
/// `numer/denom` los da `mach_timebase_info`. En Intel suele ser 1/1 (host tick =
/// 1 ns); en Apple Silicon no. Por eso nunca se asume la equivalencia.
public struct HostClock: Equatable, Sendable {

    /// Numerador de la escala host-tick -> nanosegundo.
    public let numer: UInt64
    /// Denominador de la escala host-tick -> nanosegundo.
    public let denom: UInt64

    /// Construye a partir del `mach_timebase_info` real de esta maquina.
    public init() {
        #if canImport(Darwin)
        var info = mach_timebase_info_data_t()
        mach_timebase_info(&info)
        self.numer = UInt64(info.numer)
        self.denom = UInt64(info.denom)
        #else
        // Fuera de Darwin (no deberia pasar en produccion) asumimos 1 ns/tick.
        self.numer = 1
        self.denom = 1
        #endif
    }

    /// Constructor explicito para los tests: permite fijar una timebase
    /// determinista (p. ej. la 125/3 tipica de Apple Silicon) sin depender de la
    /// maquina donde corren.
    public init(numer: UInt64, denom: UInt64) {
        precondition(numer > 0 && denom > 0, "la timebase debe ser positiva")
        self.numer = numer
        self.denom = denom
    }

    /// Instante actual en host ticks. Es la unica funcion con efecto de "leer el
    /// mundo"; todo lo demas es aritmetica pura.
    public static func now() -> UInt64 {
        #if canImport(Darwin)
        return mach_absolute_time()
        #else
        return 0
        #endif
    }

    // MARK: - conversiones (puras)

    public func nanoseconds(fromHostTicks hostTicks: UInt64) -> Double {
        Double(hostTicks) * Double(numer) / Double(denom)
    }

    public func hostTicks(fromNanoseconds ns: Double) -> UInt64 {
        let ticks = (ns * Double(denom) / Double(numer)).rounded()
        return ticks <= 0 ? 0 : UInt64(ticks)
    }
}
