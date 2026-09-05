// SPDX-License-Identifier: GPL-3.0-only
//
// Los tres paneles del asistente de calibración (`docs/UI_DESIGN.md` §3.1).
// Son `internal`: solo los usa `CalibrationWizardView`. Toda la lógica está en
// `CalibrationWizardModel`; esto solo la dibuja.

import SwiftUI
import XFDesign
import XFRender

// MARK: - 1 · Audio

struct AudioCalibrationStep: View {
    @ObservedObject var model: CalibrationWizardModel
    let inputDevices: [AudioDeviceList.Device]
    let outputDevices: [AudioDeviceList.Device]

    var body: some View {
        XFCard {
            VStack(alignment: .leading, spacing: XFSpacing.md) {
                devicePicker("Entrada (timecode)", devices: inputDevices,
                             selection: $model.inputDeviceName)
                if let inDevice = inputDevices.first(where: { $0.name == model.inputDeviceName }) {
                    let pairs = AudioDeviceList.inputChannelPairs(for: inDevice)
                    if pairs.count > 1 {
                        channelPicker("Canal del timecode", pairs: pairs,
                                     selection: $model.inputChannelFirst)
                    }
                }
                devicePicker("Salida", devices: outputDevices,
                             selection: $model.outputDeviceName)
                if let outDevice = outputDevices.first(where: { $0.name == model.outputDeviceName }) {
                    let pairs = AudioDeviceList.outputChannelPairs(for: outDevice)
                    if pairs.count > 1 {
                        channelPicker("Canal de salida", pairs: pairs,
                                     selection: $model.outputChannelFirst)
                        // F.68 (ADR-075): mismo dispositivo, un PAR distinto
                        // para la base — dos tiras de mezclador separadas en
                        // vez de una mezcla combinada. Necesita al menos dos
                        // pares para tener sentido (si no, no hay "distinto"
                        // que elegir).
                        instrumentalChannelPicker(pairs: pairs)
                    }
                }
                HStack {
                    Text("Buffer").foregroundColor(XFColor.textMuted)
                    Picker("", selection: $model.bufferFrames) {
                        Text("64 frames").tag(64)
                        Text("128 frames").tag(128)
                    }
                    .labelsHidden()
                    .frame(width: 160)
                }
                Text("64 frames = 1,33 ms a 48 kHz. Sube a 128 si oyes cortes.")
                    .font(XFFont.body(12)).foregroundColor(XFColor.textMuted)
                if inputDevices.first(where: { $0.name == model.inputDeviceName })
                    .map({ AudioDeviceList.inputChannelPairs(for: $0).count > 1 }) == true {
                    Text("En una interfaz multicanal el canal 1 casi nunca es el que lleva el "
                         + "timecode — elige la pareja correcta arriba en vez de a ciegas.")
                        .font(XFFont.body(11)).foregroundColor(XFColor.textMuted)
                }
            }
        }
    }

    private func devicePicker(_ title: String, devices: [AudioDeviceList.Device],
                              selection: Binding<String?>) -> some View {
        HStack {
            Text(title).foregroundColor(XFColor.textMuted).frame(width: 160, alignment: .leading)
            Picker("", selection: selection) {
                Text("— elige —").tag(String?.none)
                ForEach(devices) { d in Text(d.name).tag(String?.some(d.name)) }
            }
            .labelsHidden()
        }
    }

    /// F.68 (ADR-075): a diferencia de `channelPicker` (siempre un par real),
    /// aquí `nil` es una opción explícita — "Combinado" (con el scratch), el
    /// comportamiento de siempre — así que necesita su propio picker con esa
    /// opción de más.
    private func instrumentalChannelPicker(pairs: [AudioDeviceList.ChannelPair]) -> some View {
        HStack {
            Text("Canal de la instrumental").foregroundColor(XFColor.textMuted)
                .frame(width: 160, alignment: .leading)
            Picker("", selection: $model.instrumentalOutputChannelFirst) {
                Text("Combinado (con el scratch)").tag(Int?.none)
                ForEach(pairs) { p in Text(p.label).tag(Int?.some(p.first)) }
            }
            .labelsHidden()
        }
    }

    private func channelPicker(_ title: String, pairs: [AudioDeviceList.ChannelPair],
                               selection: Binding<Int?>) -> some View {
        HStack {
            Text(title).foregroundColor(XFColor.textMuted).frame(width: 160, alignment: .leading)
            Picker("", selection: selection) {
                ForEach(pairs) { p in Text(p.label).tag(Int?.some(p.first)) }
            }
            .labelsHidden()
        }
    }
}

// MARK: - 2 · Timecode

struct TimecodeCalibrationStep: View {
    @ObservedObject var model: CalibrationWizardModel
    let scopeReadings: () -> [ScopeReading]

    var body: some View {
        XFCard {
            HStack(alignment: .top, spacing: XFSpacing.lg) {
                ScopeView(geometry: ScopeGeometry(size: CGSize(width: 160, height: 160)),
                          readings: scopeReadings)
                    .frame(width: 160, height: 160)
                    .clipShape(RoundedRectangle(cornerRadius: XFRadius.card))

                VStack(alignment: .leading, spacing: XFSpacing.sm) {
                    Text("Calidad de señal").foregroundColor(XFColor.textMuted)
                    ProgressView(value: model.signalConfidence)
                        .frame(width: 220)
                    Text(model.signalConfidence >= model.timecodeConfidenceGate
                         ? "Señal buena." : "Gira el plato; la aguja tiene que enganchar.")
                        .font(XFFont.body(12)).foregroundColor(XFColor.textMuted)

                    Divider().background(XFColor.stroke)

                    Text("Dirección detectada: \(model.detectedForwards ? "adelante" : "hacia atrás")")
                        .font(XFFont.body(13))
                    Toggle("Corto en reverse (hamster)", isOn: $model.hamster)
                        .toggleStyle(.checkbox)

                    Text("Vinilo Serato (2ª ed.). Otros formatos (Traktor, MixVibes) — pendiente.")
                        .font(XFFont.body(10)).foregroundColor(XFColor.textMuted)
                }
            }
        }
    }
}

// MARK: - 3 · Fader

struct FaderCalibrationStep: View {
    @ObservedObject var model: CalibrationWizardModel
    /// F.67: arma/lee el tráfico MIDI real mientras el usuario mueve el
    /// crossfader de tope a tope, para descubrir qué CC/canal es sin tener
    /// que asumir lo que declare el perfil (que puede no existir, o estar
    /// mal — B5.5 ya enseñó a no fiarse del papel).
    let onStartLearn: () -> Void
    let onFinishLearn: () -> Void

    var body: some View {
        XFCard {
            VStack(alignment: .leading, spacing: XFSpacing.md) {
                faderLearnSection

                HStack(spacing: XFSpacing.sm) {
                    Text("\(min(model.cutsDetected, model.faderCutsNeeded)) / \(model.faderCutsNeeded) cortes")
                        .font(XFFont.mono(22))
                    if model.cutsDetected > 0 {
                        Button("Reiniciar cortes") { model.resetFaderCuts() }
                            .xfButton(.bordered)
                    }
                }

                slider("Punto de corte", value: $model.faderCutIn, range: 0...1)
                slider("Histéresis", value: $model.faderHysteresis, range: 0...0.3)

                Text("Los cortes calibran el punto donde empieza a oírse. Puedes afinarlo a mano.")
                    .font(XFFont.body(12)).foregroundColor(XFColor.textMuted)
            }
        }
    }

    @ViewBuilder private var faderLearnSection: some View {
        VStack(alignment: .leading, spacing: XFSpacing.xs) {
            if model.faderLearning {
                HStack(spacing: XFSpacing.sm) {
                    ProgressView(value: min(1, Double(model.faderLearnSpan) / 127))
                        .frame(width: 160)
                    Text("rango \(model.faderLearnSpan) / 127")
                        .font(XFFont.mono(12)).foregroundColor(XFColor.textMuted)
                    Button("Listo") { onFinishLearn() }.xfButton(.filled)
                }
                Text("Mueve el crossfader de tope a tope varias veces.")
                    .font(XFFont.body(12)).foregroundColor(XFColor.textMuted)
            } else {
                HStack(spacing: XFSpacing.sm) {
                    Button("Aprender MIDI del fader") { onStartLearn() }.xfButton(.bordered)
                    if let cc = model.learnedFaderCC, let ch = model.learnedFaderChannel {
                        Text("aprendido: CC \(cc) · canal \(ch)")
                            .font(XFFont.body(12)).foregroundColor(XFColor.textMuted)
                    } else {
                        Text("sin aprender — usa el CC del perfil, si lo declara")
                            .font(XFFont.body(12)).foregroundColor(XFColor.textMuted)
                    }
                }
            }
            Divider().background(XFColor.stroke)
        }
    }

    private func slider(_ title: String, value: Binding<Double>,
                        range: ClosedRange<Double>) -> some View {
        HStack {
            Text(title).foregroundColor(XFColor.textMuted).frame(width: 140, alignment: .leading)
            Slider(value: value, in: range)
            Text(String(format: "%.2f", value.wrappedValue)).font(XFFont.mono(12)).frame(width: 44)
        }
    }
}
