// SPDX-License-Identifier: GPL-3.0-only

/// Regla para traducir entre el reloj del sistema (`hostTime`, de las muestras
/// de motion y de los eventos de fader) y el tiempo musical (ticks).
///
/// Es un **ancla + tempo**: se dice que un `hostTime` concreto corresponde a un
/// `tick` concreto, y a partir de ahi todo es proporcional al tempo. Lo usa
/// `XFAnalysis` (via `Take.clock`, ver `docs/ARCHITECTURE.md` §3) para llevar una
/// captura grabada a la rejilla del patron objetivo.
///
/// El par ida y vuelta `tick(fromHostTime:)` ∘ `hostTime(fromTick:)` devuelve el
/// mismo tick exacto para todo el rango de trabajo: un tick musical dura muchos
/// host ticks, asi que el redondeo intermedio nunca llega a medio tick musical
/// (verificado con 10.000 valores y varias timebases en los tests).
public struct ClockMap: Equatable, Sendable {

    /// Un instante del reloj del sistema...
    public let anchorHostTime: UInt64
    /// ...que se declara equivalente a este tick musical.
    public let anchorTick: Tick
    /// Tempo con el que avanza el tiempo musical respecto al real.
    public let tempo: Tempo
    /// Timebase para convertir host ticks a nanosegundos.
    public let host: HostClock

    public init(anchorHostTime: UInt64, anchorTick: Tick, tempo: Tempo, host: HostClock = HostClock()) {
        self.anchorHostTime = anchorHostTime
        self.anchorTick = anchorTick
        self.tempo = tempo
        self.host = host
    }

    /// Atajo habitual: el ancla es "ahora" y el tick 0. Sirve para arrancar una
    /// toma en vivo, donde el instante de `start` es el origen musical.
    public static func startingNow(tempo: Tempo, host: HostClock = HostClock()) -> ClockMap {
        ClockMap(anchorHostTime: HostClock.now(), anchorTick: 0, tempo: tempo, host: host)
    }

    // MARK: - conversiones

    /// `hostTime` (real, de una AudioTimeStamp o MIDITimeStamp) -> tick musical.
    public func tick(fromHostTime hostTime: UInt64) -> Tick {
        // delta en host ticks, con signo. Un mach time real cabe de sobra en Int64.
        let deltaHost = Int64(hostTime) - Int64(anchorHostTime)
        let magNs = host.nanoseconds(fromHostTicks: UInt64(deltaHost.magnitude))
        let deltaTicks = tempo.ticks(fromMilliseconds: magNs / 1_000_000.0)
        return deltaHost >= 0 ? anchorTick + deltaTicks : anchorTick - deltaTicks
    }

    /// Tick musical -> `hostTime`. El inverso de `tick(fromHostTime:)`.
    public func hostTime(fromTick tick: Tick) -> UInt64 {
        let deltaTicks = tick - anchorTick                       // con signo
        let deltaNs = tempo.milliseconds(fromTicks: deltaTicks) * 1_000_000.0
        let deltaHost = host.hostTicks(fromNanoseconds: abs(deltaNs))
        if deltaNs >= 0 {
            return anchorHostTime &+ deltaHost
        }
        // hacia atras del ancla: no bajamos de 0 (no hay hostTime negativo)
        return deltaHost >= anchorHostTime ? 0 : anchorHostTime - deltaHost
    }
}
