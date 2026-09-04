// SPDX-License-Identifier: GPL-3.0-only

import SwiftUI
import XFDesign
import XFRender
import XFPersistence

/// El asistente de calibración de 4 pasos (`docs/UI_DESIGN.md` §3.1). La pantalla
/// más importante: si esto sale mal, todo lo demás miente.
///
/// El estado vive en `CalibrationWizardModel` (testeable). Esta vista solo lo
/// dibuja y conecta los botones. Las listas de dispositivos, la medición de
/// latencia y las lecturas del scope las aporta `XFApp` cuando cablee el audio.
public struct CalibrationWizardView: View {

    @ObservedObject private var model: CalibrationWizardModel

    private let inputDevices: [String]
    private let outputDevices: [String]
    private let onMeasureLatency: () -> Void
    private let scopeReadings: () -> [ScopeReading]
    private let onFinish: (DeviceCalibration) -> Void

    public init(model: CalibrationWizardModel,
                inputDevices: [String] = [],
                outputDevices: [String] = [],
                onMeasureLatency: @escaping () -> Void = {},
                scopeReadings: @escaping () -> [ScopeReading] = { [] },
                onFinish: @escaping (DeviceCalibration) -> Void = { _ in }) {
        self.model = model
        self.inputDevices = inputDevices
        self.outputDevices = outputDevices
        self.onMeasureLatency = onMeasureLatency
        self.scopeReadings = scopeReadings
        self.onFinish = onFinish
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: XFSpacing.lg) {
            stepIndicator

            VStack(alignment: .leading, spacing: XFSpacing.sm) {
                Text(model.step.title).font(XFFont.title(22))
                Text(model.step.instruction).foregroundColor(XFColor.textMuted)
                // Honesto en vez de un control que se queda mudo: mientras el
                // paso no tenga el motor real conectado, lo dice y apunta a
                // la herramienta de docs/HW_BRINGUP.md que sí mide hoy.
                if let note = model.step.pendingNote {
                    Text(note).font(XFFont.body(12)).foregroundColor(Color(hex: 0xF5C542))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            currentStep
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            navigation
        }
        .padding(XFSpacing.xl)
        .frame(minWidth: 640, minHeight: 480)
        .background(XFColor.bg)
    }

    private var stepIndicator: some View {
        HStack(spacing: XFSpacing.sm) {
            ForEach(CalibrationStep.allCases, id: \.rawValue) { s in
                let done = model.isReady(s)
                let current = s == model.step
                HStack(spacing: XFSpacing.xs) {
                    Text("\(s.number)")
                        .font(XFFont.mono(13))
                        .frame(width: 22, height: 22)
                        .background(Circle().fill(current ? XFColor.accent : XFColor.surfaceRaised))
                        .foregroundColor(current ? XFColor.bg : (done ? XFColor.accent : XFColor.textMuted))
                    Text(s.title)
                        .font(XFFont.body(13))
                        .foregroundColor(current ? XFColor.text : XFColor.textMuted)
                }
                if s != CalibrationStep.allCases.last {
                    Rectangle().fill(XFColor.stroke).frame(height: 1).frame(maxWidth: 40)
                }
            }
        }
    }

    @ViewBuilder private var currentStep: some View {
        switch model.step {
        case .audio:
            AudioCalibrationStep(model: model, inputDevices: inputDevices, outputDevices: outputDevices)
        case .latency:
            LatencyCalibrationStep(model: model, onMeasure: onMeasureLatency)
        case .timecode:
            TimecodeCalibrationStep(model: model, scopeReadings: scopeReadings)
        case .fader:
            FaderCalibrationStep(model: model)
        }
    }

    private var navigation: some View {
        HStack {
            Button("Atrás") { model.back() }
                .xfButton(.bordered)
                .disabled(model.step == .audio)

            Spacer()

            if model.step == .fader {
                Button("Terminar") {
                    if let result = model.result() { onFinish(result) }
                }
                .xfButton(.filled)
                .disabled(!model.isComplete)
            } else {
                Button("Siguiente") { model.advance() }
                    .xfButton(.filled)
                    .disabled(!model.canAdvance)
            }
        }
    }
}
