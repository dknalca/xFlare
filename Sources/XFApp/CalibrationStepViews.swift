// SPDX-License-Identifier: GPL-3.0-only
//
// Los cuatro paneles del asistente de calibración (`docs/UI_DESIGN.md` §3.1).
// Son `internal`: solo los usa `CalibrationWizardView`. Toda la lógica está en
// `CalibrationWizardModel`; esto solo la dibuja.

import SwiftUI
import XFDesign
import XFRender

// MARK: - 1 · Audio

struct AudioCalibrationStep: View {
    @ObservedObject var model: CalibrationWizardModel
    let inputDevices: [String]
    let outputDevices: [String]

    var body: some View {
        XFCard {
            VStack(alignment: .leading, spacing: XFSpacing.md) {
                devicePicker("Entrada (timecode)", devices: inputDevices,
                             selection: $model.inputDeviceName)
                devicePicker("Salida", devices: outputDevices,
                             selection: $model.outputDeviceName)
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
            }
        }
    }

    private func devicePicker(_ title: String, devices: [String],
                              selection: Binding<String?>) -> some View {
        HStack {
            Text(title).foregroundColor(XFColor.textMuted).frame(width: 160, alignment: .leading)
            Picker("", selection: selection) {
                Text("— elige —").tag(String?.none)
                ForEach(devices, id: \.self) { Text($0).tag(String?.some($0)) }
            }
            .labelsHidden()
        }
    }
}

// MARK: - 2 · Latencia

struct LatencyCalibrationStep: View {
    @ObservedObject var model: CalibrationWizardModel
    let onMeasure: () -> Void

    var body: some View {
        XFCard {
            VStack(alignment: .leading, spacing: XFSpacing.md) {
                Button("Medir latencia", action: onMeasure).xfButton(.filled)

                if let ms = model.measuredLatencyMs, let verdict = model.latencyVerdict {
                    HStack(spacing: XFSpacing.sm) {
                        Circle().fill(verdict.color).frame(width: 14, height: 14)
                        Text(String(format: "%.1f ms", ms)).font(XFFont.mono(28))
                        Text(verdict.label).foregroundColor(XFColor.textMuted)
                    }
                    Text(verdict.advice)
                        .font(XFFont.body(13)).foregroundColor(XFColor.textMuted)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text("Conecta un cable de la salida a la entrada (o usa el retorno del máster) y pulsa Medir.")
                        .foregroundColor(XFColor.textMuted)
                }
            }
        }
    }
}

// MARK: - 3 · Timecode

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

// MARK: - 4 · Fader

struct FaderCalibrationStep: View {
    @ObservedObject var model: CalibrationWizardModel

    var body: some View {
        XFCard {
            VStack(alignment: .leading, spacing: XFSpacing.md) {
                Text("\(min(model.cutsDetected, model.faderCutsNeeded)) / \(model.faderCutsNeeded) cortes")
                    .font(XFFont.mono(22))

                slider("Punto de corte", value: $model.faderCutIn, range: 0...1)
                slider("Histéresis", value: $model.faderHysteresis, range: 0...0.3)

                Text("Los cortes calibran el punto donde empieza a oírse. Puedes afinarlo a mano.")
                    .font(XFFont.body(12)).foregroundColor(XFColor.textMuted)
            }
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
