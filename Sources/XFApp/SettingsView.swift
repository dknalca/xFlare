// SPDX-License-Identifier: GPL-3.0-only

import SwiftUI
import XFDesign

/// Pantalla de Ajustes (`docs/UI_DESIGN.md` §3.7). Edita un `AppSettings` y avisa
/// al guardarlo; la persistencia la hace `XFApp`.
public struct SettingsView: View {

    @State private var settings: AppSettings
    private let onChange: (AppSettings) -> Void

    public init(settings: AppSettings, onChange: @escaping (AppSettings) -> Void = { _ in }) {
        _settings = State(initialValue: settings)
        self.onChange = onChange
    }

    public var body: some View {
        Form {
            Section(header: Text("Hardware")) {
                Toggle("Corto en reverse (hamster)", isOn: bind(\.hamster))
                Picker("Buffer de audio", selection: bind(\.bufferFrames)) {
                    Text("64 frames").tag(64)
                    Text("128 frames").tag(128)
                }
            }
            Section(header: Text("Sesión")) {
                Toggle("Metrónomo", isOn: bind(\.metronomeEnabled))
                HStack {
                    Text("Tolerancia")
                    Slider(value: bind(\.toleranceScale), in: 0.5...2.0)
                    Text(String(format: "×%.2f", settings.toleranceScale)).font(XFFont.mono(12))
                }
            }
            Section(header: Text("Accesibilidad")) {
                Toggle("Alto contraste", isOn: bind(\.highContrast))
                Toggle("Reducir movimiento", isOn: bind(\.reduceMotion))
            }
            Section {
                Text("Todo se guarda en tu Mac. Sin cuenta, sin nube, sin telemetría.")
                    .font(XFFont.body(12)).foregroundColor(XFColor.textMuted)
            }
        }
        .padding(XFSpacing.lg)
        .background(XFColor.bg)
    }

    private func bind<V>(_ keyPath: WritableKeyPath<AppSettings, V>) -> Binding<V> {
        Binding(get: { settings[keyPath: keyPath] },
                set: { settings[keyPath: keyPath] = $0; onChange(settings) })
    }
}
