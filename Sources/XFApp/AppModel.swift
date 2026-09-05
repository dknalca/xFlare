// SPDX-License-Identifier: GPL-3.0-only

import Foundation
import Combine
import XFClock
import XFNotation
import XFPersistence
import XFProfiles
import XFCapture
import XFAnalysis
import XFRender
import XFPrimitives

/// El coordinador de la app: es dueño del contenido (`Catalog`), la base
/// (`XFDatabase`) y el motor de audio (`EngineHandle`), lleva la navegacion entre
/// pantallas y sirve a cada vista sus datos ya montados con los *assemblers*.
///
/// `ObservableObject` + `@Published` (macOS 11; nada de `@Observable`).
public final class AppModel: ObservableObject {

    public enum Screen: Equatable {
        case home
        case calibration
        /// Ficha de un truco antes de practicarlo: dibujo + historia + variantes.
        case exerciseDetail(scratchId: String)
        case practice(exerciseId: String, variantId: String)
        case results
        /// El navegador de trucos (antes "Librería", ahora "Trucos").
        case library
        /// Librería de medios: instrumentales y samples del usuario.
        case mediaLibrary
        /// Editor de una instrumental de la librería: tempo/rejilla, cues, loops.
        case instrumentalEditor(path: String)
        /// Editor de un sample de la librería: inicio + duración.
        case sampleEditor(path: String)
        case progress(exerciseId: String, variantId: String)
        case myTable
        case settings
        case freeMode
        /// Calentamiento adaptativo (F.0 / ADR-027).
        case warmup
        case error(String)
    }

    public let catalog: Catalog
    public let db: XFDatabase
    public let engine: EngineHandle?
    public let profiles: ProfileStore
    /// De donde salen los recursos (repo en dev, bundle en el `.app`). Lo usa la
    /// practica para cargar los audios.
    public let content: ContentLoader

    @Published public private(set) var screen: Screen = .home
    @Published public var settings: AppSettings {
        didSet {
            Self.persist(settings)
            rebuildMidiCommandMap()
            applyAudioDevicePreferences()
            // F.72 (ADR-077): la calibración guardada (cutIn/histéresis/hamster)
            // se busca por `outputDeviceUID` (ver `rebuildCrossfaderSource`) — si
            // cambia el dispositivo de salida (p. ej. el asistente de
            // Calibración lo fija al entrar), hay que releerla YA, no esperar a
            // que cambie el perfil. Comparado contra `oldValue` para no
            // reconstruir el crossfader en CADA cambio de ajuste (un slider de
            // Debug no tiene nada que ver con esto).
            if oldValue.outputDeviceUID != settings.outputDeviceUID { rebuildCrossfaderSource() }
            // pre-analiza las instrumentales nuevas para que carguen al instante.
            analysisCache.analyzeAll(settings.instrumentalLibrary,
                                     sampleRate: engine?.sampleRateHz ?? 48_000)
        }
    }

    /// Vuelca el dispositivo/canal elegidos en Ajustes › Hardware al motor
    /// (`EngineHandle.preferred*`). Solo los guarda para el PRÓXIMO
    /// `start()`/`startOutput()` — igual que el buffer, cambiar el
    /// dispositivo o el canal no reinicia el motor en caliente.
    private func applyAudioDevicePreferences() {
        engine?.preferredOutputDeviceUID = settings.outputDeviceUID.isEmpty ? nil : settings.outputDeviceUID
        engine?.preferredOutputChannel = settings.outputChannel
        engine?.preferredInputDeviceUID = settings.inputDeviceUID.isEmpty ? nil : settings.inputDeviceUID
        engine?.preferredInputChannel = settings.inputChannel
        engine?.preferredInstrumentalOutputChannel = settings.instrumentalOutputChannel
    }

    /// Caché de análisis de tempo de las instrumentales de la librería (fase 2).
    public let analysisCache = InstrumentalAnalysisCache()
    /// Ajustes del editor de instrumental (tempo/rejilla, cues, loops) por fichero.
    public let instrumentalEdits = InstrumentalEditStore()
    /// Recorte del editor de samples (inicio + duración) por fichero.
    public let sampleEdits = SampleEditStore()
    @Published public var activeProfileId: String? {
        didSet {
            rebuildMidiCommandMap()
            rebuildCrossfaderSource()
        }
    }

    /// Comandos de práctica que llegan por MIDI (cue, reiniciar base, congelar,
    /// grabar, fader, …). `midiMonitor` (hardware, ver más abajo) alimenta
    /// `midiCommands` con `ingest`; la práctica se suscribe a `practiceCommandEvents`.
    public let midiCommands = MidiCommandSource()
    public let practiceCommandEvents = PassthroughSubject<PracticeCommandEvent, Never>()
    /// "MIDI Learn" de Ajustes: escucha CoreMIDI mientras esa pantalla está
    /// abierta y asigna el control que se mueva al comando seleccionado. Es
    /// UN cliente CoreMIDI aparte de `midiMonitor` a propósito: mientras se
    /// aprende no hace falta que los mensajes también disparen comandos reales.
    public let midiLearn = MidiLearnModel()

    /// Escucha CoreMIDI real durante TODA la sesión (a diferencia de `midiLearn`,
    /// que solo escucha mientras Ajustes está en pantalla): alimenta
    /// `midiCommands` (cue, freeze, samples…, ADR-054) y, si el perfil activo
    /// lee el crossfader por MIDI (ADR-021), `crossfaderSource`. `AppModel.boot()`
    /// la abre — construirla aquí no toca CoreMIDI (para no abrirlo en los tests
    /// que crean `AppModel` a mano, que no llaman a `boot()`).
    public let midiMonitor = MidiMonitorConnector()
    /// Cualquier mensaje MIDI real, sin filtrar — lo usa `AppRootView` para el
    /// paso "Fader" del asistente (F.67): "aprender" qué CC/canal es el
    /// crossfader observando el tráfico mientras el usuario lo mueve de tope a
    /// tope, y contar cortes en vivo con el cutIn/histéresis que se estén
    /// ajustando ahí. `AppModel` no conoce `CalibrationWizardModel` (ADR-073:
    /// vive en la vista); esto es el mismo patrón que `onTimecodeSample`.
    public var onRawMidiMessage: ((UInt8, UInt8, UInt8) -> Void)?
    /// Crossfader por MIDI del perfil activo (ADR-021), si `crossfader.method
    /// = midi`. `nil` si el perfil usa otro método o no se ha podido construir.
    /// Se reconstruye cada vez que cambia `activeProfileId`.
    private var crossfaderSource: MidiFaderSource?
    /// F.79 (ADR-083) — hay un crossfader de HARDWARE real leído para el
    /// perfil activo (MIDI, ADR-021 — o `audio_return`, mismo caso): el propio
    /// mezclador corta el audio por su circuito analógico, así que
    /// `LivePracticeView` no debe silenciar el scratch por software cuando el
    /// corte lo hace el usuario de verdad con ese fader (solo dibujarlo) —
    /// hacerlo dos veces, con curvas distintas, sonaba raro en la Rane 72 real.
    public var hasHardwareCrossfader: Bool { crossfaderSource != nil }

    // MARK: - captura de timecode para el scope de calibración (paso 3)

    /// Últimas lecturas del plato para `ScopeView` (`docs/UI_DESIGN.md` §3.1:
    /// "Scope circular en vivo"). Vacío mientras no hay captura activa.
    /// Acotado a un rastro corto — el scope solo dibuja lo reciente.
    @Published public private(set) var scopeReadings: [ScopeReading] = []
    /// Se llama en cada lectura nueva mientras hay captura activa. `AppRootView`
    /// lo cablea a `CalibrationWizardModel.reportTimecode(...)` — `AppModel` no
    /// es dueño de ese modelo (vive en la vista, ADR-073), así que no lo llama
    /// directo.
    public var onTimecodeSample: ((MotionSample) -> Void)?
    /// F.65 — el mismo tráfico que `onTimecodeSample`, como publisher: lo
    /// escucha `LivePracticeView` (Freestyle/práctica) para mover el plato
    /// con el vinilo real. Un publisher (no un closure único como
    /// `onTimecodeSample`) porque aquí SÍ puede haber más de un suscriptor
    /// potencial sin que uno pise al otro.
    ///
    /// F.78 (ADR-082, Fase 2 de `docs/TIMECODE_DRIFT.md`) — además de la
    /// muestra relativa de siempre, manda `absolutePositionSeconds`: la
    /// posición del bitstream (`TimecodeMotionSource.absoluteLock`, no
    /// acumula error nunca) cuando hay enganche, `nil` si no. Medido en la
    /// Rane 72 real (F.76/F.77): con el ring ya arreglado, la deriva SIGUE
    /// creciendo durante el scratch mientras los frames perdidos se quedan
    /// planos — la integral de `xf_timecoder_position()` tiene su propio
    /// sesgo (el filtro de pitch de xwax, más marcado en aceleraciones
    /// rápidas), y F.74 solo la anclaba a SÍ MISMA (nunca corregía ese
    /// sesgo). `PracticeSession.pushRealMotion` usa esto para anclar a la
    /// posición absoluta cuando está disponible, en vez de a la integral.
    public let motionSampleEvents = PassthroughSubject<(sample: MotionSample, absolutePositionSeconds: Double?), Never>()
    private var timecodeSource: TimecodeMotionSource?
    /// F.77 (ADR-081) — antes esto era un `Timer` en `RunLoop.main`: el
    /// consumidor del ring de entrada competía con el redibujado de
    /// SwiftUI/SpriteKit por el hilo principal, y perdía. Medido en la Rane
    /// 72 real (F.76): **977 frames perdidos solo girando el disco, sin
    /// scratchear** — el hilo principal no daba abasto ni en reposo. Ahora
    /// el drenaje corre en su propia cola serial, a 100 Hz (10 ms) en vez de
    /// 30 Hz — con ~85 ms de capacidad en el ring (32 bloques de 128 frames
    /// a 48 kHz), eso deja de sobra margen frente al jitter de una cola
    /// dedicada (mucho más fiable que competir con la UI). Solo esta cola
    /// toca `timecodeSource`/`timecodeDrainTimer`; `stopTimecodeCapture()`
    /// cancela el timer con `.sync` en la MISMA cola antes de soltar nada,
    /// así ninguna llamada a `drainTimecode()` puede quedar en vuelo cuando
    /// se limpia el estado.
    private let timecodeDrainQueue = DispatchQueue(label: "xflare.timecode.drain", qos: .userInitiated)
    private var timecodeDrainTimer: DispatchSourceTimer?

    // MARK: - diagnóstico de deriva ("sticker drift", F.76, ADR-080)

    /// Deriva ACUMULADA, en milisegundos, desde el primer enganche de esta
    /// captura: cuánto se ha separado la posición INTEGRADA
    /// (`MotionSample.position`, acumula la estimación de velocidad y por
    /// tanto puede acumular sesgo) de la posición ABSOLUTA que trae el
    /// bitstream (no acumula error nunca).
    ///
    /// OJO — esto NO es `integrada - absoluta` a pelo: la absoluta es la
    /// posición dentro del vinilo FÍSICO (dondequiera que esté la aguja en
    /// ese disco de ~12 min), con un cero completamente distinto al de la
    /// integrada (que arranca en 0 al abrir el motor). Restarlas sin más da
    /// un número enorme y sin sentido — la posición en el disco, no una
    /// deriva (primera versión de F.76, corregida el mismo día). Se ancla
    /// `(integrada, absoluta)` en el PRIMER enganche y luego se comparan
    /// los DELTAS desde ese ancla: así el punto de partida en el disco no
    /// importa, solo cuánto se separan las dos velocidades integradas desde
    /// que hay referencia. `nil` hasta el primer enganche. Ver
    /// `docs/TIMECODE_DRIFT.md`.
    @Published public private(set) var timecodeDriftMs: Double?
    /// Fracción (0...1) de lecturas con el bitstream enganchado desde que
    /// arrancó esta captura. Un scratch agresivo desengancha el bitstream a
    /// menudo — un número bajo aquí no es un fallo, es información: mientras
    /// no engancha, `timecodeDriftMs` no se actualiza (se queda con el
    /// último valor conocido).
    @Published public private(set) var timecodeLockedFraction: Double = 0
    private var timecodeLockedTicks = 0
    private var timecodeTotalTicks = 0
    /// Ancla del cálculo de deriva de arriba: `(integrada, absoluta)` en el
    /// primer enganche de la captura en curso. `nil` = todavía sin fijar.
    private var timecodeDriftAnchor: (integrated: Double, absolute: Double)?

    /// F.76 (ADR-080) — el cálculo puro de la deriva, extraído para poder
    /// testearlo sin motor real ni CoreAudio (`pollTimecode` sí los necesita).
    ///
    /// Primera versión (el mismo día): `integradaAhora - absolutaAhora` a
    /// pelo. Con la Rane 72 real dio "-136567 ms" — no es un sesgo de
    /// integración creíble en un minuto de prueba, es la posición del disco:
    /// `absolutaAhora` vive en el reloj del VINILO FÍSICO (dondequiera que
    /// esté la aguja en ese disco de ~12 min), `integradaAhora` en el reloj
    /// de "segundos desde que arrancó el motor" — ceros completamente
    /// distintos, restarlos sin más no mide nada real.
    ///
    /// La cura: ANCLAR `(integrada, absoluta)` la primera vez que hay
    /// enganche, y comparar después los DELTAS de cada una desde su propio
    /// ancla. El punto de partida en el disco se cancela solo; lo que queda
    /// es cuánto se ha separado una velocidad integrada de la otra desde que
    /// hay referencia — la deriva de verdad.
    static func timecodeDrift(integratedNow: Double, absoluteNow: Double,
                              anchor: (integrated: Double, absolute: Double)?)
        -> (driftMs: Double, anchor: (integrated: Double, absolute: Double)) {
        guard let anchor else {
            // primer enganche: no hay deriva que enseñar todavía (0 por
            // definición), pero SÍ hay que fijar la referencia.
            return (0, (integratedNow, absoluteNow))
        }
        let deltaIntegrated = integratedNow - anchor.integrated
        let deltaAbsolute = absoluteNow - anchor.absolute
        return ((deltaIntegrated - deltaAbsolute) * 1000.0, anchor)
    }

    /// Arranca la captura de entrada de verdad para leer el vinilo de timecode
    /// en vivo: para el motor (que hasta ahora solo corría "solo salida", B4.2),
    /// lo reabre con la entrada activada (canal de `AppSettings`, F.60) y drena
    /// el PCM capturado hacia un `TimecodeMotionSource` propio (el mismo
    /// wrapper de `xf_timecoder` que ya validó B5.5 con vinilo real), ahora en
    /// `timecodeDrainQueue` (F.77) en vez del hilo principal. Para la
    /// pantalla de Calibración (`AppRootView`); no toca nada si `engine` es
    /// `nil` (tests sin motor).
    public func startTimecodeCapture() {
        guard timecodeSource == nil, let engine else { return }
        engine.stop()
        // deviceUID/canal salen de `EngineHandle.preferred*` (F.60), que
        // `applyAudioDevicePreferences()` ya mantiene sincronizados con
        // `settings`; no hace falta repetirlos aquí.
        guard engine.start() else { return }

        let source = TimecodeMotionSource(config: .init(
            format: "serato_2a",   // única definición validada contra hardware real (B5.5)
            sampleRate: UInt32(engine.sampleRateHz), hamster: settings.hamster))
        guard (try? source.start()) != nil else {
            engine.stop()
            _ = engine.startOutput()
            return
        }
        timecodeSource = source
        scopeReadings = []
        timecodeDriftMs = nil
        timecodeLockedFraction = 0
        timecodeLockedTicks = 0
        timecodeTotalTicks = 0
        timecodeDriftAnchor = nil

        // F.77 (ADR-081) — 100 Hz (10 ms), no 30 Hz: con ~85 ms de capacidad
        // en el ring (32 bloques de 128 frames a 48 kHz), deja de sobra
        // margen frente al jitter de una cola dedicada. `timecodeSource` ya
        // quedó escrito arriba, en este mismo hilo (main), ANTES de que el
        // timer pueda disparar por primera vez: GCD garantiza que ese
        // escritura ya es visible en `timecodeDrainQueue` cuando llegue el
        // primer evento (happens-before de `resume()`).
        let timer = DispatchSource.makeTimerSource(queue: timecodeDrainQueue)
        timer.schedule(deadline: .now(), repeating: .milliseconds(10))
        timer.setEventHandler { [weak self] in self?.drainTimecode() }
        timer.resume()
        timecodeDrainTimer = timer
    }

    /// Corre en `timecodeDrainQueue` (F.77), NUNCA en el hilo principal: es
    /// la parte que tiene que ir fina de verdad (drenar el ring antes de que
    /// se llene, ~85 ms de margen). Lo único que toca del estado de
    /// `AppModel` son `engine` (`let`, inmutable, seguro desde cualquier
    /// hilo) y `timecodeSource` (solo se reasigna en el hilo principal, y
    /// `stopTimecodeCapture()` cancela este timer con `.sync` en esta MISMA
    /// cola antes de tocarlo, así que aquí nunca hay una carrera). El
    /// resultado se manda a `applyTimecodeSample` en el hilo principal —
    /// ahí es donde de verdad hace falta estar (todo lo que sigue es
    /// `@Published`).
    private func drainTimecode() {
        guard let engine, let source = timecodeSource else { return }
        let pcm = engine.drainInput()
        guard pcm.count >= 2 else { return }
        pcm.withUnsafeBufferPointer { buf in
            guard let base = buf.baseAddress else { return }
            source.submit(pcm: base, frames: pcm.count / 2, hostTime: HostClock.now())
        }
        guard let sample = source.latest() else { return }
        let lock = source.absoluteLock
        DispatchQueue.main.async { [weak self] in
            self?.applyTimecodeSample(sample, lock: lock)
        }
    }

    /// Siempre en el hilo principal (llamado desde `drainTimecode`, en
    /// `timecodeDrainQueue`, vía `DispatchQueue.main.async`): toda la
    /// mutación de `@Published` del diagnóstico de timecode vive aquí, sin
    /// cambios de comportamiento respecto a antes de F.77 — solo cambia
    /// QUIÉN llama y desde qué hilo.
    private func applyTimecodeSample(_ sample: MotionSample,
                                     lock: (positionSeconds: Double, ageSeconds: Double)?) {
        scopeReadings.append(ScopeReading(position: sample.position, velocity: sample.velocity,
                                          confidence: Double(sample.confidence)))
        // ~8s de rastro a 30 Hz de antes; a 100 Hz de sondeo se poda más a
        // menudo pero la ventana visible del scope no cambia.
        if scopeReadings.count > 240 { scopeReadings.removeFirst(scopeReadings.count - 240) }

        // F.76 (ADR-080): comparar la posición integrada contra la absoluta
        // SOLO cuando hay bitstream enganchado ahora mismo -- sin eso no hay
        // con qué comparar, y `timecodeDriftMs` se queda con el último valor
        // (no se pone a 0: eso escondería la deriva real detrás de un
        // "sin dato" que parece "sin problema").
        timecodeTotalTicks += 1
        if let lock {
            timecodeLockedTicks += 1
            let (drift, anchor) = Self.timecodeDrift(integratedNow: sample.position,
                                                     absoluteNow: lock.positionSeconds,
                                                     anchor: timecodeDriftAnchor)
            timecodeDriftAnchor = anchor
            timecodeDriftMs = drift
        }
        timecodeLockedFraction = timecodeTotalTicks > 0
            ? Double(timecodeLockedTicks) / Double(timecodeTotalTicks) : 0

        onTimecodeSample?(sample)
        motionSampleEvents.send((sample, lock?.positionSeconds))
    }

    /// Para la captura y deja el motor en modo "solo salida" otra vez, listo
    /// para practicar. Idempotente.
    public func stopTimecodeCapture() {
        // F.77 — `.sync` en la MISMA cola del timer: si `drainTimecode()`
        // está en vuelo, esto espera a que termine antes de seguir (la cola
        // es serial); después de este cancel, ninguna llamada más puede
        // empezar. Solo entonces es seguro tocar `timecodeSource` desde aquí.
        timecodeDrainQueue.sync {
            timecodeDrainTimer?.cancel()
            timecodeDrainTimer = nil
        }
        timecodeSource?.stop()
        timecodeSource = nil
        scopeReadings = []
        guard let engine else { return }
        engine.stop()
        _ = engine.startOutput()
    }

    /// Ejercicio en curso para la tarjeta "Continuar" (en memoria por ahora).
    @Published public var continueExerciseId: String?

    // instantaneas para las pantallas
    @Published public private(set) var home: HomeSummary?
    @Published public private(set) var library: LibraryBrowser?
    @Published public private(set) var lastResults: ResultsSummary?

    public init(catalog: Catalog, db: XFDatabase, engine: EngineHandle? = nil,
                profiles: ProfileStore = ProfileStore(bundled: [], user: []),
                settings: AppSettings = .defaults,
                content: ContentLoader = RepoContentLoader()) {
        self.catalog = catalog
        self.db = db
        self.engine = engine
        self.profiles = profiles
        self.settings = settings
        self.content = content

        // El decodificador MIDI reenvía cada comando al subject al que se
        // suscribe la práctica.
        self.midiCommands.onCommand = { [weak self] event in
            self?.practiceCommandEvents.send(event)
        }
        // Un solo mensaje MIDI real puede ser, a la vez, un comando discreto
        // (cue, freeze…) Y el crossfader — se reparte a los dos decodificadores,
        // cada uno filtra lo que no es suyo. `midiMonitor.open()` no se llama
        // aquí (ver doc de `midiMonitor`); solo se deja el reparto listo.
        midiMonitor.onMessage = { [weak self] status, data1, data2 in
            // CoreMIDI entrega en su propio hilo, no en el principal (mismo
            // aviso que ya tenía `MidiLearnModel`); todo lo de aquí toca
            // `@Published`/`@State` río abajo, así que salta al principal.
            DispatchQueue.main.async {
                self?.midiCommands.ingest(status: status, data1: data1, data2: data2)
                self?.crossfaderSource?.ingest(status: status, data1: data1, data2: data2,
                                               hostTime: HostClock.now())
                self?.onRawMidiMessage?(status, data1, data2)
            }
        }
        // `midiLearn.onLearn` lo cablea `SettingsView` mientras está en pantalla
        // (tiene que actualizar SU copia de los ajustes, no solo la de aquí).
        rebuildMidiCommandMap()
        rebuildCrossfaderSource()
        // el `didSet` de `settings` no salta en la asignación inicial de arriba.
        applyAudioDevicePreferences()
    }

    /// Abre `midiMonitor` de verdad (CoreMIDI). Separado del `init` a propósito:
    /// los tests que construyen `AppModel(catalog:db:...)` a mano no llaman a
    /// esto y no tocan CoreMIDI; solo lo hace la app real (`AppModel.boot()`).
    /// No lanza si CoreMIDI falla (p. ej. sin ninguna fuente) — se queda sin
    /// escuchar en vez de tumbar el arranque.
    public func openMidiMonitor() {
        try? midiMonitor.open()
    }

    /// Reconstruye `crossfaderSource` a partir del perfil activo: si
    /// `crossfader.method = midi` (ADR-021), un `MidiFaderSource` listo para
    /// recibir mensajes reales de `midiMonitor`; si no, `nil` (no hay
    /// crossfader que leer por MIDI con este perfil).
    ///
    /// El umbral de corte (`cutIn`) sale de la calibración GUARDADA del
    /// dispositivo si existe (`XFPersistence.DeviceCalibration`, la afina el
    /// asistente) — es la fuente correcta, "calibrado a oído" por el usuario.
    /// Si todavía no hay calibración (lo normal hoy: el asistente no cablea
    /// ese paso, B4.2), se cae al `cut_in.left` del perfil como arranque
    /// razonable, no a un valor inventado aquí.
    ///
    /// F.72 (ADR-077) — la calibración se busca por el **UID del dispositivo
    /// de salida** (`AppSettings.outputDeviceUID`), NO por `activeProfileId`:
    /// `deviceKey` identifica la MESA física (`DeviceCalibration.deviceKey`,
    /// "el UID del dispositivo de audio"), y el asistente (`CalibrationWizardModel.
    /// result()`) ya guarda con esa clave (`AppRootView.applyCalibrationSelection`).
    /// Buscar por `activeProfileId` (el perfil `.conf`, un concepto distinto —
    /// dos mesas podrían compartir perfil) nunca coincidía con lo guardado:
    /// la calibración parecía "no guardarse de una sesión a otra".
    private func rebuildCrossfaderSource() {
        crossfaderSource?.stop()
        crossfaderSource = nil
        guard let id = activeProfileId, let profile = profiles.profile(id: id),
              let profileConfig = try? MidiCrossfaderConfig(from: profile) else { return }

        let saved = settings.outputDeviceUID.isEmpty ? nil
            : try? db.calibration(deviceKey: settings.outputDeviceUID)
        let cutIn = Float(saved?.faderCutIn ?? profile.crossfader.cutInLeft ?? 0.5)
        let hysteresis = Float(saved?.faderHysteresis ?? profile.crossfader.hysteresis ?? 0.05)
        let hamster = saved?.hamster ?? profile.crossfader.reverseDefault ?? false
        let binarizer = FaderBinarizer(cutIn: min(1, max(0, cutIn)),
                                       hysteresis: max(0, hysteresis), hamster: hamster)

        // F.72 (ADR-077) — si el asistente aprendió un CC/canal para este
        // dispositivo (`MidiFaderLearner`/F.67) y quedó guardado, manda sobre
        // el que declare el perfil: el perfil puede no traerlo, o traer uno
        // equivocado (B5.5 ya enseñó a no fiarse del papel). Mismo criterio
        // que `AppRootView.rebuildFaderConfig()` usa DENTRO del asistente;
        // esto lo lleva también a la práctica real, no solo a la calibración.
        let config: MidiCrossfaderConfig
        if let ch = saved?.faderMidiChannel, let cc = saved?.faderMidiCC,
           let lo = saved?.faderMidiRawMin, let hi = saved?.faderMidiRawMax {
            config = MidiCrossfaderConfig(channel: ch, cc: cc, rawMin: lo, rawMax: hi,
                                          invert: profileConfig.invert)
        } else {
            config = profileConfig
        }

        let source = MidiFaderSource(config: config, binarizer: binarizer)
        source.onChange = { [weak self] sample in
            self?.practiceCommandEvents.send(.faderClosed(!sample.isOpen))
        }
        try? source.start()
        crossfaderSource = source
    }

    // MARK: - MIDI de comandos

    /// Reconstruye el mapa MIDI de comandos: base del perfil activo (sección
    /// `[transport]` del `.conf`) + los overrides del usuario por encima. Se
    /// llama al arrancar y cada vez que cambian el perfil o los ajustes.
    func rebuildMidiCommandMap() {
        let base = activeProfileId
            .flatMap { profiles.profile(id: $0)?.raw }
            .map(MidiCommandMap.fromProfile) ?? MidiCommandMap()

        var overrides: [PracticeCommand: MidiBinding] = [:]
        for (key, value) in settings.midiCommandOverrides {
            if let cmd = PracticeCommand(rawValue: key), let bind = MidiBinding(value) {
                overrides[cmd] = bind
            }
        }
        midiCommands.map = base.merging(userOverrides: overrides)
    }

    /// Asignaciones MIDI que trae el perfil activo (`comando -> "note:1:36"`),
    /// para mostrarlas como valor por defecto en Ajustes.
    public var profileCommandBindings: [String: String] {
        guard let ini = activeProfileId.flatMap({ profiles.profile(id: $0)?.raw }) else { return [:] }
        var out: [String: String] = [:]
        for (cmd, bind) in MidiCommandMap.fromProfile(ini).bindings {
            out[cmd.rawValue] = bind.text
        }
        return out
    }

    // MARK: - arranque

    /// Monta el modelo real. En dev lee el contenido del repo; el empaquetado en
    /// el bundle es tarea de B12. Si algo falla, devuelve un modelo en
    /// `.error(...)` para que la ventana al menos abra y lo diga.
    public static func boot(content: ContentLoader = RepoContentLoader(),
                            databaseURL: URL? = nil) -> AppModel {
        do {
            let catalog = try CatalogLoader.load(from: content)
            let url = databaseURL ?? defaultDatabaseURL()
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let db = try XFDatabase(url: url)

            let confs = content.list("profiles", withExtension: "conf")
            let bundled: [(filename: String, text: String)] = confs.compactMap { name in
                guard let data = try? content.data("profiles/\(name)"),
                      let text = String(data: data, encoding: .utf8) else { return nil }
                return (name, text)
            }
            let profiles = ProfileStore(bundled: bundled, user: [])

            // Ajustes: se guardan en un plist local (UserDefaults); ningun dato
            // sale de la maquina. El buffer de audio se fija aqui, al crear el
            // motor (cambiarlo requiere reiniciar).
            let settings = recoverInstrumentalLibraryIfNeeded(loadSettings())
            let model = AppModel(catalog: catalog, db: db,
                                 engine: EngineHandle(maxFrames: settings.bufferFrames),
                                 profiles: profiles, settings: settings, content: content)
            model.refreshHome()
            // La app real escucha CoreMIDI desde que arranca (no solo en
            // Ajustes): así el crossfader y los comandos de la mesa funcionan
            // nada más abrir, sin un paso "activar MIDI" aparte.
            model.openMidiMonitor()
            return model
        } catch {
            return failed("\(error)")
        }
    }

    public static func failed(_ message: String) -> AppModel {
        let emptyLibrary = ScratchLibrary(schemaVersion: "0", generatedBy: "xFlare",
                                          notation: "XFN", ppq: 480, scratches: [])
        let db = (try? XFDatabase.inMemory()) ?? {
            // .inMemory() no deberia fallar nunca; si lo hace, no hay nada que hacer
            fatalError("no se puede abrir ni una base en memoria")
        }()
        let model = AppModel(
            catalog: Catalog(library: emptyLibrary, levels: [], exercises: [], variants: []),
            db: db)
        model.screen = .error(message)
        return model
    }

    // MARK: - persistencia de ajustes (fichero de texto + espejo en plist)

    private static let settingsDefaults = UserDefaults(suiteName: "app.xflare.settings")

    /// Orden de preferencia: el **fichero** `settings.json` (fuente de verdad,
    /// ver `SettingsStore`); si no lo hay, el plist viejo (y se migra al fichero);
    /// si tampoco, los valores por defecto.
    static func loadSettings() -> AppSettings {
        if let fromFile = SettingsStore.load() {
            return fromFile
        }
        if let d = settingsDefaults,
           let raw = d.dictionary(forKey: "settings") as? [String: String] {
            let migrated = AppSettings(raw: raw)
            SettingsStore.save(migrated)          // deja el fichero para la próxima
            return migrated
        }
        return .defaults
    }

    static func persist(_ s: AppSettings) {
        SettingsStore.save(s)                      // atómico, en cada cambio
        settingsDefaults?.set(s.raw, forKey: "settings")   // espejo, compatibilidad
    }

    /// Recuperación **una sola vez**: un bug de `@State` en Ajustes podía pisar
    /// `AppModel.settings` con una copia vieja y **vaciar la librería de
    /// instrumentales**. Los ficheros que se llegaron a analizar siguen en
    /// `instrumental-analysis.json`; si aún existen en disco y no están en la
    /// lista, se re-añaden. `libraryRecovered` evita repetirlo (y resucitar los
    /// que el usuario borró a propósito).
    static func recoverInstrumentalLibraryIfNeeded(_ s: AppSettings) -> AppSettings {
        guard settingsDefaults?.bool(forKey: "libraryRecovered") != true else { return s }
        settingsDefaults?.set(true, forKey: "libraryRecovered")

        let cache = InstrumentalAnalysisCache()          // carga su JSON al init
        let fm = FileManager.default
        let analyzed = cache.entries.keys.filter { fm.fileExists(atPath: $0) }
        guard !analyzed.isEmpty else { return s }

        var merged = s.instrumentalLibrary
        for p in analyzed where !merged.contains(p) { merged.append(p) }
        guard merged.count != s.instrumentalLibrary.count else { return s }

        var out = s
        out.instrumentalLibrary = merged
        persist(out)
        return out
    }

    static func defaultDatabaseURL() -> URL {
        let base = (try? FileManager.default.url(for: .applicationSupportDirectory,
                                                 in: .userDomainMask, appropriateFor: nil, create: true))
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("xFlare/xflare.sqlite")
    }

    // MARK: - navegacion

    public func goHome()          { warmupSteps = []; refreshHome(); screen = .home }
    public func openCalibration() { screen = .calibration }
    public func openLibrary()      { refreshLibrary(); screen = .library }   // "Trucos"
    public func openMediaLibrary() { screen = .mediaLibrary }
    public func openInstrumentalEditor(path: String) { screen = .instrumentalEditor(path: path) }
    public func openSampleEditor(path: String) { screen = .sampleEditor(path: path) }
    public func openMyTable()      { screen = .myTable }
    public func openSettings()    { screen = .settings }
    public func openFreeMode()    { screen = .freeMode }

    /// Filas del calentamiento de hoy (vacío si no dominas nada todavía).
    /// `internal`: `WarmupRow` no cruza el límite del módulo.
    @Published private(set) var warmup: [WarmupRow] = []

    /// Pasos del calentamiento en marcha. Vacío = no estamos calentando. Todo el
    /// calentamiento es UNA sesión: `LivePracticeView` encadena estos pasos
    /// conforme se completan las frases de "repite conmigo".
    /// `internal`: `WarmupStep` no cruza el límite del módulo.
    @Published private(set) var warmupSteps: [WarmupStep] = []

    /// Genera el plan de calentamiento **sugerido** (histórico o, sin historial,
    /// la rutina de arranque) y abre la pantalla. Desde ahí el usuario lo edita
    /// antes de empezar.
    public func openWarmup() {
        var rng = SystemRandomNumberGenerator()
        warmup = WarmupAssembler.rows(from: warmupPlan(rng: &rng), catalog: catalog)
        screen = .warmup
    }

    /// Ejercicios de la librería que se pueden **añadir** al calentamiento con el
    /// botón "+" de `WarmupView`. Todos, sin filtrar por dominio: el usuario
    /// manda sobre su propio calentamiento.
    var warmupLibrary: [WarmupPickable] {
        catalog.exercises.compactMap { ex in
            guard let sc = catalog.library.scratch(id: ex.scratchId) else { return nil }
            let fam = catalog.family(containingScratch: ex.scratchId)?.name ?? ""
            return WarmupPickable(exerciseId: ex.id, name: sc.name, familyName: fam)
        }
    }

    /// Monta la tanda entera **a partir de las filas ya editadas por el usuario**
    /// (borradas, con la duración cambiada o añadidas a mano en `WarmupView`) y
    /// abre la práctica en la primera con "repite conmigo" en marcha. A partir de
    /// ahí `LivePracticeView` avanza solo.
    /// `internal`: `WarmupRow` no cruza el límite del módulo.
    func startWarmupSession(rows: [WarmupRow]) {
        let steps: [WarmupStep] = rows.compactMap { row in
            guard let sc = scratch(exerciseId: row.exerciseId, variantId: row.variantId)
            else { return nil }
            let name = catalog.exercise(id: row.exerciseId)
                .flatMap { catalog.library.scratch(id: $0.scratchId)?.name } ?? row.exerciseId
            return WarmupStep(scratch: sc, name: name, phraseCount: max(1, row.phraseCount),
                              exerciseId: row.exerciseId, variantId: row.variantId)
        }
        guard let first = rows.first, !steps.isEmpty else { goHome(); return }
        warmupSteps = steps
        continueExerciseId = first.exerciseId
        startCallResponseBars = max(1, first.phraseBars)
        screen = .practice(exerciseId: first.exerciseId, variantId: first.variantId)
    }

    /// Compases de "repite conmigo" con los que arrancar la próxima práctica, o
    /// `nil` para no forzar call-response. Lo pone el calentamiento; la práctica
    /// lo lee al aparecer y `startPractice` lo limpia para la siguiente.
    @Published private(set) var startCallResponseBars: Int?

    public func startPractice(exerciseId: String, variantId: String = "base",
                              callResponseBars: Int? = nil) {
        warmupSteps = []          // una práctica normal no es una tanda de calentamiento
        continueExerciseId = exerciseId
        startCallResponseBars = callResponseBars
        screen = .practice(exerciseId: exerciseId, variantId: variantId)
    }

    public func openProgress(exerciseId: String, variantId: String = "base") {
        screen = .progress(exerciseId: exerciseId, variantId: variantId)
    }

    /// Desde una celda de la matriz o del navegador (recibe `scratchId`): abre la
    /// **ficha** del truco, no la práctica. Desde la ficha se pulsa "Practicar".
    public func selectScratch(_ scratchId: String) {
        // acepta un scratchId real o un id de familia ("flare", "transformer")
        guard catalog.library.scratch(id: scratchId) != nil
                || catalog.family(id: scratchId) != nil else { return }
        screen = .exerciseDetail(scratchId: scratchId)
    }

    // MARK: - datos para las pantallas

    public func refreshHome() {
        home = try? HomeAssembler.summary(
            catalog: catalog, db: db,
            continueExerciseId: continueExerciseId,
            streakDays: currentStreakDays(), minutesToday: minutesPracticedToday(),
            allUnlocked: settings.allUnlocked)
    }

    public func refreshLibrary() {
        library = try? LibraryAssembler.browser(
            catalog: catalog, db: db, allUnlocked: settings.allUnlocked)
    }

    public func variantOptions(exerciseId: String) -> [VariantOption] {
        (try? VariantAssembler.options(catalog: catalog, exerciseId: exerciseId, db: db,
                                       allUnlocked: settings.allUnlocked)) ?? []
    }

    /// Ficha de detalle de un truco para la pantalla `.exerciseDetail`.
    public func exerciseDetail(scratchId: String) -> ExerciseDetailDisplay? {
        (try? ExerciseDetailAssembler.display(catalog: catalog, db: db, scratchId: scratchId,
                                              allUnlocked: settings.allUnlocked)) ?? nil
    }

    public func progressDisplay(exerciseId: String, variantId: String) -> ExerciseProgressDisplay? {
        guard let s = try? db.progressSummary(exerciseId: exerciseId, variantId: variantId) else {
            return nil
        }
        return ExerciseProgressDisplay.build(s)
    }

    public func myTable() -> MyTable {
        let rows = profiles.entries.values.compactMap { entry -> (profile: DeviceProfile, isUser: Bool)? in
            guard !entry.isExample, let p = entry.profile else { return nil }
            return (p, entry.origin == .user)
        }
        let cals = (try? db.allCalibrations()) ?? []
        return MyTableAssembler.table(profiles: rows, calibrations: cals,
                                      activeProfileId: activeProfileId)
    }

    /// El `Scratch` a practicar, con la **variante** ya aplicada sobre el patrón
    /// base (offset / amplitude / mirror / swing / subdivision). `dropout`
    /// (blind) no toca el patrón: es cosa de la sesión. Si la recomposición
    /// falla (dato malo), se practica la base.
    public func scratch(exerciseId: String, variantId: String = "base") -> Scratch? {
        guard let ex = catalog.exercise(id: exerciseId),
              let base = catalog.library.scratch(id: ex.scratchId) else { return nil }
        guard let v = catalog.variant(id: variantId), !v.isBase else { return base }

        switch v.transform {
        case .identity, .dropout:
            return base
        case .amplitude(let scale):
            return base.withAmplitude(scale: scale)
        case .mirror:
            return base.mirrored()
        case .swing(let ratio):
            return base.withSwing(ratio: ratio, ppq: base.ppq)
        case .subdivision(let div):
            return (try? Composer.composeWithSubdivision(
                base, to: div, ppq: base.ppq, primitives: catalog.primitives)) ?? base
        case .offset(let fraction):
            return (try? Composer.composeWithOffset(
                hand: base.hand, fader: base.fader, division: base.div, cycles: base.cycles,
                fraction: fraction, ppq: base.ppq, primitives: catalog.primitives)) ?? base
        }
    }

    // MARK: - resultado de una practica

    /// Asienta una toma (persistencia + progreso + desbloqueos) y va a la
    /// pantalla de resultados.
    public func finishPractice(attempt: Attempt, events: [AttemptEvent],
                               starReasons: [String], diagnostics: [String]) {
        let previousBest = (try? db.progress(exerciseId: attempt.exerciseId,
                                             variantId: attempt.variantId)?.bestScore) ?? nil
        _ = try? AttemptRecorder.record(attempt, events: events, db: db, catalog: catalog)

        lastResults = ResultsSummary.build(
            score: attempt.score, maxScore: attempt.maxScore, starCount: attempt.stars,
            starReasons: starReasons, diagnostics: diagnostics,
            isBestScore: attempt.score > (previousBest ?? -1))
        refreshHome()
        screen = .results
    }

    // MARK: - puntuar una toma grabada (practica rudimentaria)

    /// Puntua una toma (`.xfsession` grabado en la practica) contra su patron con
    /// `XFAnalysis` y va a la pantalla de resultados con el diagnostico
    /// accionable. **No persiste** ni mueve estrellas / progreso: la practica
    /// rudimentaria todavia no es una sesion de verdad (sin cuenta atras ni
    /// series, eso es XFEngine). Es "enseñar, no puntuar" sin el ciclo completo.
    public func scoreTake(_ session: XFSession, exerciseId: String, variantId: String) {
        guard let scratch = scratch(exerciseId: exerciseId, variantId: variantId) else { return }
        let take = Take(motion: session.motion, fader: session.fader, clock: session.clockMap)
        let takeBpm = Int(session.header.tempoBPM.rounded())
        let atTarget = takeBpm == (catalog.exercise(id: exerciseId)?.startBpm ?? takeBpm)
        let report = DefaultScorer().score(take, against: scratch, atTargetBpm: atTarget)

        lastResults = ResultsSummary.build(report: report, isBestScore: false)
        screen = .results
    }

    /// Igual que `scoreTake` pero para una toma hecha **dentro del calentamiento**
    /// (F.0): la puntúa con `XFAnalysis`, la asienta como toma de calentamiento
    /// (`settleWarmupTake` → `mode:.warmup`, no cuenta para estrellas, alimenta la
    /// repetición espaciada y marca oxidación si baja de 2★) y **devuelve** el
    /// resultado para enseñarlo EN LA PROPIA práctica, sin navegar a `.results`:
    /// así la tanda de calentamiento no se corta.
    struct WarmupTakeResult: Equatable {
        var stars: Int
        var accuracyPercent: Int
        /// Aviso de oxidación ("el crab se te está cayendo…") o `nil`.
        var oxidationMessage: String?
    }

    func scoreWarmupTake(_ session: XFSession,
                         exerciseId: String, variantId: String) -> WarmupTakeResult? {
        guard let scratch = scratch(exerciseId: exerciseId, variantId: variantId) else { return nil }
        let take = Take(motion: session.motion, fader: session.fader, clock: session.clockMap)
        let takeBpm = Int(session.header.tempoBPM.rounded())
        let atTarget = takeBpm == (catalog.exercise(id: exerciseId)?.startBpm ?? takeBpm)
        let report = DefaultScorer().score(take, against: scratch, atTargetBpm: atTarget)

        let message = settleWarmupTake(
            exerciseId: exerciseId, variantId: variantId,
            score: report.score, maxScore: report.maxScore, stars: report.stars,
            sigmaMs: report.sigmaMs, biasMs: report.biasMs)

        return WarmupTakeResult(stars: report.stars,
                                accuracyPercent: Int((report.accuracy * 100).rounded()),
                                oxidationMessage: message)
    }

    // MARK: - calentamiento adaptativo (F.0 / ADR-027)

    /// El plan de calentamiento de hoy: 4-6 ejercicios **dominados**, cada uno
    /// con una variante desbloqueada al azar distinta a la de la última vez.
    /// Puro por debajo (`WarmupPlanner`); aquí solo se leen los datos de la BD.
    func warmupPlan(now: Date = Date(),
                    rng: inout some RandomNumberGenerator) -> [WarmupPlanner.PlannedItem] {
        let mastered = (try? db.masteredExercises()) ?? []
        let candidates: [WarmupPlanner.Candidate] = mastered.compactMap { id in
            guard let ex = catalog.exercise(id: id),
                  let base = catalog.library.scratch(id: ex.scratchId) else { return nil }
            let maxScore = Double(max(1, ScoreEvents(of: base).maxScore))

            let ceiling = ((try? db.progress(exerciseId: id, variantId: "base")) ?? nil)?
                .bestScore.map { Double($0) / maxScore }

            let recent = ((try? db.attempts(exerciseId: id, variantId: "base", limit: 6)) ?? [])
                .filter { $0.countsForStars }
            let recentAvg: Double? = recent.isEmpty ? nil
                : recent.map(\.accuracy).reduce(0, +) / Double(recent.count)

            let lastWarmup = ((try? db.attempts(exerciseId: id, limit: 16)) ?? [])
                .first { $0.mode == .warmup }?.variantId

            let review = (try? db.reviewItem(exerciseId: id, variantId: "base")) ?? nil
            let lastAt = review?.lastReviewedAt
                ?? ((try? db.progress(exerciseId: id, variantId: "base")) ?? nil)?.lastAttemptAt
            let daysSince = lastAt.map { now.timeIntervalSince($0) / 86_400 } ?? 30

            let masteredAt = ((try? db.mastery(exerciseId: id)) ?? nil)?.masteredAt
            let masteryAge = masteredAt.map { now.timeIntervalSince($0) / 86_400 } ?? 30

            let unlocked = Array((try? db.unlockedVariants(exerciseId: id)) ?? ["base"])
            return WarmupPlanner.Candidate(
                exerciseId: id, name: base.name,
                familyId: catalog.family(containingScratch: ex.scratchId)?.id,
                daysSinceReview: daysSince, recentAverage: recentAvg,
                ceiling: ceiling, masteryAgeDays: masteryAge,
                unlockedVariants: unlocked.isEmpty ? ["base"] : unlocked,
                lastWarmupVariant: lastWarmup)
        }
        let adaptive = WarmupPlanner.plan(candidates, rng: &rng)
        // Sin historial (nada dominado): rutina de arranque fija en vez de una
        // pantalla vacía — Forward Cut, Reverse Cut, Chirp, Transformer, cada
        // uno 8 frases de 2 compases (F.0, feedback 2026-09-03).
        return adaptive.isEmpty ? WarmupAssembler.starterPlan(catalog: catalog) : adaptive
    }

    /// Asienta una toma de **calentamiento**: la registra (no cuenta para
    /// estrellas, ADR-027), alimenta la repetición espaciada y, si ha bajado de
    /// 2★, marca el ejercicio **oxidado** y devuelve el aviso para la UI.
    @discardableResult
    func settleWarmupTake(exerciseId: String, variantId: String,
                          score: Int, maxScore: Int, stars: Int,
                          sigmaMs: Double? = nil, biasMs: Double? = nil,
                          at date: Date = Date()) -> String? {
        let name = catalog.exercise(id: exerciseId)
            .flatMap { catalog.library.scratch(id: $0.scratchId)?.name } ?? exerciseId
        let acc = maxScore > 0 ? Double(score) / Double(maxScore) : 0
        let prior = (((try? db.progressSummary(exerciseId: exerciseId, variantId: "base")) ?? nil)?
            .averageOfLast5).map { $0 / Double(max(1, maxScore)) }

        let attempt = Attempt(id: UUID().uuidString, exerciseId: exerciseId,
                              variantId: variantId, mode: .warmup, bpm: 0, startedAt: date,
                              score: score, maxScore: maxScore, accuracy: acc, stars: stars,
                              sigmaMs: sigmaMs, biasMs: biasMs, countsForStars: false)
        try? db.saveAttempt(attempt)
        _ = try? db.recordReviewOutcome(exerciseId: exerciseId, variantId: "base",
                                        passed: stars >= 2, at: date)

        let ox = WarmupOxidation.check(exerciseName: name, starsInWarmup: stars,
                                       accuracy: acc, priorAverage: prior)
        if ox.oxidized { try? db.setOxidized(exerciseId: exerciseId, at: date) }
        refreshHome()
        return ox.message
    }

    // MARK: - racha / minutos (desde los intentos guardados)

    private func allAttemptDates() -> [Date] {
        catalog.exercises.flatMap { (try? db.attempts(exerciseId: $0.id)) ?? [] }
            .map(\.startedAt)
    }

    public func currentStreakDays() -> Int {
        PracticeStreak.currentStreak(practiceDates: allAttemptDates())
    }

    public func minutesPracticedToday() -> Int {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let ms = catalog.exercises
            .flatMap { (try? db.attempts(exerciseId: $0.id)) ?? [] }
            .filter { cal.isDate($0.startedAt, inSameDayAs: today) }
            .compactMap(\.durationMs)
            .reduce(0, +)
        return Int(ms / 60_000)
    }
}
