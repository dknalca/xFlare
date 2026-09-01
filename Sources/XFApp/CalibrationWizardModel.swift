// SPDX-License-Identifier: GPL-3.0-only

import Foundation
import Combine
import XFPersistence

/// El estado del asistente de calibración de 4 pasos (`docs/UI_DESIGN.md` §3.1).
///
/// **No mide nada**: la capa de audio (bloque B1/B4, hardware) le va contando lo
/// que detecta con `reportLatency` / `reportTimecode` / `reportFaderCut`, y el
/// modelo decide cuándo cada paso está listo y qué `DeviceCalibration` sale al
/// final. Así el flujo se testea sin hardware.
///
/// `ObservableObject` + `@Published` (no `@Observable`, que es macOS 14 —
/// `docs/PLATFORM_SUPPORT.md` §4).
public final class CalibrationWizardModel: ObservableObject {

    @Published public private(set) var step: CalibrationStep = .audio

    // MARK: paso 1 · audio
    @Published public var inputDeviceName: String?
    @Published public var outputDeviceName: String?
    @Published public var bufferFrames: Int = 64

    // MARK: paso 2 · latencia
    @Published public private(set) var measuredLatencyMs: Double?

    // MARK: paso 3 · timecode
    @Published public private(set) var signalConfidence: Double = 0
    @Published public private(set) var detectedForwards: Bool = true
    /// La autodetección la propone; el usuario la confirma o la cambia.
    @Published public var hamster: Bool = false

    // MARK: paso 4 · fader
    @Published public private(set) var cutsDetected: Int = 0
    @Published public var faderCutIn: Double = 0.5
    @Published public var faderHysteresis: Double = 0.08

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

    public func reportLatency(roundTripMs: Double) {
        measuredLatencyMs = roundTripMs
    }

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

    // MARK: - navegación

    /// `true` si el paso `s` tiene lo mínimo para pasar al siguiente.
    public func isReady(_ s: CalibrationStep) -> Bool {
        switch s {
        case .audio:    return inputDeviceName != nil && outputDeviceName != nil
        case .latency:  return measuredLatencyMs != nil   // el semáforo avisa; no bloquea
        case .timecode: return signalConfidence >= timecodeConfidenceGate
        case .fader:    return cutsDetected >= faderCutsNeeded
        }
    }

    public var canAdvance: Bool { isReady(step) }

    public var latencyVerdict: LatencyVerdict? {
        measuredLatencyMs.map(LatencyVerdict.init(roundTripMs:))
    }

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
            latencyMs: measuredLatencyMs,
            updatedAt: now)
    }
}
