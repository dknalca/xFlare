// SPDX-License-Identifier: GPL-3.0-only

import Foundation
import Combine
import QuartzCore
import XFNotation
import XFRender
import XFDesign

/// El motor de la practica **rudimentaria**: un reloj musical propio (sin audio)
/// que hace correr la autopista, y un modelo de plato de juguete que el trackpad
/// y el teclado empujan. Acumula la traza del usuario para pintarla sobre la
/// autopista.
///
/// No es la sesion de verdad (series, cuenta atras, scoring): eso vive en
/// `XFEngine` + `XFAnalysis` y necesita el callback de audio corriendo (B4.2).
/// Esto es solo para ver el movimiento y probar la entrada antes de tener la mesa.
///
/// `ObservableObject` para que la vista lo retenga (`@StateObject`) y refresque
/// la barra superior; el redibujo de la autopista NO pasa por aqui: la escena de
/// SpriteKit lee `tick()` / `trace()` en cada fotograma.
public final class PracticeSession: ObservableObject {

    // --- constantes del patron ---
    private let ppq: Double
    /// Rango de posicion util (el del patron, ensanchado un 25 % a cada lado)
    /// para que la linea del usuario no se salga de la autopista.
    private let posLo: Double
    private let posHi: Double
    /// Cuanta historia de traza guardamos, en ticks (~8 negras).
    private let historyTicks: Double

    // --- estado observable (barra superior) ---
    @Published public private(set) var bpm: Int
    @Published public private(set) var faderClosed = false

    // --- reloj musical, integrado a mano para tolerar cambios de BPM ---
    private(set) var currentTick: Double = 0

    // --- plato de juguete ---
    /// Posicion del disco, en las mismas unidades que la curva del patron.
    private(set) var platterPosition: Double
    /// Velocidad del disco, unidades de posicion por segundo.
    private(set) var platterVelocity: Double = 0

    /// Traza del usuario ya lista para `HighwayView` (ticks absolutos de sesion).
    private var traceBuffer: [TracePoint] = []

    /// Se llama al final de cada paso de simulacion con (velocidad del plato,
    /// tick). La practica lo usa para empujar el motor de audio. Opcional.
    public var onAdvance: ((_ platterVelocity: Double, _ tick: Double) -> Void)?

    // --- bucle ---
    private var timer: Timer?
    private var lastFrameTime: CFTimeInterval = 0

    // --- sintonia (a ojo; se afina cuando haya mesa) ---
    /// Decaimiento exponencial de la velocidad al soltar, en 1/s. ~0,3 s de coast.
    private let frictionPerSecond = 7.0
    /// Ganancia del scroll del trackpad: puntos de scroll -> unidades/s.
    private let scrollGain = 0.055
    /// Impulso de una pulsacion de A / D, en unidades/s.
    private let keyImpulse = 0.6

    public init(scratch: Scratch, bpm: Int) {
        self.ppq = Double(max(1, scratch.ppq))
        self.historyTicks = self.ppq * 8

        let range = HighwayLayout(scratch: scratch).positionRange
        let span = max(0.2, range.upperBound - range.lowerBound)
        self.posLo = range.lowerBound - span * 0.25
        self.posHi = range.upperBound + span * 0.25
        self.platterPosition = (range.lowerBound + range.upperBound) / 2
        self.bpm = min(220, max(40, bpm))
    }

    // MARK: - ciclo de vida

    /// Arranca el bucle a 60 Hz. En modo `.common` para que siga latiendo
    /// mientras el trackpad esta en tracking (si no, se congela al hacer scroll).
    public func start() {
        guard timer == nil else { return }
        lastFrameTime = CACurrentMediaTime()
        let t = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            let now = CACurrentMediaTime()
            let dt = now - self.lastFrameTime
            self.lastFrameTime = now
            self.advance(by: dt)
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    public func stop() {
        timer?.invalidate()
        timer = nil
    }

    deinit { timer?.invalidate() }

    // MARK: - avance del mundo

    /// Un paso de simulacion de `dt` segundos. Lo llama el timer; los tests lo
    /// llaman directamente con un `dt` fijo.
    func advance(by dt: Double) {
        let step = min(0.05, max(0, dt))   // acota saltos si el hilo se atasca
        guard step > 0 else { return }

        // reloj musical
        currentTick += step * (Double(bpm) / 60.0) * ppq

        // plato: la velocidad decae y arrastra la posicion
        platterVelocity *= exp(-frictionPerSecond * step)
        if abs(platterVelocity) < 1e-4 { platterVelocity = 0 }
        platterPosition += platterVelocity * step
        if platterPosition < posLo { platterPosition = posLo; platterVelocity = 0 }
        if platterPosition > posHi { platterPosition = posHi; platterVelocity = 0 }

        // traza: un punto por fotograma. Con el fader cerrado no suena, asi que
        // ese tramo de la linea se pinta apagado (nivel `.miss`), no la pantalla.
        let level: HitLevel? = faderClosed ? .miss : nil
        traceBuffer.append(TracePoint(tick: currentTick, position: platterPosition, level: level))
        let cutoff = currentTick - historyTicks
        if traceBuffer.first?.tick ?? 0 < cutoff {
            traceBuffer.removeAll { $0.tick < cutoff }
        }

        onAdvance?(platterVelocity, currentTick)
    }

    /// Velocidad del plato mapeada a la del reproductor de scratch (1.0 = pitch
    /// normal). Rudimentaria y acotada; se afina a oido con la mesa.
    public var scratchPlaybackVelocity: Double {
        let scaled = platterVelocity * 1.6
        return max(-8.0, min(8.0, scaled))
    }

    // MARK: - lo que lee la autopista (cada fotograma, hilo principal)

    public func tick() -> Double { currentTick }
    public func trace() -> [TracePoint] { traceBuffer }

    // MARK: - entrada

    /// Scroll horizontal del trackpad. `deltaX` en puntos (signo: + = adelante).
    public func scrollBy(_ deltaX: Double) {
        platterVelocity += deltaX * scrollGain
    }

    /// Pulsacion de tecla de plato. `forward` = hacia adelante (D); si no, atras (A).
    public func nudge(forward: Bool) {
        platterVelocity += (forward ? 1.0 : -1.0) * keyImpulse
    }

    public func setFaderClosed(_ closed: Bool) {
        if faderClosed != closed { faderClosed = closed }
    }

    public func setBPM(_ value: Int) {
        let clamped = min(220, max(40, value))
        if clamped != bpm { bpm = clamped }
    }
}
