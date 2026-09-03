// SPDX-License-Identifier: GPL-3.0-only

import SwiftUI
import XFDesign
import XFCapture

/// Pantalla de Ajustes (`docs/UI_DESIGN.md` §3.7). Edita un `AppSettings` y avisa
/// al guardarlo; la persistencia la hace `XFApp`.
public struct SettingsView: View {

    @State private var settings: AppSettings
    private let onChange: (AppSettings) -> Void
    /// Asignaciones MIDI que trae el perfil activo (sección `[transport]`),
    /// `comando -> "note:1:36"`. Se muestran como valor por defecto; el usuario
    /// puede pisarlas.
    private let profileBindings: [String: String]

    public init(settings: AppSettings,
                profileBindings: [String: String] = [:],
                onChange: @escaping (AppSettings) -> Void = { _ in }) {
        _settings = State(initialValue: settings)
        self.profileBindings = profileBindings
        self.onChange = onChange
    }

    public var body: some View {
        Form {
            Section(header: Text("Perfil")) {
                HStack {
                    Text("Nombre")
                    TextField("para las estadísticas", text: bind(\.username))
                }
            }
            Section(header: Text("Hardware")) {
                Toggle("Corto en reverse (hamster)", isOn: bind(\.hamster))
                Picker("Buffer de audio", selection: bind(\.bufferFrames)) {
                    ForEach(AppSettings.bufferOptions, id: \.self) { n in
                        Text("\(n) frames").tag(n)
                    }
                }
                Text("Si oyes crujidos, sube el buffer. Cambia al reiniciar la app.")
                    .font(XFFont.body(11)).foregroundColor(XFColor.textMuted)
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
            Section(header: Text("MIDI · comandos")) {
                Text("Nota o CC para disparar cada comando de la práctica. "
                     + "Formato: note:canal:número o cc:canal:número (canal 0 = "
                     + "cualquiera). Vacío = usar lo que traiga el perfil de mesa.")
                    .font(XFFont.body(11)).foregroundColor(XFColor.textMuted)
                ForEach(PracticeCommand.allCases, id: \.self) { cmd in
                    midiRow(cmd)
                }
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

    /// Fila de un comando MIDI: nombre + campo de texto para el override. El
    /// placeholder muestra lo que trae el perfil (o "sin asignar").
    private func midiRow(_ cmd: PracticeCommand) -> some View {
        let placeholder = profileBindings[cmd.rawValue] ?? "sin asignar"
        return HStack {
            Text(cmd.label)
            Spacer()
            TextField(placeholder, text: midiBind(cmd))
                .frame(width: 130)
                .font(XFFont.mono(12))
                .multilineTextAlignment(.trailing)
        }
    }

    /// Binding al override de texto de un comando dentro de
    /// `settings.midiCommandOverrides`. Cadena vacía = quita el override.
    private func midiBind(_ cmd: PracticeCommand) -> Binding<String> {
        Binding(
            get: { settings.midiCommandOverrides[cmd.rawValue] ?? "" },
            set: { new in
                let trimmed = new.trimmingCharacters(in: .whitespaces)
                if trimmed.isEmpty {
                    settings.midiCommandOverrides.removeValue(forKey: cmd.rawValue)
                } else {
                    settings.midiCommandOverrides[cmd.rawValue] = trimmed
                }
                onChange(settings)
            })
    }
}
