// SPDX-License-Identifier: GPL-3.0-only

import XFClock
import XFPrimitives

/// Modo sin mesa: el disco se mueve con las flechas del teclado (`profiles/
/// keyboard.conf`). Existe para desarrollar y practicar la lectura sin platos
/// (CLAUDE.md §3, §5). El ciudadano de primera es el timecode; esto es la muleta.
///
/// Física sencilla: con una flecha pulsada la velocidad tiende a `±speed`; al
/// soltar, tiende a 0. La posición integra la velocidad. Todo en **unidades
/// nominales** (velocidad 1.0 = reproducción normal); la escala absoluta no
/// importa en modo teclado porque el análisis normaliza la amplitud (ADR-005).
///
/// No mira el reloj por su cuenta: el driver la hace avanzar con
/// `advance(toHostTime:)` usando el reloj de AUDIO, como el transporte y el
/// replay. Así es determinista y testeable sin tiempo real.
public final class KeyboardMotionSource: MotionSource {

    public struct Config: Sendable {
        /// Velocidad (nominal) que alcanza el disco con la flecha pulsada.
        public var speed: Double
        /// Aceleración (nominal/segundo) hacia la velocidad objetivo.
        public var accel: Double
        public init(speed: Double = 1.6, accel: Double = 14.0) {
            self.speed = speed
            self.accel = accel
        }
    }

    private let config: Config
    private let host: HostClock

    private var running = false
    private var forwardHeld = false
    private var backHeld = false
    private var position = 0.0
    private var velocity = 0.0
    private var lastHost: UInt64 = 0
    private var current: MotionSample?

    public init(config: Config = .init(), host: HostClock = HostClock()) {
        self.config = config
        self.host = host
    }

    public var isConnected: Bool { running }

    public func start() throws {
        running = true
        forwardHeld = false
        backHeld = false
        position = 0
        velocity = 0
        lastHost = HostClock.now()
        current = MotionSample(hostTime: lastHost, position: 0, velocity: 0, confidence: 1)
    }

    public func stop() {
        running = false
    }

    public func latest() -> MotionSample? { current }

    // MARK: - teclado

    public func press(_ key: Key)   { setHeld(key, true) }
    public func release(_ key: Key) { setHeld(key, false) }

    public enum Key: Sendable { case forward, back }

    private func setHeld(_ key: Key, _ held: Bool) {
        switch key {
        case .forward: forwardHeld = held
        case .back:    backHeld = held
        }
    }

    // MARK: - integración

    /// Integra la física hasta `hostTime`. Lo llama el driver cada bloque de audio.
    public func advance(toHostTime hostTime: UInt64) {
        guard running, hostTime > lastHost else { return }
        let dt = host.nanoseconds(fromHostTicks: hostTime - lastHost) / 1_000_000_000.0
        lastHost = hostTime

        // velocidad objetivo: +speed / −speed / 0 (si ambas o ninguna).
        let target: Double
        if forwardHeld == backHeld {
            target = 0
        } else {
            target = forwardHeld ? config.speed : -config.speed
        }

        // acercar `velocity` a `target` sin pasarse.
        let maxStep = config.accel * dt
        let diff = target - velocity
        velocity += abs(diff) <= maxStep ? diff : (diff > 0 ? maxStep : -maxStep)

        position += velocity * dt
        current = MotionSample(hostTime: hostTime, position: position,
                               velocity: velocity, confidence: 1)
    }
}
