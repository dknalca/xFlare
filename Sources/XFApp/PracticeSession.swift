// SPDX-License-Identifier: GPL-3.0-only

import Foundation
import Combine
import QuartzCore
import XFNotation
import XFRender
import XFDesign
import XFCapture
import XFPrimitives
import XFClock

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

    // --- el patron, para que el fantasma pueda mover el sample en `listen`.
    // `var` (no `let`): el calentamiento en una sola sesión cambia de patrón sin
    // recrear la sesión (`reload(scratch:)`).
    private var scratch: Scratch
    private var lengthTicks: Double

    // --- constantes del patron ---
    private var ppq: Double
    /// Extremos del recorrido del PLATO. `posLo` = posicion 0 del sample (el
    /// pico bajo del patron); `posHi` = final del sample. El PLATO recorre
    /// SIEMPRE todo el rango, de abajo a arriba: el slider de amplitud solo
    /// afecta a la ONDA FANTASMA que se dibuja (en `PracticeScene`), no a la
    /// libertad de movimiento ni al mapeo de audio.
    private var posLo: Double
    private var posHi: Double
    /// Span propio del patron (pico bajo -> pico alto), en unidades de posicion.
    private var patternSpan: Double
    /// Cuanta historia de traza guardamos, en ticks (~8 negras).
    private var historyTicks: Double

    // --- estado observable (barra superior) ---
    @Published public private(set) var bpm: Int
    @Published public private(set) var faderClosed = false
    /// Congelado (tecla P): el reloj y la autopista se paran en el instante
    /// actual y la traza deja de crecer, pero el plato sigue vivo -> puedes
    /// scratchear el sample sobre la imagen congelada. La instrumental la para
    /// la vista (transporte del motor).
    @Published public private(set) var frozen = false

    // --- grabacion de linea libre (.xfsession) ---
    /// `true` mientras se graba el movimiento del plato y el fader.
    @Published public private(set) var recording = false
    /// `true` mientras se reproduce una linea grabada (importada): el plato lo
    /// mueve el fichero, se ignora el input (como en "repite conmigo").
    @Published public private(set) var playingBack = false
    /// `true` durante la **claqueta**: 1 compás de metrónomo antes de que la
    /// grabación empiece de verdad, para poder entrar en el "1".
    @Published public private(set) var recArming = false
    /// Negras que quedan de claqueta (para el contador 3·2·1 de la vista). 0 si
    /// no hay claqueta en curso.
    @Published public private(set) var recCountBeats = 0
    /// Nombre de la instrumental de la última línea importada (de su cabecera).
    /// Vacío si la toma no lo trae o no se está reproduciendo nada.
    @Published public private(set) var playbackInstrName = ""
    private var recMotion: [MotionSample] = []
    private var recFader: [FaderSample] = []
    private var recStartHost: UInt64 = 0
    private var recLastClosed: Bool?
    /// Tick musical en el que arrancó la grabación (tras la claqueta). La toma se
    /// ancla aquí: cada gesto se reproduce en la misma fase del bucle.
    private var recAnchorTick: Double = 0
    /// Tick en el que la claqueta termina y empieza a grabar.
    private var recArmFireTick: Double = 0
    /// Longitud del bucle de la instrumental cargada, en ticks (la fija la vista).
    /// La toma se redondea a un múltiplo de esto para que encaje sin deriva.
    private var instrLoopTicksHint: Double = 0
    /// Nombre de la instrumental cargada (lo fija la vista); viaja en la cabecera
    /// de la toma para saber sobre qué base se grabó.
    private var instrNameHint = ""
    // Playback: `t` y `pbClock`/`pbLen` van en TICKS musicales (antes segundos),
    // así la línea corre al mismo reloj que la instrumental y no se desfasa.
    private var pbMotion: [(t: Double, pos: Double)] = []
    private var pbFader: [(t: Double, closed: Bool)] = []
    private var pbLen: Double = 0
    private var pbClock: Double = 0

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
    /// (posicion 0 del sample), `amplitude` cuando el patron esta en su pico, 1
    /// en el final del sample. Se puede llegar a 1.
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
    /// rueda mas y cuesta menos llegar a los extremos del recorrido. Bajado de
    /// 2.5 a 1.8 para poder llegar al final del sample (n=1.5) con un gesto.
    private let frictionPerSecond = 1.8
    /// Ganancia del scroll del trackpad: puntos de scroll -> unidades/s. El
    /// recorrido del plato es ~1,5x el span del patron; un gesto normal tiene
    /// que poder cubrirlo entero (hasta el final del sample) en las dos
    /// direcciones. Subido de 0.26 a 0.40.
    private let scrollGain = 0.40
    /// Impulso de una pulsacion de A / D, en unidades/s.
    private let keyImpulse = 2.2

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

        // El patron (fantasma) va de `range.lowerBound` a `range.upperBound`. El
        // PLATO tiene un techo GENEROSO (2,5x el span del patron): puede
        // scratchear bien mas alla del final del sample; `PracticeScene` mapea
        // el rango propio del patron (n=0..1) a toda la autopista y lo que se
        // pasa se sale por arriba ("infinito"). El audio satura en el final del
        // sample (`normalizedPosition` <= 1).
        let range = HighwayLayout(scratch: scratch).positionRange
        self.patternSpan = max(1e-6, range.upperBound - range.lowerBound)
        self.posLo = range.lowerBound
        self.posHi = range.lowerBound + patternSpan * 2.5
        // Arranca en `posLo` = posicion 0 del sample.
        self.platterPosition = range.lowerBound
        self.bpm = min(220, max(40, bpm))
    }

    /// Cambia el **patrón** en caliente (calentamiento en una sola sesión): sin
    /// recrear la sesión ni parar el reloj. Deja el plato al inicio y limpia la
    /// traza; el `currentTick` y el BPM no se tocan (la rejilla sigue).
    public func reload(scratch: Scratch) {
        self.scratch = scratch
        self.lengthTicks = Double(max(1, scratch.lengthTicks))
        self.ppq = Double(max(1, scratch.ppq))
        self.historyTicks = self.ppq * 8
        let range = HighwayLayout(scratch: scratch).positionRange
        self.patternSpan = max(1e-6, range.upperBound - range.lowerBound)
        self.posLo = range.lowerBound
        self.posHi = range.lowerBound + patternSpan * 2.5
        self.platterPosition = range.lowerBound
        self.platterVelocity = 0
        self.traceBuffer.removeAll(keepingCapacity: true)
        onAdvance?(0, 0, currentTick)
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
            recordFrame()
            onAdvance?(normalizedVelocity, normalizedPosition, currentTick)
            return
        }

        // reloj musical
        currentTick += step * (Double(bpm) / 60.0) * ppq

        // fin de la claqueta -> empieza a grabar en el downbeat
        if recArming {
            if currentTick >= recArmFireTick {
                recArming = false
                recCountBeats = 0
                beginRecordingNow()
            } else {
                // negras que faltan, para el contador 3·2·1 de la vista
                let left = Int(((recArmFireTick - currentTick) / ppq).rounded(.up))
                if left != recCountBeats { recCountBeats = max(0, left) }
            }
        }

        // llamada y respuesta: alterna escucha <-> tu turno cada `crBars` compases
        if crPhase != .off, currentTick - crPhaseStart >= crPhaseLenTicks {
            crPhase = (crPhase == .listen) ? .respond : .listen
            crPhaseStart = currentTick
            if crPhase == .respond {
                platterVelocity = 0        // empiezas con el plato quieto
                // ...y con el fader ABIERTO: durante la escucha el fantasma pudo
                // dejarlo cerrado (un chirp/transformer acaba en mute) y si no lo
                // reabrimos aqui tu turno arranca mudo hasta que tocas Espacio.
                setFaderClosed(false)
            }
        }

        if playingBack {
            // reproduccion de una linea grabada, ANCLADA a la instrumental: el
            // reloj de la linea avanza en TICKS al tempo actual, igual que la
            // base, asi los scratches caen siempre en el mismo punto del bucle.
            pbClock += step * (Double(bpm) / 60.0) * ppq
            if pbLen > 0, pbClock >= pbLen { pbClock = pbClock.truncatingRemainder(dividingBy: pbLen) }
            let g = pbPositionAt(pbClock)
            platterVelocity = (g - platterPosition) / step
            platterPosition = g
            setFaderClosed(pbClosedAt(pbClock))
        } else if crPhase == .listen {
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

        recordFrame()
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

    // MARK: - grabar / reproducir una linea libre (.xfsession)

    /// Un compás en ticks (4/4). Mismo criterio que `crPhaseLenTicks`.
    private var barTicks: Double { 4.0 * ppq }

    /// La vista informa de la longitud del bucle de la instrumental cargada, en
    /// ticks. La toma grabada se redondea a un múltiplo de esto (o de un compás
    /// si no se sabe) para que el bucle encaje con la base sin deriva.
    public func setInstrumentalLoopTicks(_ ticks: Double) {
        instrLoopTicksHint = max(0, ticks)
    }

    /// La vista informa del nombre de la instrumental cargada. Viaja en la
    /// cabecera de la toma (`instr=<slug>`, sin espacios).
    public func setInstrumentalName(_ name: String) {
        instrNameHint = Self.slug(name)
    }

    /// Nombre apto para la cabecera: sin espacios ni separadores del formato.
    /// `internal` para que la vista compare el nombre de la toma con el de la
    /// instrumental cargada con el mismo criterio.
    static func slug(_ s: String) -> String {
        String(s.map { ($0 == " " || $0 == ";" || $0 == "=") ? "_" : $0 })
    }

    /// Arranca una **claqueta** de ~1 compás y empieza a grabar en el downbeat
    /// siguiente. La vista enciende el metrónomo mientras `recArming`. Los tests
    /// y el arranque directo usan `startRecording()` (sin claqueta).
    public func armRecording() {
        guard !recording, !recArming else { return }
        stopPlayback()
        let bt = barTicks
        var fire = ((currentTick / bt).rounded(.down) + 1) * bt
        if fire - currentTick < bt * 0.5 { fire += bt }   // al menos medio compás
        recArmFireTick = fire
        recCountBeats = max(1, Int(((fire - currentTick) / ppq).rounded(.up)))
        recArming = true
    }

    /// Empieza a grabar YA, sin claqueta (borra lo anterior).
    public func startRecording() {
        stopPlayback()
        recArming = false
        recCountBeats = 0
        beginRecordingNow()
    }

    private func beginRecordingNow() {
        recMotion.removeAll(keepingCapacity: true)
        recFader.removeAll(keepingCapacity: true)
        recLastClosed = nil
        recStartHost = HostClock.now()
        recAnchorTick = currentTick
        recording = true
    }

    /// Para de grabar y devuelve lo grabado como `XFSession` (nil si es muy
    /// corto). La longitud del bucle (en ticks, redondeada a compases enteros /
    /// múltiplo del bucle de la instrumental) viaja en `notes` como `loop=<n>`.
    @discardableResult
    public func stopRecording() -> XFSession? {
        recording = false
        recArming = false
        recCountBeats = 0
        guard recMotion.count > 2,
              let a = recMotion.first?.hostTime,
              let b = recMotion.last?.hostTime, b > a else { return nil }
        let hc = HostClock()
        if recFader.isEmpty {
            recFader.append(FaderSample(hostTime: recStartHost, value: 1, isOpen: true))
        }
        // duración real de la toma -> ticks al tempo de grabación
        let spanSec = hc.nanoseconds(fromHostTicks: b - a) / 1_000_000_000
        let spanTicks = spanSec * (Double(bpm) / 60.0) * ppq
        // se redondea HACIA ARRIBA a un múltiplo del bucle de la instrumental
        // (si se conoce) o de un compás: así cada vuelta cae sobre los mismos
        // golpes de la base.
        let unit = instrLoopTicksHint >= barTicks ? instrLoopTicksHint : barTicks
        let loopTicks = max(unit, (spanTicks / unit).rounded(.up) * unit)
        return XFSession(
            header: .init(formatVersion: 1, tempoBPM: Double(bpm),
                          anchorHostTime: recStartHost,
                          anchorTick: Int(recAnchorTick.rounded()),
                          hostNumer: hc.numer, hostDenom: hc.denom,
                          notes: "xfl loop=\(Int(loopTicks.rounded())) bar=\(Int(barTicks.rounded()))"
                                 + (instrNameHint.isEmpty ? "" : " instr=\(instrNameHint)")),
            motion: recMotion, fader: recFader)
    }

    /// Longitud del bucle codificada en las notas de la cabecera ("… loop=<n> …").
    static func parseLoopTicks(_ notes: String) -> Double? {
        for tok in notes.split(whereSeparator: { $0 == " " || $0 == ";" })
        where tok.hasPrefix("loop=") {
            if let n = Double(tok.dropFirst(5)), n > 0 { return n }
        }
        return nil
    }

    /// Nombre de la instrumental codificado en las notas ("… instr=<slug> …").
    static func parseInstrName(_ notes: String) -> String {
        for tok in notes.split(whereSeparator: { $0 == " " || $0 == ";" })
        where tok.hasPrefix("instr=") {
            return String(tok.dropFirst(6))
        }
        return ""
    }

    /// Segundos grabados hasta ahora.
    public var recordedSeconds: Double {
        guard let a = recMotion.first?.hostTime, let b = recMotion.last?.hostTime, b > a
        else { return 0 }
        return HostClock().nanoseconds(fromHostTicks: b - a) / 1_000_000_000
    }

    /// Carga una linea grabada y la pone a reproducir en bucle (el plato lo
    /// mueve el fichero; el input se ignora, como en "repite conmigo").
    public func loadPlayback(_ s: XFSession) {
        let hc = HostClock(numer: max(1, s.header.hostNumer), denom: max(1, s.header.hostDenom))
        guard let t0 = s.motion.first?.hostTime else { return }
        let recBPM = s.header.tempoBPM > 0 ? s.header.tempoBPM : Double(bpm)
        // host-ticks -> TICKS musicales al tempo de la grabación, relativos al
        // primer sample (que es la fase 0 del bucle).
        func ticks(_ ht: UInt64) -> Double {
            guard ht > t0 else { return 0 }
            return hc.nanoseconds(fromHostTicks: ht - t0) / 1_000_000_000 * (recBPM / 60.0) * ppq
        }
        pbMotion = s.motion.map { (ticks($0.hostTime), $0.position) }
        pbFader = s.fader.map { (ticks($0.hostTime), !$0.isOpen) }
        // longitud del bucle: la de la cabecera (compases enteros). Si el fichero
        // es antiguo y no la trae, la última muestra.
        pbLen = Self.parseLoopTicks(s.header.notes) ?? (pbMotion.last?.t ?? 0)
        pbClock = 0
        playbackInstrName = Self.parseInstrName(s.header.notes)
        playingBack = pbLen > 0
    }

    public func stopPlayback() {
        playingBack = false
        playbackInstrName = ""
        pbMotion.removeAll(); pbFader.removeAll(); pbLen = 0
    }

    /// Un frame de grabacion (si esta grabando).
    private func recordFrame() {
        guard recording else { return }
        let ht = HostClock.now()
        recMotion.append(MotionSample(hostTime: ht, position: platterPosition,
                                      velocity: platterVelocity, confidence: 1))
        if recLastClosed != faderClosed {
            recLastClosed = faderClosed
            recFader.append(FaderSample(hostTime: ht, value: faderClosed ? 0 : 1,
                                        isOpen: !faderClosed))
        }
    }

    /// Posicion interpolada de la linea grabada en el tick `t` del bucle.
    private func pbPositionAt(_ t: Double) -> Double {
        guard !pbMotion.isEmpty else { return platterPosition }
        if t <= pbMotion[0].t { return pbMotion[0].pos }
        for i in 1..<pbMotion.count where pbMotion[i].t >= t {
            let a = pbMotion[i - 1], b = pbMotion[i]
            let f = (t - a.t) / max(1e-9, b.t - a.t)
            return a.pos + (b.pos - a.pos) * f
        }
        return pbMotion.last!.pos
    }
    private func pbClosedAt(_ t: Double) -> Bool {
        var closed = false
        for f in pbFader { if f.t <= t { closed = f.closed } else { break } }
        return closed
    }

    /// Tecla 1: **cue 1**. Salta el plato al inicio del sample (`posLo`), que es
    /// donde está el cue 1 por defecto. Deja el plato quieto y avisa al motor
    /// (por `onAdvance`) para que el sample vuelva al principio.
    public func jumpToCue() {
        platterPosition = posLo
        platterVelocity = 0
        onAdvance?(0, 0, currentTick)
    }

    /// Salta el plato a una fracción `f` (0…1) del **sample entero** (cue A/B de
    /// F.3). Inverso de `normalizedPosition`: deja el plato quieto ahí y avisa al
    /// motor para que el cabezal del sample vaya a ese punto.
    public func jumpTo(sampleFraction f: Double) {
        let clamped = min(1, max(0, f))
        let rel = clamped / AudioAsset.scratchPatternTopFraction
        platterPosition = min(posHi, max(posLo, posLo + rel * patternSpan))
        platterVelocity = 0
        onAdvance?(0, clamped, currentTick)
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
        cachedTickAt = -1
        traceBuffer.removeAll()
        platterVelocity = 0
        platterPosition = posLo
        if crPhase != .off { crPhase = .listen }
    }
}
