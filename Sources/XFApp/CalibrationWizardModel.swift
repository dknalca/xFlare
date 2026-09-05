// SPDX-License-Identifier: GPL-3.0-only

import Foundation
import Combine
import XFPersistence

/// El estado del asistente de calibración de 3 pasos (`docs/UI_DESIGN.md` §3.1).
///
/// **No mide nada**: la capa de audio (bloque B1/B4, hardware) le va contando lo
/// que detecta con `reportTimecode` / `reportFaderCut`, y el modelo decide
/// cuándo cada paso está listo y qué `DeviceCalibration` sale al final. Así
/// el flujo se testea sin hardware.
///
/// `ObservableObject` + `@Published` (no `@Observable`, que es macOS 14 —
/// `docs/PLATFORM_SUPPORT.md` §4).
public final class CalibrationWizardModel: ObservableObject {

    @Published public private(set) var step: CalibrationStep = .audio

    // MARK: paso 1 · audio
    @Published public var inputDeviceName: String?
    @Published public var outputDeviceName: String?
    /// Primer canal (1-based) del PAR estéreo elegido dentro del dispositivo de
    /// entrada — en una interfaz multicanal (la Rane 72: 14 in) el dispositivo
    /// no basta, hace falta decir cuál de los 7 pares lleva el timecode
    /// (B5.5/B1.2, 2026-09-04: la señal real estaba en "Analog 1", no en el
    /// canal que la mesa llama "Deck 1"). `nil` hasta que `AppRootView`
    /// resuelve el primer par disponible del dispositivo elegido.
    @Published public var inputChannelFirst: Int?
    /// Igual que `inputChannelFirst` pero de SALIDA.
    @Published public var outputChannelFirst: Int?
    /// Par estéreo de salida de la BASE INSTRUMENTAL (+ metrónomo), si es
    /// DISTINTO de `outputChannelFirst` (F.68, ADR-075): dos tiras de
    /// mezclador separadas para scratch y base, en vez de un único par
    /// combinado. `nil` = combinado (mismo par que el scratch) — el
    /// comportamiento de siempre. Mismo campo que `AppSettings.
    /// instrumentalOutputChannel`, aquí solo para el paso 1 del asistente.
    @Published public var instrumentalOutputChannelFirst: Int?
    @Published public var bufferFrames: Int = 64

    // MARK: paso 2 · timecode
    @Published public private(set) var signalConfidence: Double = 0
    @Published public private(set) var detectedForwards: Bool = true
    /// La autodetección la propone; el usuario la confirma o la cambia.
    @Published public var hamster: Bool = false

    // MARK: paso 3 · fader
    /// F.80 — estado EN VIVO del fader real (abierto/cerrado), para dibujarlo
    /// en el paso mientras se calibra. Antes de esto el paso solo mostraba
    /// el contador de cortes, que salta en incrementos — sin nada que
    /// reaccione al segundo con el movimiento del crossfader, el autor lo
    /// reportó como "no dibuja cuando el crossfader corta". Arranca abierto
    /// (mismo criterio que `PracticeSession.faderClosed = false` al inicio).
    @Published public private(set) var faderIsOpen = true
    @Published public private(set) var cutsDetected: Int = 0
    @Published public var faderCutIn: Double = 0.5
    @Published public var faderHysteresis: Double = 0.08
    /// `true` mientras se espera que el usuario mueva el crossfader de tope a
    /// tope para descubrir qué CC/canal es (F.67) — lo activa el botón
    /// "Aprender MIDI del fader". No todas las mesas declaran esto en su
    /// perfil, y aunque lo declaren puede estar mal (hay que confiar en lo
    /// que la mesa manda de verdad, no en el papel — B5.5 ya enseñó esa
    /// lección con los canales de audio).
    @Published public private(set) var faderLearning = false
    /// Cuánto ha barrido hasta ahora el candidato que más se mueve, mientras
    /// `faderLearning` está activo (`MidiFaderLearner.bestSpanSoFar`,
    /// `XFCapture`) — feedback en vivo de "sigue moviendo, todavía no llega".
    @Published public private(set) var faderLearnSpan: Int = 0
    /// Canal MIDI (1-16) del crossfader aprendido, o `nil` si todavía no se
    /// ha aprendido (el paso usa entonces el `cc`/canal del perfil, si los
    /// declara).
    @Published public private(set) var learnedFaderChannel: Int?
    @Published public private(set) var learnedFaderCC: Int?
    @Published public private(set) var learnedFaderMin: Int?
    @Published public private(set) var learnedFaderMax: Int?

    /// Identificador estable del dispositivo (UID de audio o puerto MIDI) y perfil
    /// de `XFProfiles` con el que se guarda la calibración.
    public var deviceKey: String
    public var profileId: String

    /// Confianza de señal a partir de la cual el paso de timecode se da por bueno.
    public var timecodeConfidenceGate = 0.6
    /// Cortes que hay que encadenar en el paso de fader.
    public var faderCutsNeeded = 10

    public init(deviceKey: String = "", profileId: String = "generic-midi") {
        self.deviceKey = deviceKey
        self.profileId = profileId
    }

    // MARK: - lo que reporta la capa de audio

    public func reportTimecode(confidence: Double, forwards: Bool, suggestedHamster: Bool) {
        signalConfidence = min(1, max(0, confidence))
        detectedForwards = forwards
        hamster = suggestedHamster
    }

    /// Un corte detectado, con la estimación de cut-in / histéresis hasta ahora.
    public func reportFaderCut(cutIn: Double, hysteresis: Double) {
        cutsDetected += 1
        faderCutIn = min(1, max(0, cutIn))
        faderHysteresis = max(0, hysteresis)
    }

    /// F.80 — estado en vivo del fader (llega con CADA mensaje MIDI del
    /// crossfader, no solo cuando cambia): a diferencia de `reportFaderCut`
    /// (un evento discreto, puntuable), esto es solo para dibujar.
    public func reportFaderState(isOpen: Bool) {
        if faderIsOpen != isOpen { faderIsOpen = isOpen }
    }

    /// Botón "Reiniciar cortes": vuelve a 0 sin tocar `faderCutIn`/
    /// `faderHysteresis` (los sliders no se mueven solos) — para repetir los
    /// diez cortes con un ajuste distinto sin salir del paso.
    public func resetFaderCuts() {
        cutsDetected = 0
    }

    // MARK: - aprender MIDI del fader (F.67)

    public func startFaderLearn() {
        faderLearning = true
        faderLearnSpan = 0
    }

    /// `AppRootView` llama a esto en cada mensaje MIDI mientras se aprende,
    /// con `MidiFaderLearner.bestSpanSoFar` — solo para la barra de progreso.
    public func reportFaderLearnProgress(span: Int) {
        faderLearnSpan = span
    }

    /// Aprendizaje terminado con éxito: `AppRootView` ya resolvió qué
    /// `(canal, cc, rango)` es el que más se movió mientras se escuchaba
    /// (`MidiFaderLearner.bestGuess`). Reinicia los cortes contados: los que
    /// se hicieron antes de aprender pudieron ir contra el CC equivocado.
    public func reportLearnedFader(channel: Int, cc: Int, rawMin: Int, rawMax: Int) {
        learnedFaderChannel = channel
        learnedFaderCC = cc
        learnedFaderMin = rawMin
        learnedFaderMax = rawMax
        faderLearning = false
        cutsDetected = 0
    }

    /// Se paró sin encontrar nada fiable (rango insuficiente): no se pisa lo
    /// que ya hubiera aprendido antes.
    public func cancelFaderLearn() {
        faderLearning = false
    }

    // MARK: - precarga de una calibración guardada (F.72, ADR-077)

    /// `AppRootView` llama a esto UNA vez por dispositivo resuelto (no en
    /// cada redibujado — pisaría un ajuste que el usuario esté tocando ahora
    /// mismo): trae el punto de corte, la histéresis, el hamster y el CC MIDI
    /// aprendido de la ÚLTIMA calibración guardada para esta mesa, en vez de
    /// empezar de los valores de fábrica cada vez que se abre el asistente.
    public func applyLoaded(_ cal: DeviceCalibration) {
        faderCutIn = min(1, max(0, cal.faderCutIn))
        faderHysteresis = max(0, cal.faderHysteresis)
        hamster = cal.hamster
        if let ch = cal.faderMidiChannel, let cc = cal.faderMidiCC,
           let lo = cal.faderMidiRawMin, let hi = cal.faderMidiRawMax {
            reportLearnedFader(channel: ch, cc: cc, rawMin: lo, rawMax: hi)
        }
    }

    // MARK: - navegación

    /// `true` si el paso `s` tiene lo mínimo para pasar al siguiente.
    public func isReady(_ s: CalibrationStep) -> Bool {
        switch s {
        case .audio:    return inputDeviceName != nil && outputDeviceName != nil
        case .timecode: return signalConfidence >= timecodeConfidenceGate
        case .fader:    return cutsDetected >= faderCutsNeeded
        }
    }

    public var canAdvance: Bool { isReady(step) }

    public func advance() {
        guard canAdvance, let next = CalibrationStep(rawValue: step.rawValue + 1) else { return }
        step = next
    }

    public func back() {
        guard let prev = CalibrationStep(rawValue: step.rawValue - 1) else { return }
        step = prev
    }

    // MARK: - resultado

    public var isComplete: Bool { CalibrationStep.allCases.allSatisfy(isReady) }

    /// La calibración lista para `XFPersistence`, o `nil` si falta algún paso.
    public func result(now: Date = Date()) -> DeviceCalibration? {
        guard isComplete else { return nil }
        return DeviceCalibration(
            deviceKey: deviceKey.isEmpty ? (outputDeviceName ?? "unknown-device") : deviceKey,
            profileId: profileId,
            faderCutIn: faderCutIn,
            faderHysteresis: faderHysteresis,
            hamster: hamster,
            // F.72 (ADR-077): el CC/canal APRENDIDO (F.67), si lo hay, para que
            // sobreviva a la sesión de calibración -- `nil` si nunca se aprendió
            // (el perfil sigue siendo el fallback en `rebuildCrossfaderSource`).
            faderMidiChannel: learnedFaderChannel, faderMidiCC: learnedFaderCC,
            faderMidiRawMin: learnedFaderMin, faderMidiRawMax: learnedFaderMax,
            updatedAt: now)
    }
}
