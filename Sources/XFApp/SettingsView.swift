// SPDX-License-Identifier: GPL-3.0-only

import SwiftUI
import XFDesign
import XFCapture

/// Pantalla de Ajustes (`docs/UI_DESIGN.md` §3.7). Edita un `AppSettings` y avisa
/// al guardarlo; la persistencia la hace `XFApp`.
///
/// Layout **manual** (`ScrollView` + `VStack` + `XFCard`), como el resto de la
/// app: el `Form` de SwiftUI en macOS 11 se quedaba en blanco al meterle un
/// `ForEach` (la lista de comandos MIDI).
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
        ScrollView {
            VStack(alignment: .leading, spacing: XFSpacing.lg) {

                section("Perfil") {
                    row("Nombre") {
                        TextField("para las estadísticas", text: bind(\.username))
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            .frame(width: 200)
                    }
                }

                section("Hardware") {
                    Toggle("Corto en reverse (hamster)", isOn: bind(\.hamster))
                    row("Buffer de audio") {
                        Picker("", selection: bind(\.bufferFrames)) {
                            ForEach(AppSettings.bufferOptions, id: \.self) { n in
                                Text("\(n)").tag(n)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 90)
                    }
                    note("Si oyes crujidos, sube el buffer. Cambia al reiniciar la app.")
                }

                section("Sesión") {
                    Toggle("Metrónomo", isOn: bind(\.metronomeEnabled))
                    row("Tolerancia") {
                        HStack(spacing: XFSpacing.xs) {
                            Slider(value: bind(\.toleranceScale), in: 0.5...2.0).frame(width: 160)
                            Text(String(format: "×%.2f", settings.toleranceScale))
                                .font(XFFont.mono(12)).foregroundColor(XFColor.textMuted)
                        }
                    }
                }

                section("Accesibilidad") {
                    Toggle("Alto contraste", isOn: bind(\.highContrast))
                    Toggle("Reducir movimiento", isOn: bind(\.reduceMotion))
                }

                section("MIDI · comandos") {
                    note("Nota o CC por comando. Formato note:canal:nº o cc:canal:nº "
                         + "(canal 0 = cualquiera). Vacío = usar lo del perfil de mesa.")
                    ForEach(PracticeCommand.allCases, id: \.self) { cmd in
                        midiRow(cmd)
                    }
                }

                note("Todo se guarda en tu Mac. Sin cuenta, sin nube, sin telemetría.")
            }
            .frame(maxWidth: 460, alignment: .leading)
            .padding(XFSpacing.xl)
        }
        .background(XFColor.bg)
    }

    // MARK: - piezas

    private func section<C: View>(_ title: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: XFSpacing.xs) {
            Text(title.uppercased()).font(XFFont.body(9)).kerning(0.6)
                .foregroundColor(XFColor.textMuted)
            XFCard {
                VStack(alignment: .leading, spacing: XFSpacing.sm) { content() }
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    /// Fila etiqueta + control a la derecha.
    private func row<C: View>(_ label: String, @ViewBuilder _ control: () -> C) -> some View {
        HStack {
            Text(label).font(XFFont.body(13))
            Spacer(minLength: XFSpacing.sm)
            control()
        }
    }

    private func note(_ text: String) -> some View {
        Text(text)
            .font(XFFont.body(11)).foregroundColor(XFColor.textMuted)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
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
            Text(cmd.label).font(XFFont.body(12)).lineLimit(1)
            Spacer(minLength: XFSpacing.sm)
            TextField(placeholder, text: midiBind(cmd))
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .frame(width: 132)
                .font(XFFont.mono(11))
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
