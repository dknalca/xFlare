// SPDX-License-Identifier: GPL-3.0-only

/// Un tempo: cuantos negras por minuto. Convierte entre tiempo musical (ticks)
/// y tiempo real (milisegundos / segundos).
///
/// ADR-016: el patron se guarda en ticks y el BPM es un parametro de
/// reproduccion. Toda la conversion a tiempo real pasa por aqui, en un unico
/// sitio, para que no haya dos formulas distintas repartidas por el codigo.
public struct Tempo: Equatable, Sendable {

    /// Negras por minuto. Siempre > 0.
    public let bpm: Double

    public init(bpm: Double) {
        precondition(bpm > 0 && bpm.isFinite, "bpm debe ser un numero positivo")
        self.bpm = bpm
    }

    /// Milisegundos que dura un tick a este tempo.
    /// `60_000 ms/min / (bpm negras/min * PPQ ticks/negra)`.
    public var millisecondsPerTick: Double {
        60_000.0 / (bpm * Double(XFClock.ppq))
    }

    /// Ticks que caben en un segundo a este tempo (util para el driver de audio,
    /// que razona en muestras y segundos).
    public var ticksPerSecond: Double {
        1_000.0 / millisecondsPerTick
    }

    // MARK: - ticks -> tiempo real

    public func milliseconds(fromTicks ticks: Tick) -> Double {
        Double(ticks) * millisecondsPerTick
    }

    public func seconds(fromTicks ticks: Tick) -> Double {
        milliseconds(fromTicks: ticks) / 1_000.0
    }

    // MARK: - tiempo real -> ticks

    /// Redondea al tick mas cercano. El par
    /// `ticks(fromMilliseconds: milliseconds(fromTicks: t))` devuelve `t` exacto
    /// para todo el rango de trabajo (verificado con 10.000 valores en los tests).
    public func ticks(fromMilliseconds ms: Double) -> Tick {
        Tick((ms / millisecondsPerTick).rounded())
    }

    public func ticks(fromSeconds s: Double) -> Tick {
        ticks(fromMilliseconds: s * 1_000.0)
    }
}
