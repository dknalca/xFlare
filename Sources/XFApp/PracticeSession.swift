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

    /// Fase de "llamada y respuesta": la máquina toca el fantasma sobre el
    /// sample unos compases (`listen`) y luego te toca imitarlo de oído
    /// (`respond`). `off` = práctica libre normal.
    public enum CallResponsePhase: Equatable { case off, listen, respond }

    // --- el patron, para que el fantasma pueda mover el sample en `listen` ---
    private let scratch: Scratch
    private let lengthTicks: Double

    // --- constantes del patron ---
    private let ppq: Double
    /// Extremos del recorrido del PLATO. `posLo` = posicion 0 del sample (el
    /// pico bajo del patron); `posHi` = final del sample. El pico ALTO del
    /// patron cae en `posLo + patternSpan` (< `posHi`): el plato puede seguir
    /// scratcheando mas alla.
    private let posLo: Double
    private let posHi: Double
    /// Span propio del patron (pico bajo -> pico alto), en unidades de posicion.
    private let patternSpan: Double
    /// Cuanta historia de traza guardamos, en ticks (~8 negras).
    private let historyTicks: Double

    // --- estado observable (barra superior) ---
    @Published public private(set) var bpm: Int
    @Published public private(set) var faderClosed = false
    /// Congelado (tecla P): el reloj y la autopista se paran en el instante
    /// actual y la traza deja de crecer, pero el plato sigue vivo -> puedes
    /// scratchear el sample sobre la imagen congelada. La instrumental la para
    /// la vista (transporte del motor).
    @Published public private(set) var frozen = false

    // --- llamada y respuesta ---
    @Published public private(set) var crPhase: CallResponsePhase = .off
    /// Cuántos compases dura cada fase (la máquina toca `crBars`, tú imitas
    /// `crBars`). Se elige desde la vista en múltiplos de 2.
    @Published public private(set) var crBars: Int = 2
    private var crPhaseLenTicks: Double = 0
    private var crPhaseStart: Double = 0

    // --- reloj musical, integrado a mano para tolerar cambios de BPM ---
    private(set) var currentTick: Double = 0

    // --- plato de juguete ---
    /// Posicion del disco, en las mismas unidades que la curva del patron.
    private(set) var platterPosition: Double
    /// Velocidad del disco, unidades de posicion por segundo.
    private(set) var platterVelocity: Double = 0

    /// Traza del usuario ya lista para `HighwayView` (ticks absolutos de sesion).
    private var traceBuffer: [TracePoint] = []

    /// Se llama al final de cada paso de simulacion con (velocidad normalizada
    /// -fraccion del rango del patron por segundo-, posicion normalizada 0…1,
    /// tick). La practica lo usa para empujar el motor de audio con la onda de
    /// abajo pegada a la autopista (mismo origen, no dos integradores). Opcional.
    public var onAdvance: ((_ normalizedVelocity: Double,
                            _ normalizedPosition: Double,
                            _ tick: Double) -> Void)?

    /// Posicion del plato como fraccion 0…1 del **sample entero**: 0 al empezar
    /// (posicion 0 del sample), `patternTopFraction` (2/3) cuando el patron esta
    /// en su pico, 1 en el final del sample. Se puede llegar a 1.
    public var normalizedPosition: Double {
        let rel = (platterPosition - posLo) / patternSpan   // 1.0 en el pico del patron
        return min(1, max(0, rel * AudioAsset.scratchPatternTopFraction))
    }

    /// Derivada exacta de `normalizedPosition`: para que el cabezal del audio y
    /// la traza de la autopista no se separen.
    public var normalizedVelocity: Double {
        platterVelocity / patternSpan * AudioAsset.scratchPatternTopFraction
    }

    // --- bucle ---
    private var timer: Timer?
    private var lastFrameTime: CFTimeInterval = 0

    // --- sintonia (a ojo; se afina cuando haya mesa) ---
    /// Decaimiento exponencial de la velocidad al soltar, en 1/s. Mas bajo =
    /// rueda mas y cuesta menos llegar a los extremos del recorrido.
    private let frictionPerSecond = 2.5
    /// Ganancia del scroll del trackpad: puntos de scroll -> unidades/s. El
    /// recorrido del plato es ~1,5x el span del patron; un gesto normal tiene
    /// que poder cubrirlo entero (hasta el final del sample) en las dos direcciones.
    private let scrollGain = 0.26
    /// Impulso de una pulsacion de A / D, en unidades/s.
    private let keyImpulse = 1.6

    /// Sensibilidad del trackpad, PROVISIONAL para las pruebas sin mesa. Escala
    /// el scroll antes de convertirlo en velocidad del plato (1.0 = base). Un
    /// slider de la vista lo mueve en caliente porque a ojo el gesto va rapido.
    public var scrollSensitivity: Double = 1.0

    public init(scratch: Scratch, bpm: Int) {
        self.scratch = scratch
        self.lengthTicks = Double(max(1, scratch.lengthTicks))
        self.ppq = Double(max(1, scratch.ppq))
        self.historyTicks = self.ppq * 8

        // llamada y respuesta: 2 compases por defecto (ajustable desde la vista).
        self.crBars = 2
        self.crPhaseLenTicks = 2.0 * 4.0 * self.ppq

        // El patron (fantasma) va de `range.lowerBound` a `range.upperBound` y su
        // curva llena la autopista entera (patternFill 1.0). El PLATO puede ir
        // mas alla del pico, hasta el final del sample: `posHi` esta por encima
        // de `range.upperBound` y esa traza extra se sale por el borde superior.
        let range = HighwayLayout(scratch: scratch).positionRange
        self.patternSpan = max(1e-6, range.upperBound - range.lowerBound)
        self.posLo = range.lowerBound
        //   rel(posHi) = 1 / (2/3) = 1.5  ->  normalizedPosition(posHi) = 1.0 (final del sample)
        self.posHi = range.lowerBound + patternSpan / AudioAsset.scratchPatternTopFraction
        // Arranca en `posLo` = posicion 0 del sample.
        self.platterPosition = range.lowerBound
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

        // CONGELADO (tecla P): el reloj no avanza y la traza no crece, pero el
        // plato sigue con su fisica y se sigue empujando el motor de audio ->
        // puedes scratchear el sample sobre la imagen quieta, sin dibujar.
        if frozen {
            platterVelocity *= exp(-frictionPerSecond * step)
            if abs(platterVelocity) < 1e-4 { platterVelocity = 0 }
            platterPosition += platterVelocity * step
            if platterPosition < posLo { platterPosition = posLo; platterVelocity = 0 }
            if platterPosition > posHi { platterPosition = posHi; platterVelocity = 0 }
            onAdvance?(normalizedVelocity, normalizedPosition, currentTick)
            return
        }

        // reloj musical
        currentTick += step * (Double(bpm) / 60.0) * ppq

        // llamada y respuesta: alterna escucha <-> tu turno cada `crBars` compases
        if crPhase != .off, currentTick - crPhaseStart >= crPhaseLenTicks {
            crPhase = (crPhase == .listen) ? .respond : .listen
            crPhaseStart = currentTick
            if crPhase == .respond { platterVelocity = 0 }   // empiezas con el plato quieto
        }

        if crPhase == .listen {
            // la MAQUINA toca: el fantasma mueve el plato (y con el, el sample).
            // La posicion viene de la curva del patron; la velocidad, de su
            // derivada; el fader, del estado del patron en ese tick.
            let g = ghostPosition(atTick: currentTick)
            platterVelocity = (g - platterPosition) / step
            platterPosition = g
            setFaderClosed(!ghostFaderOpen(atTick: currentTick))
        } else {
            // tu turno (o practica libre): el plato lo mueves tu
            platterVelocity *= exp(-frictionPerSecond * step)
            if abs(platterVelocity) < 1e-4 { platterVelocity = 0 }
            platterPosition += platterVelocity * step
            if platterPosition < posLo { platterPosition = posLo; platterVelocity = 0 }
            if platterPosition > posHi { platterPosition = posHi; platterVelocity = 0 }
        }

        // traza: un punto por fotograma. Con el fader cerrado no suena, asi que
        // ese tramo de la linea se pinta apagado (nivel `.miss`), no la pantalla.
        // La traza se pinta en unidades de posicion del patron. Si el plato se
        // pasa del pico del patron, `platterPosition` > `posLo + patternSpan` y
        // la autopista lo extrapola hacia el hueco de arriba (ADR-041,
        // `geometry.patternFill`), hacia el final del sample.
        let level: HitLevel? = faderClosed ? .miss : nil
        traceBuffer.append(TracePoint(tick: currentTick, position: platterPosition, level: level))
        let cutoff = currentTick - historyTicks
        if traceBuffer.first?.tick ?? 0 < cutoff {
            traceBuffer.removeAll { $0.tick < cutoff }
        }

        onAdvance?(normalizedVelocity, normalizedPosition, currentTick)
    }

    // MARK: - lo que lee la autopista (cada fotograma, hilo principal)

    private var cachedTick: Double = 0
    private var cachedTickAt: CFTimeInterval = -1

    /// Tick "de ahora mismo". Entre dos pasos del timer (que llega con jitter)
    /// se **extrapola** con el reloj de pared: `currentTick + (tiempo desde el
    /// ultimo paso) * ritmo`. Ademas se **cachea ~4 ms**: la autopista y las dos
    /// tiras llaman aqui dentro del mismo frame (con microsegundos de diferencia)
    /// y asi obtienen EXACTAMENTE el mismo valor -> la rejilla cae en la misma X
    /// en las tres. Sin timer (tests) se devuelve el crudo.
    public func tick() -> Double {
        guard timer != nil else { return currentTick }
        if frozen { return currentTick }     // imagen congelada: no se extrapola
        let now = CACurrentMediaTime()
        if now - cachedTickAt >= 0, now - cachedTickAt < 0.004 { return cachedTick }
        let rate = (Double(bpm) / 60.0) * ppq
        let extra = (now - lastFrameTime) * rate
        let v = currentTick + min(max(0, extra), 0.05 * rate)
        cachedTick = v
        cachedTickAt = now
        return v
    }
    public func trace() -> [TracePoint] { traceBuffer }

    // MARK: - llamada y respuesta

    /// Enciende/apaga el modo. Al encender arranca en `listen` (te toca escuchar).
    public func setCallResponse(_ on: Bool) {
        if on {
            guard crPhase == .off else { return }
            crPhase = .listen
            crPhaseStart = currentTick
        } else {
            crPhase = .off
            platterVelocity = 0
        }
    }

    /// Nº de compases de cada fase, forzado a par y a [2, 16]. La fase en curso
    /// no se corta: el cambio entra en la siguiente.
    public func setCallResponseBars(_ n: Int) {
        let even = max(2, min(16, (n / 2) * 2))
        guard even != crBars else { return }
        crBars = even
        crPhaseLenTicks = Double(crBars) * 4.0 * ppq
    }

    /// Posición del fantasma en `tick`, envuelta al patrón (para `listen`).
    private func ghostPosition(atTick t: Double) -> Double {
        PositionSampler.position(of: scratch, atTick: wrappedTick(t))
    }
    private func ghostFaderOpen(atTick t: Double) -> Bool {
        PositionSampler.faderState(of: scratch, atTick: wrappedTick(t)) == .open
    }
    private func wrappedTick(_ t: Double) -> Int {
        let m = t.truncatingRemainder(dividingBy: lengthTicks)
        return Int(m < 0 ? m + lengthTicks : m)
    }

    // MARK: - entrada

    /// Scroll horizontal del trackpad. `deltaX` en puntos (signo: + = adelante).
    /// En `listen` se ignora: manda la máquina.
    public func scrollBy(_ deltaX: Double) {
        guard crPhase != .listen else { return }
        platterVelocity += deltaX * scrollGain * scrollSensitivity
    }

    /// Pulsacion de tecla de plato. `forward` = hacia adelante (D); si no, atras (A).
    public func nudge(forward: Bool) {
        guard crPhase != .listen else { return }
        platterVelocity += (forward ? 1.0 : -1.0) * keyImpulse
    }

    public func setFaderClosed(_ closed: Bool) {
        if faderClosed != closed { faderClosed = closed }
    }

    /// Tecla P: congela / descongela. Al congelar corta el impulso del reloj
    /// (`lastFrameTime` se refresca al descongelar para no pegar un salto).
    public func toggleFreeze() {
        frozen.toggle()
        if !frozen { lastFrameTime = CACurrentMediaTime() }
    }

    public func setBPM(_ value: Int) {
        let clamped = min(220, max(40, value))
        if clamped != bpm { bpm = clamped }
    }

    /// Pone el reloj a 0 y limpia el estado. Se llama cuando el audio arranca de
    /// verdad (tras decodificar), para que `currentTick == 0` coincida con el
    /// primer golpe de la instrumental y la rejilla caiga sobre los golpes.
    public func resyncClock() {
        currentTick = 0
        crPhaseStart = 0
        traceBuffer.removeAll()
        platterVelocity = 0
        platterPosition = posLo
        if crPhase != .off { crPhase = .listen }
    }
}
