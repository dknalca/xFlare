// SPDX-License-Identifier: GPL-3.0-only

/// El transporte: play / stop / loop / cuenta atras de N compases.
///
/// Es un **valor** (`struct`), no un objeto con hilo propio. No mira ningun
/// reloj por su cuenta: el driver de audio calcula cuantos ticks han pasado
/// segun el reloj de AUDIO y llama a `advance(by:)`. Asi el transporte es
/// determinista y testeable sin tiempo real (los tests de B2.2), y la autopista
/// nunca deriva respecto al sonido (ver `docs/PLAN.md` §8).
public struct Transport: Equatable, Sendable {

    /// En que fase esta el transporte.
    public enum State: Equatable, Sendable {
        /// Parado. `position` vuelve a 0.
        case stopped
        /// Cuenta atras en curso: `position` es negativa y sube hacia 0.
        case countIn
        /// Sonando: `position` >= 0 y avanza.
        case playing
    }

    /// Un tramo que se repite. `start`..<`end` en ticks musicales.
    public struct Loop: Equatable, Sendable {
        public let start: Tick
        public let end: Tick

        public init(start: Tick, end: Tick) {
            precondition(end > start, "el loop necesita end > start")
            self.start = start
            self.end = end
        }

        /// Longitud del tramo en ticks.
        public var length: Tick { end - start }
    }

    /// Fase actual.
    public private(set) var state: State

    /// Posicion en tiempo musical. Negativa durante la cuenta atras, >= 0 al sonar.
    public private(set) var position: Tick

    /// Compas de referencia para la cuenta atras y para `bar`.
    public var timeSignature: TimeSignature

    /// Tramo de repeticion, o `nil` si no hay loop.
    public var loop: Loop?

    public init(timeSignature: TimeSignature = .fourFour) {
        self.state = .stopped
        self.position = 0
        self.timeSignature = timeSignature
        self.loop = nil
    }

    // MARK: - control

    /// Para y rebobina a 0.
    public mutating func stop() {
        state = .stopped
        position = 0
    }

    /// Arranca. Con `countInBars > 0` entra en cuenta atras: `position` parte en
    /// `-(countInBars * ticksPerBar)` y `advance(by:)` la lleva hasta 0, momento
    /// en que pasa sola a `.playing`.
    public mutating func play(countInBars: Int = 0) {
        precondition(countInBars >= 0, "countInBars no puede ser negativo")
        if countInBars == 0 {
            state = .playing
            position = 0
            applyLoopIfNeeded()
        } else {
            state = .countIn
            position = -(countInBars * timeSignature.ticksPerBar)
        }
    }

    /// Avanza `delta` ticks (>= 0). Lo llama el driver cada bloque de audio con
    /// los ticks transcurridos segun el reloj de audio.
    public mutating func advance(by delta: Tick) {
        precondition(delta >= 0, "el transporte solo avanza hacia delante")
        switch state {
        case .stopped:
            return
        case .countIn:
            position += delta
            if position >= 0 {
                state = .playing
                applyLoopIfNeeded()
            }
        case .playing:
            position += delta
            applyLoopIfNeeded()
        }
    }

    // MARK: - consultas

    public var isPlaying: Bool { state == .playing }

    /// Compases que faltan para que acabe la cuenta atras. 0 si ya suena o esta
    /// parado.
    public var countInBarsRemaining: Int {
        guard state == .countIn else { return 0 }
        let barTicks = timeSignature.ticksPerBar
        // `position` es < 0 aqui; ceil(-position / barTicks)
        return Int((-position + barTicks - 1) / barTicks)
    }

    /// Compas actual, 1-based, mientras suena. 0 en cuenta atras o parado.
    public var bar: Int {
        guard state == .playing, position >= 0 else { return 0 }
        return position / timeSignature.ticksPerBar + 1
    }

    // MARK: - interno

    /// Si hay loop y nos hemos pasado del final, envuelve la posicion. Un solo
    /// `%` cubre cualquier numero de vueltas en un mismo `advance`.
    private mutating func applyLoopIfNeeded() {
        guard let loop = loop, position >= loop.end else { return }
        let over = position - loop.start
        position = loop.start + (over % loop.length)
    }
}
