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

    /// Qué capa del gesto lleva **la máquina** mientras practicas tú.
    ///
    /// Un flare no se aprende haciendo las dos cosas a la vez desde el primer
    /// día: se separan las manos — primero el giro del disco solo, luego el
    /// corte de fader solo, y cuando cada una va sola, se juntan. Esto es esa
    /// separación, en la app.
    ///
    /// Es **ortogonal** al "repite conmigo": durante la fase de escucha la
    /// máquina toca las dos capas pase lo que pase; el modo de manos solo
    /// manda en tu turno y en la práctica libre.
    public enum AssistMode: String, Equatable, CaseIterable {
        /// Tú llevas disco y fader. La práctica normal.
        case both
        /// Tú mueves el disco; **la máquina corta**. Aísla la mano del plato.
        case hand
        /// La máquina mueve el disco; **tú cortas**. Aísla la mano del fader.
        case fader

        /// Nombre corto para la UI.
        public var label: String {
            switch self {
            case .both:  return "Las dos"
            case .hand:  return "Solo mano"
            case .fader: return "Solo fader"
            }
        }

        /// Qué está haciendo la máquina, para el aviso de la barra superior.
        public var badge: String? {
            switch self {
            case .both:  return nil
            case .hand:  return "EL FADER LO LLEVA LA MÁQUINA"
            case .fader: return "EL DISCO LO LLEVA LA MÁQUINA"
            }
        }
    }

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
    /// F.70 (ADR-076) — margen de "silencio infinito" hacia atrás, tan
    /// generoso como el de `posHi` hacia adelante (misma proporción). Un
    /// scratch real jamás lo alcanza: solo actúa de red de seguridad frente al
    /// martilleo sintético de la rueda del ratón (`scrollBy`), que ACUMULA
    /// impulso sin límite (a diferencia de `scrub`/`pushRealVelocity`, que
    /// imponen la velocidad real directamente y nunca podrían llegar tan
    /// lejos). Ver `coastPlatter`.
    private var posLoFloor: Double
    /// Span propio del patron (pico bajo -> pico alto), en unidades de posicion.
    private var patternSpan: Double
    /// Cuanta historia de traza guardamos, en ticks (~8 negras).
    private var historyTicks: Double

    // --- estado observable (barra superior) ---
    /// BPM de la rejilla / metrónomo. `Double` (no `Int`) porque en la práctica
    /// va **enganchado al BPM de la instrumental**, que se detecta con decimales
    /// (120,5). Si la rejilla fuera entera y la base 120,5 se separarían.
    @Published public private(set) var bpm: Double
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

    // --- descomposición mano / fader (F.23) ---
    /// Qué capa lleva la máquina cuando practicas tú (fuera de la escucha del
    /// "repite conmigo"). `.both` = práctica normal.
    @Published public private(set) var assist: AssistMode = .both

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
    /// F.44 — `true` mientras tienes los dedos en el trackpad y estas
    /// "sujetando el disco": la velocidad del plato ES la de tu mano (`scrub`),
    /// no un impulso acumulado, y `advance` NO le aplica friccion mientras dure.
    /// Se suelta con `endScrub()` o solo si dejan de llegar eventos (~80 ms).
    private var scrubbing = false
    private var lastScrubAt: CFTimeInterval = 0
    /// F.70 — separado de `scrubbing`: mientras el vinilo de timecode real
    /// manda velocidad (`pushRealVelocity`), el plato se mueve EXCLUSIVAMENTE
    /// con esa señal, sin física sintética de por medio (ni mientras llega, ni
    /// al dejar de llegar). Si se reutilizara `scrubbing`/la fricción de
    /// `scrub()` (pensada para el trackpad), al parar el vinilo de verdad el
    /// "teal" seguía decelerando solo un rato más — dejaba de ser fiel a la
    /// señal real, que es justo lo que no puede pasar aquí.
    private var timecodeDriving = false
    private var lastTimecodeAt: CFTimeInterval = 0
    /// F.74 (ADR-078) — "ancla" de posición real: `MotionSample.position`
    /// (segundos-nominales acumulados por el decoder xwax, `xf_timecoder`) en
    /// el instante en que se fijó esta referencia, junto con el
    /// `platterPosition` que le correspondía. Cada muestra real siguiente
    /// recalcula `platterPosition` como `anchorPlatterPosition + (position -
    /// anchorRevolutions)/duración·escala` — un ÚNICO salto desde el ancla,
    /// no una cadena de sumas — para que el plato SIEMPRE quede exactamente
    /// donde el decoder dice que está el vinilo, sin importar cuánto haya
    /// interpolado `coastPlatter` de por medio entre dos muestras reales.
    /// `nil` mientras no hay una muestra real reciente (se reancla al volver
    /// la señal, en vez de arrastrar un ancla vieja de antes del corte).
    private var realMotionAnchorRevolutions: Double?
    private var realMotionAnchorPlatterPosition: Double?
    /// F.81 (ADR-085) — desplazamiento FIJO entre la posición absoluta del
    /// bitstream y `platterPosition`, fijado una sola vez (la primera
    /// muestra enganchada de la racha) y NUNCA reanclado mientras se pierde
    /// y se recupera el enganche dentro de la misma racha. F.78 (ADR-082)
    /// reanclaba en cada transición enganche<->sin enganche: eso paraba la
    /// deriva MIENTRAS seguía enganchado, pero cualquier sesgo acumulado por
    /// la integral durante un tramo sin enganche quedaba CONGELADO para
    /// siempre en el nuevo ancla — con el enganche cayendo al 49-57% en un
    /// scratch real (muchas transiciones), el error se iba sumando en cada
    /// ciclo en vez de corregirse. Con el desplazamiento fijo, CADA muestra
    /// enganchada recalcula `platterPosition` directo desde la posición
    /// absoluta (nunca acumula sesgo), así que recuperar el enganche
    /// siempre corrige de vuelta a la verdad del vinilo. F.82 (ADR-086)
    /// suaviza el salto si el hueco es grande — ver `plausibleJumpThreshold`.
    private var absoluteToPlatterOffset: Double?
    /// F.82 (ADR-086) — a partir de cuántos SEGUNDOS-NOMINALES de hueco entre
    /// la posición absoluta y `platterPosition` se considera "grande" (se
    /// suaviza) en vez de "normal" (se corrige entero). 100 ms es generoso
    /// frente al hueco esperado entre dos muestras ENGANCHADAS consecutivas
    /// a la cadencia real de F.77 (~100 Hz, ~10 ms) incluso en un scratch muy
    /// rápido — así que un hueco así de grande solo aparece tras perder el
    /// enganche un buen rato, no durante el seguimiento normal.
    private static let plausibleJumpThresholdSeconds = 0.1
    /// Fracción del hueco "grande" que se cierra por muestra (geométrico):
    /// con la cadencia de F.77 (~100 Hz) converge al 95% en ~10 muestras,
    /// ~100 ms — rápido, pero sin el salto de un solo fotograma.
    private static let driftCorrectionFraction = 0.25

    /// Convierte el umbral de arriba (segundos-nominales) al espacio de
    /// `platterPosition`, con la misma conversión que el resto de esta
    /// función (`/sampleDurationSeconds*scale`).
    private static func plausibleJumpThreshold(sampleDurationSeconds: Double, scale: Double) -> Double {
        plausibleJumpThresholdSeconds / sampleDurationSeconds * scale
    }

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
    /// `var` para poder afinarlo desde la ventana Debug de Ajustes.
    public var frictionPerSecond: Double = 1.8
    /// F.08 — **rozamiento seco (Coulomb)**: una deceleración CONSTANTE, en
    /// unidades/s², que se suma al decaimiento exponencial. El exponencial solo
    /// nunca llega a cero (el disco se arrastra asintóticamente); el término de
    /// Coulomb lo para **en firme** cerca de cero, como hace un slipmat de
    /// verdad. `var` para afinarlo desde Ajustes › Debug.
    public var coulombFriction: Double = 3.0
    /// Ganancia del scroll del trackpad: puntos de scroll -> unidades/s. El
    /// recorrido del plato es ~1,5x el span del patron; un gesto normal tiene
    /// que poder cubrirlo entero (hasta el final del sample) en las dos
    /// direcciones. Subido de 0.26 a 0.40. (Solo lo usa `scrollBy` — la rueda de
    /// ratón —; el trackpad va por `scrub`.)
    private let scrollGain = 0.40
    /// F.44 — ganancia del `scrub` del trackpad: velocidad de la mano (puntos/s)
    /// -> velocidad del plato (unidades/s). Un gesto de scratch (~200-500
    /// puntos/s) da ~4-10 unidades/s: recorre el patrón en una fracción de
    /// segundo, como un scratch. `var` para afinarlo desde Ajustes › Debug.
    public var scrubGain = 0.02
    /// Impulso de una pulsacion de A / D, en unidades/s.
    private let keyImpulse = 2.2

    /// Sensibilidad del trackpad, PROVISIONAL para las pruebas sin mesa. Escala
    /// el scroll antes de convertirlo en velocidad del plato (1.0 = base). Un
    /// slider de la vista lo mueve en caliente porque a ojo el gesto va rapido.
    public var scrollSensitivity: Double = 1.0

    /// Desfase (ticks) de la rejilla respecto a la instrumental (botones ◀/▶ de
    /// la vista). El **fantasma** (en escucha del "repite conmigo") se evalúa en
    /// `currentTick + gridPhaseTicks`, así el fantasma que se OYE se mueve con el
    /// que se DIBUJA (la vista dibuja rejilla + fantasma en `now + gridShift`).
    /// La traza y el reloj NO se tocan: siguen siendo tiempo real.
    public var gridPhaseTicks: Double = 0

    public init(scratch: Scratch, bpm: Double) {
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
        self.posLoFloor = range.lowerBound - patternSpan * 2.5
        // Arranca en `posLo` = posicion 0 del sample.
        self.platterPosition = range.lowerBound
        self.bpm = min(220, max(40, bpm))
        // ~8 negras de historia a 60 fps y 200 BPM caben de sobra en 512; se
        // reserva de una para no re-asignar el array durante la práctica.
        self.traceBuffer.reserveCapacity(512)
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
        self.posLoFloor = range.lowerBound - patternSpan * 2.5
        self.platterPosition = range.lowerBound
        self.platterVelocity = 0
        self.scrubbing = false
        self.timecodeDriving = false
        self.realMotionAnchorRevolutions = nil
        self.realMotionAnchorPlatterPosition = nil
        self.absoluteToPlatterOffset = nil
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

        // F.44 — si dejan de llegar eventos de `scrub` (~80 ms) la mano se ha
        // levantado sin avisar (o hubo un salto de estado): vuelve la fisica de
        // inercia + friccion desde la ultima velocidad de la mano.
        if scrubbing, CACurrentMediaTime() - lastScrubAt > 0.08 { scrubbing = false }
        // F.70 — el mismo watchdog pero SIN física de por medio: si el vinilo
        // real deja de mandar velocidad (aguja levantada, o simplemente
        // paraste el plato con la mano — la confianza del timecode cae a la
        // vez que la velocidad, F.65), el plato se para EN FIRME. Nada de
        // fricción sintética: "el teal" solo se mueve con la señal real.
        if timecodeDriving, CACurrentMediaTime() - lastTimecodeAt > 0.08 {
            timecodeDriving = false
            platterVelocity = 0
            // F.74 — suelta el ancla: si la señal vuelve más tarde, se fija
            // una NUEVA desde la posición de entonces, no se arrastra una
            // referencia de antes del corte (eso sí sería "sticker drift").
            realMotionAnchorRevolutions = nil
            realMotionAnchorPlatterPosition = nil
            absoluteToPlatterOffset = nil
        }

        // CONGELADO (tecla P): el reloj no avanza y la traza no crece, pero el
        // plato sigue con su fisica y se sigue empujando el motor de audio ->
        // puedes scratchear el sample sobre la imagen quieta, sin dibujar.
        if frozen {
            coastPlatter(step: step)
            recordFrame()
            onAdvance?(normalizedVelocity, normalizedPosition, currentTick)
            return
        }

        // reloj musical
        currentTick += step * (bpm / 60.0) * ppq

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
                scrubbing = false
                timecodeDriving = false
                realMotionAnchorRevolutions = nil
                realMotionAnchorPlatterPosition = nil
                absoluteToPlatterOffset = nil
                // ...y con el fader ABIERTO: durante la escucha el fantasma pudo
                // dejarlo cerrado (un chirp/transformer acaba en mute) y si no lo
                // reabrimos aqui tu turno arranca mudo hasta que tocas Espacio.
                applyFaderClosed(false)
            }
        }

        if playingBack {
            // reproduccion de una linea grabada, ANCLADA a la instrumental: el
            // reloj de la linea avanza en TICKS al tempo actual, igual que la
            // base, asi los scratches caen siempre en el mismo punto del bucle.
            pbClock += step * (bpm / 60.0) * ppq
            if pbLen > 0, pbClock >= pbLen { pbClock = pbClock.truncatingRemainder(dividingBy: pbLen) }
            let g = pbPositionAt(pbClock)
            platterVelocity = (g - platterPosition) / step
            platterPosition = g
            applyFaderClosed(pbClosedAt(pbClock))
        } else {
            // Cada capa del gesto la lleva la MÁQUINA o TÚ, por separado (F.23):
            //  - en la escucha del "repite conmigo" la máquina lleva las dos;
            //  - fuera de ella, `assist` decide (solo mano / solo fader / las dos).
            // El patrón se muestrea en `currentTick + gridPhaseTicks`, igual que
            // la escucha, para que lo que se OYE vaya con lo que se DIBUJA cuando
            // la rejilla se ha movido con ◀/▶.
            let gt = currentTick + gridPhaseTicks

            // --- DISCO ---
            if machineDrivesDisc {
                let g = ghostPosition(atTick: gt)
                platterVelocity = (g - platterPosition) / step
                platterPosition = g
            } else {
                coastPlatter(step: step)
            }

            // --- FADER ---
            // si lo lleva la máquina, sale del patrón; si lo llevas tú, no se
            // toca aquí (lo mueve `setFaderClosed` desde el input / MIDI).
            if machineDrivesFader {
                applyFaderClosed(!ghostFaderOpen(atTick: gt))
            }
        }

        // traza: un punto por fotograma. Con el fader cerrado no suena, asi que
        // ese tramo de la linea se pinta apagado (nivel `.miss`), no la pantalla.
        // La traza se pinta en unidades de posicion del patron. Si el plato se
        // pasa del pico del patron, `platterPosition` > `posLo + patternSpan` y
        // la autopista lo extrapola hacia el hueco de arriba (ADR-041,
        // `geometry.patternFill`), hacia el final del sample.
        let level: HitLevel? = faderClosed ? .miss : nil
        traceBuffer.append(TracePoint(tick: currentTick, position: platterPosition, level: level))
        // Poda del prefijo caducado. Los ticks son monótonos, así que basta
        // contar cuántos puntos del principio quedan fuera de la ventana y
        // tirarlos de una (`removeFirst(k)`), sin recorrer todo el array con un
        // predicado como hacía `removeAll(where:)`.
        let cutoff = currentTick - historyTicks
        if traceBuffer.first.map({ $0.tick < cutoff }) == true {
            var drop = 1
            while drop < traceBuffer.count, traceBuffer[drop].tick < cutoff { drop += 1 }
            traceBuffer.removeFirst(drop)
        }

        recordFrame()
        onAdvance?(normalizedVelocity, normalizedPosition, currentTick)
    }

    /// Frena el plato al soltarlo: decaimiento **exponencial** (arrastre
    /// viscoso, rueda hacia cero) + **Coulomb** (deceleración constante que lo
    /// para en firme cerca de cero). Antes solo el exponencial + un corte a
    /// `1e-4`; el Coulomb da la detención corta y seca de un slipmat real
    /// (F.08).
    private func decayPlatterVelocity(step: Double) {
        platterVelocity *= exp(-frictionPerSecond * step)
        let c = coulombFriction * step
        if platterVelocity > c { platterVelocity -= c }
        else if platterVelocity < -c { platterVelocity += c }
        else { platterVelocity = 0 }
    }

    /// Física del plato al girar libre: frena por fricción (F.08) **salvo
    /// mientras haces `scrub`** — con los dedos en el trackpad la velocidad la
    /// sujeta tu mano (F.44) — **o mientras manda el timecode real** (F.70) —
    /// luego integra la posición y aplica los topes.
    ///
    /// F.70 (ADR-076): el tope de ABAJO ya NO clava la posición a `posLo` (el
    /// principio del sample) — la clava mucho más atrás, en `posLoFloor`. Con
    /// el vinilo real el plato puede seguir girando hacia atrás más allá del
    /// principio (el motor ya sabe devolver silencio ahí, `xf_player.c`); si
    /// aquí lo clavábamos justo en `posLo`, ese giro de más se perdía y al
    /// volver hacia delante el sample sonaba antes de tiempo — la "deriva" que
    /// perdía la referencia con el vinilo real. `posLoFloor` es tan generoso
    /// (mismo margen que `posHi` hacia adelante) que ningún scratch real lo
    /// alcanza nunca; solo frena el martilleo sintético de la rueda del ratón,
    /// que sí podría acumular velocidad sin límite.
    private func coastPlatter(step: Double) {
        if !scrubbing && !timecodeDriving { decayPlatterVelocity(step: step) }
        platterPosition += platterVelocity * step
        if platterPosition < posLoFloor { platterPosition = posLoFloor; platterVelocity = 0 }
        if platterPosition > posHi { platterPosition = posHi; platterVelocity = 0 }
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
        let rate = (bpm / 60.0) * ppq
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
            scrubbing = false
            timecodeDriving = false
            realMotionAnchorRevolutions = nil
            realMotionAnchorPlatterPosition = nil
            absoluteToPlatterOffset = nil
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

    // MARK: - descomposición mano / fader (F.23)

    /// ¿Lleva la máquina el DISCO ahora mismo? (escucha del "repite conmigo", o
    /// modo "solo fader"). Si es `true`, el input de plato se ignora.
    var machineDrivesDisc: Bool { crPhase == .listen || assist == .fader }
    /// ¿Lleva la máquina el FADER ahora mismo? (escucha, o modo "solo mano").
    var machineDrivesFader: Bool { crPhase == .listen || assist == .hand }

    /// Elige qué capa lleva la máquina mientras practicas tú. Al ceder una capa
    /// se resetea su estado para no arrancar con un valor viejo.
    public func setAssist(_ mode: AssistMode) {
        guard mode != assist else { return }
        assist = mode
        if mode == .fader { platterVelocity = 0 }        // la máquina va a llevar el disco
        if mode != .hand, faderClosed { applyFaderClosed(false) }  // te devuelvo el fader abierto
    }

    /// Recorre los tres modos: las dos → solo mano → solo fader → … (para MIDI).
    public func cycleAssist() {
        let all = AssistMode.allCases
        let i = (all.firstIndex(of: assist).map { $0 + 1 } ?? 0) % all.count
        setAssist(all[i])
    }

    // MARK: - entrada

    /// Scroll de **rueda de ratón** (sin `phase`): modelo de impulso — cada
    /// evento AÑADE momento. `deltaX` en puntos (+ = adelante). El trackpad usa
    /// `scrub` (control de posición). Se ignora si el disco lo lleva la máquina.
    public func scrollBy(_ deltaX: Double) {
        guard !machineDrivesDisc else { return }
        platterVelocity += deltaX * scrollGain * scrollSensitivity
    }

    /// F.44 — control de **posición**: mientras tienes los dedos en el trackpad,
    /// la velocidad del plato ES la de tu mano. `pointsPerSecond` = velocidad
    /// del gesto (la calcula la vista de `Δx/Δt`); se escala con la misma
    /// ganancia y sensibilidad que `scrollBy`. Si paras la mano sin levantarla
    /// (`pointsPerSecond == 0`) el plato se para EN SECO — como sujetar el
    /// vinilo. Se ignora si el disco lo lleva la máquina.
    public func scrub(pointsPerSecond p: Double) {
        guard !machineDrivesDisc else { return }
        platterVelocity = p * scrubGain * scrollSensitivity
        scrubbing = true
        lastScrubAt = CACurrentMediaTime()
    }

    /// Dedos fuera del trackpad: vuelve la inercia + fricción desde la última
    /// velocidad de la mano.
    public func endScrub() { scrubbing = false }

    /// F.65/F.74 — vinilo de timecode **real** (`MotionSample`, `XFCapture`).
    /// A diferencia de `scrub`/`scrollBy`/`nudge` (pensados para ratón/
    /// trackpad, con su propia ganancia "humana"), el DVS ya trae velocidad Y
    /// posición exactas: mover el vinilo a ritmo normal avanza el sample
    /// cargado al mismo ritmo — así es el scratch por timecode, el cabezal
    /// del sample sigue al vinilo 1:1. `sampleDurationSeconds` es la
    /// duración del sample de scratch cargado en el motor
    /// (`scratchFrameCount / sampleRateHz`; la calcula quien llama, porque
    /// `PracticeSession` no conoce el motor de audio a propósito, ver la
    /// cabecera del fichero).
    ///
    /// `velocity` deshace la conversión de `normalizedVelocity` para que,
    /// tras volver a pasar por ella en `onAdvance` (`LivePracticeView`), el
    /// ratio real llegue **intacto** a `engine.setVelocity` — sirve para el
    /// tono/velocidad del audio y para interpolar la posición entre dos
    /// muestras reales (`coastPlatter`, a 60 Hz).
    ///
    /// `position` (F.74, ADR-078) es la pieza que faltaba: **segundos-
    /// nominales acumulados** que ya lleva el decoder de verdad
    /// (`xf_timecoder.pos`, `pos += vel · nframes/sr` **por bloque de
    /// audio**, muchísimo más fino que el sondeo de `AppModel`). Antes
    /// `PracticeSession` solo recibía `velocity` y RE-INTEGRABA la posición
    /// ella misma a 60 Hz, sujetando la última velocidad conocida durante
    /// toda la ventana entre dos muestras — un "mantener y extrapolar" que
    /// se separaba poco a poco de dónde estaba el vinilo DE VERDAD.
    ///
    /// `absolutePosition` (F.78, ADR-082, Fase 2 de `docs/TIMECODE_DRIFT.md`)
    /// es el siguiente escalón: `position` es una INTEGRAL de la estimación
    /// de velocidad de xwax, y esa estimación tiene su propio sesgo (el
    /// filtro de pitch, más marcado en aceleraciones rápidas — medido en la
    /// Rane 72 real: con F.76/F.77 ya puestos, la deriva seguía creciendo
    /// durante el scratch aunque los frames perdidos del ring se quedaran
    /// planos). `absolutePosition` es una lectura DIRECTA del bitstream —
    /// no acumula error nunca — así que, cuando hay enganche,
    /// `platterPosition` se recalcula SIEMPRE desde ahí con un
    /// `absoluteToPlatterOffset` FIJO (F.81, ADR-085): fijado una sola vez
    /// (la primera muestra enganchada de la racha) y nunca reanclado por
    /// perder y recuperar el enganche dentro de la misma racha — a
    /// diferencia de F.78 (ADR-082), que reanclaba en cada transición y por
    /// eso congelaba para siempre cualquier sesgo acumulado durante un
    /// tramo sin enganche (con el enganche cayendo al 49-57 % en un scratch
    /// real, eso sumaba error en cada ciclo en vez de corregirlo — "sigue
    /// habiendo deriva y es impracticable"). Sin enganche se sigue con la
    /// integral (F.74), la única referencia que queda para el hueco corto
    /// hasta el próximo enganche — recuperarlo siempre corrige de vuelta a
    /// la verdad del vinilo. F.82 (ADR-086) añade una puerta de
    /// plausibilidad: un hueco pequeño (el caso normal, enganche continuo)
    /// se corrige entero; uno grande (tras perder el enganche un buen rato,
    /// o una lectura rara que se coló) se suaviza en unas pocas muestras en
    /// vez de teletransportar de golpe — sin xwax tener nada parecido a esto
    /// (su único filtro es un contador de bits consecutivos, ver ADR-086).
    ///
    /// `velocity` deshace la conversión de `normalizedVelocity` para que,
    /// tras volver a pasar por ella en `onAdvance` (`LivePracticeView`), el
    /// ratio real llegue **intacto** a `engine.setVelocity` — sirve para el
    /// tono/velocidad del audio y para interpolar la posición entre dos
    /// muestras reales (`coastPlatter`, a 60 Hz); esta interpolación nunca
    /// tiene más de ~10 ms (F.77) para acumular error antes de que la
    /// siguiente muestra real la corrija — no se encadena.
    /// `LivePracticeView.onAdvance` ya manda `normalizedPosition` al motor
    /// como ancla anti-deriva (`engine.setScratchTarget`, ADR-042): esta
    /// corrección llega también al audio sin tocar una sola línea del motor
    /// RT.
    ///
    /// Usa su propio `timecodeDriving`/`lastTimecodeAt` (F.70) — NO
    /// `scrubbing`: ese es el de `scrub()` (trackpad), pensado para que al
    /// soltar los dedos vuelva la física de inercia + fricción. Aquí no hay
    /// tal cosa — el plato "es" el vinilo real, así que si deja de mandar
    /// muestras más de 80 ms (aguja levantada, dropout — B5.5 ya lo valida a
    /// nivel de señal, o simplemente lo paraste con la mano) el plato se para
    /// EN FIRME y suelta el ancla (se reancla fresco cuando vuelva la señal).
    public func pushRealMotion(position: Double, absolutePosition: Double? = nil,
                               velocity: Double, sampleDurationSeconds: Double) {
        guard !machineDrivesDisc, sampleDurationSeconds > 0 else { return }
        let scale = patternSpan / AudioAsset.scratchPatternTopFraction

        if let absolutePosition {
            // F.81 (ADR-085): desplazamiento FIJO, nunca reanclado por
            // perder/recuperar el enganche -- cada muestra enganchada
            // recalcula `platterPosition` directo desde la posición
            // absoluta, así que SIEMPRE corrige de vuelta a la verdad del
            // vinilo, en vez de solo parar de derivar desde donde fuera que
            // se quedó la integral.
            if let offset = absoluteToPlatterOffset {
                let target = offset + absolutePosition / sampleDurationSeconds * scale
                let gap = target - platterPosition
                // F.82 (ADR-086) — puerta de plausibilidad: un hueco pequeño
                // (enganche continuo, el caso normal) se corrige entero, sin
                // suavizar. Un hueco grande (tras un tramo largo sin
                // enganche, o una lectura rara) se acerca solo una FRACCIÓN
                // cada muestra en vez de teletransportar de golpe -- converge
                // a la verdad exacta en unas pocas muestras (~100 ms a
                // 100 Hz, F.77) sin el salto brusco de un solo fotograma.
                // Usa `position`/`absolutePosition` (el propio dominio de
                // segundos-nominales), no el reloj real: así es determinista
                // y no depende de la cadencia real de muestreo.
                if abs(gap) <= Self.plausibleJumpThreshold(sampleDurationSeconds: sampleDurationSeconds, scale: scale) {
                    platterPosition = target
                } else {
                    platterPosition += gap * Self.driftCorrectionFraction
                }
            } else {
                // primer enganche de la racha: fija el desplazamiento
                // igualando al `platterPosition` actual, sin mover el plato
                // de golpe.
                absoluteToPlatterOffset = platterPosition - absolutePosition / sampleDurationSeconds * scale
            }
            // limpia el ancla de respaldo: si se pierde el enganche después,
            // debe reanclar desde AQUÍ (ya corregido), no desde un punto
            // viejo de antes de este bloque.
            realMotionAnchorRevolutions = nil
            realMotionAnchorPlatterPosition = nil
        } else if let anchorRevs = realMotionAnchorRevolutions,
                  let anchorPos = realMotionAnchorPlatterPosition {
            // sin enganche: sigue con la integral (F.74) desde el último
            // punto bueno -- solo cubre el hueco corto hasta el próximo
            // enganche, donde el desplazamiento fijo de arriba vuelve a
            // mandar y corrige cualquier sesgo acumulado aquí.
            platterPosition = anchorPos + (position - anchorRevs) / sampleDurationSeconds * scale
        } else {
            realMotionAnchorRevolutions = position
            realMotionAnchorPlatterPosition = platterPosition
        }
        platterVelocity = velocity / sampleDurationSeconds * scale
        timecodeDriving = true
        lastTimecodeAt = CACurrentMediaTime()
    }

    /// Pulsacion de tecla de plato. `forward` = hacia adelante (D); si no, atras (A).
    public func nudge(forward: Bool) {
        guard !machineDrivesDisc else { return }
        platterVelocity += (forward ? 1.0 : -1.0) * keyImpulse
    }

    /// Fader desde el INPUT del usuario (Espacio / MIDI). Se ignora si el fader
    /// lo lleva la máquina (escucha del "repite conmigo", o modo "solo mano").
    public func setFaderClosed(_ closed: Bool) {
        guard !machineDrivesFader else { return }
        applyFaderClosed(closed)
    }

    /// Aplica el estado del fader SIN mirar quién manda. Lo usan las rutas en
    /// que la propia máquina mueve el fader (escucha, playback, `setAssist`).
    private func applyFaderClosed(_ closed: Bool) {
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
        let spanTicks = spanSec * (bpm / 60.0) * ppq
        // se redondea HACIA ARRIBA a un múltiplo del bucle de la instrumental
        // (si se conoce) o de un compás: así cada vuelta cae sobre los mismos
        // golpes de la base.
        let unit = instrLoopTicksHint >= barTicks ? instrLoopTicksHint : barTicks
        let loopTicks = max(unit, (spanTicks / unit).rounded(.up) * unit)
        return XFSession(
            header: .init(formatVersion: 1, tempoBPM: bpm,
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
        let recBPM = s.header.tempoBPM > 0 ? s.header.tempoBPM : bpm
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
        scrubbing = false
        timecodeDriving = false
        realMotionAnchorRevolutions = nil
        realMotionAnchorPlatterPosition = nil
        absoluteToPlatterOffset = nil
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
        scrubbing = false
        timecodeDriving = false
        realMotionAnchorRevolutions = nil
        realMotionAnchorPlatterPosition = nil
        absoluteToPlatterOffset = nil
        onAdvance?(0, clamped, currentTick)
    }

    public func setBPM(_ value: Double) {
        // un decimal: la detección de tempo y el TAP dan 120,53… -> 120,5.
        let clamped = (min(220, max(40, value)) * 10).rounded() / 10
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
        scrubbing = false
        timecodeDriving = false
        realMotionAnchorRevolutions = nil
        realMotionAnchorPlatterPosition = nil
        absoluteToPlatterOffset = nil
        platterPosition = posLo
        if crPhase != .off { crPhase = .listen }
    }
}
