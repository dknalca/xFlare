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
    /// La copia que llega de `AppModel` en cada render. Si cambia por fuera
    /// (p. ej. añadiste instrumentales en la Librería) hay que **re-sembrar** el
    /// `@State`: si no, una visita posterior a Ajustes lo tiene viejo y el
    /// primer cambio pisa lo nuevo (borró la librería de instrumentales).
    private let incoming: AppSettings
    private let onChange: (AppSettings) -> Void
    /// Asignaciones MIDI que trae el perfil activo (sección `[transport]`),
    /// `comando -> "note:1:36"`. Se muestran como valor por defecto; el usuario
    /// puede pisarlas.
    private let profileBindings: [String: String]
    /// "MIDI Learn": escucha CoreMIDI mientras Ajustes está abierto.
    @ObservedObject private var learn: MidiLearnModel

    public init(settings: AppSettings,
                profileBindings: [String: String] = [:],
                learn: MidiLearnModel = MidiLearnModel(),
                onChange: @escaping (AppSettings) -> Void = { _ in }) {
        _settings = State(initialValue: settings)
        self.incoming = settings
        self.profileBindings = profileBindings
        self.learn = learn
        self.onChange = onChange
    }

    public var body: some View {
        TabView {
            generalTab.tabItem { Text("General") }
            midiTab.tabItem { Text("MIDI") }
            debugTab.tabItem { Text("Debug") }
        }
        .padding(.top, XFSpacing.xs)
        .background(XFColor.bg)
        // si `AppModel.settings` cambió por fuera mientras esta vista vivía
        // (otra pantalla tocó la librería, los slots…), re-sembramos para no
        // pisar esos cambios con una copia vieja.
        .onChange(of: incoming) { new in
            if new != settings { settings = new }
        }
        .onAppear {
            // arrancar SIEMPRE de la copia buena de `AppModel` (no de un `@State`
            // que pudo quedarse viejo desde una visita anterior).
            if settings != incoming { settings = incoming }
            // el aprendizaje escribe en ESTA copia de `settings` (la que ve la
            // UI) y la sube con `onChange`. Si solo escribiera en `AppModel`, el
            // `@State` local se quedaría viejo y el cuadro no se actualizaría.
            learn.onLearn = { cmd, binding in
                settings.midiCommandOverrides[cmd.rawValue] = binding.text
                onChange(settings)
            }
            learn.start()
        }
        .onDisappear {
            learn.onLearn = nil
            learn.stop()
        }
    }

    // MARK: - pestaña General

    private var generalTab: some View {
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

                section("Diagnóstico") {
                    Toggle("Mostrar FPS en la práctica", isOn: bind(\.showFPS))
                    note("Contador de fotogramas en una esquina de la autopista. "
                         + "Rojo si baja de 55.")
                }

                section("Vídeo") {
                    row("FPS") {
                        Picker("", selection: bind(\.videoFps)) {
                            ForEach(AppSettings.videoFpsOptions, id: \.self) { Text("\($0)").tag($0) }
                        }
                        .labelsHidden().frame(width: 80)
                    }
                    row("Resolución") {
                        Picker("", selection: bind(\.videoLongSide)) {
                            Text("Rápida").tag(1280)
                            Text("Estándar").tag(1600)
                            Text("Alta").tag(2400)
                        }
                        .labelsHidden().frame(width: 120)
                    }
                    note("Lado mayor del vídeo. La proporción la marca la ventana "
                         + "de práctica. El audio sale con los volúmenes del mixer.")
                }

                note("Todo se guarda en tu Mac. Sin cuenta, sin nube, sin telemetría.")
            }
            .frame(maxWidth: 460, alignment: .leading)
            .padding(XFSpacing.xl)
        }
        .background(XFColor.bg)
    }

    // MARK: - pestaña MIDI

    private var midiTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: XFSpacing.lg) {
                section("Comandos de práctica") {
                    note("Selecciona un comando y pulsa Aprender: el siguiente "
                         + "control MIDI que muevas queda asignado. También puedes "
                         + "escribir la nota/CC a mano (note:canal:nº · cc:canal:nº).")
                    midiMonitor
                    ForEach(PracticeCommand.Category.allCases, id: \.self) { cat in
                        Text(Self.categoryTitle(cat).uppercased())
                            .font(XFFont.body(9)).kerning(0.6)
                            .foregroundColor(XFColor.textMuted)
                            .padding(.top, XFSpacing.xs)
                        ForEach(PracticeCommand.allCases.filter { $0.category == cat }, id: \.self) { cmd in
                            midiRow(cmd)
                        }
                    }
                    midiLearnControls
                }
            }
            .frame(maxWidth: 460, alignment: .leading)
            .padding(XFSpacing.xl)
        }
        .background(XFColor.bg)
    }

    private static func categoryTitle(_ c: PracticeCommand.Category) -> String {
        switch c {
        case .global:       return "Global"
        case .sample:       return "Sample"
        case .instrumental: return "Instrumental"
        }
    }

    // MARK: - pestaña Debug (afinar el "tacto" del plato)

    private var debugTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: XFSpacing.lg) {
                section("Tacto del plato") {
                    note("Para dejar fino el scratch mientras no hay mesa. Se aplica "
                         + "al abrir la práctica; se guarda en tu Mac.")
                    debugSlider("Glide (ms)", bind(\.platterGlideMs),
                                in: 0.5...12, step: 0.5, fmt: "%.1f")
                    note("Suavizado de la velocidad del plato. Menos = más seco, el "
                         + "audio sigue mejor al gesto (menos delay); más = más "
                         + "suave pero con retardo.")
                    debugSlider("Puerta de velocidad", bind(\.platterSpeedGate),
                                in: 0...0.4, step: 0.01, fmt: "%.2f")
                    note("Por debajo de esta velocidad el scratch se atenúa hasta "
                         + "enmudecer (un bloqueador de DC mata el zumbido del "
                         + "cabezal quieto, F.47). 0 = sin puerta.")
                    debugSlider("Fricción", bind(\.platterFriction),
                                in: 0.3...6, step: 0.1, fmt: "%.1f")
                    note("Cómo de rápido frena el plato al soltar. Menos = rueda más "
                         + "y llega más fácil a los extremos.")
                    debugSlider("Sensibilidad trackpad", bind(\.trackpadSensitivity),
                                in: 0.2...2.0, step: 0.1, fmt: "%.1f")
                    Button("Restablecer valores") {
                        settings.platterGlideMs = AppSettings.defaults.platterGlideMs
                        settings.platterSpeedGate = AppSettings.defaults.platterSpeedGate
                        settings.platterFriction = AppSettings.defaults.platterFriction
                        settings.trackpadSensitivity = AppSettings.defaults.trackpadSensitivity
                        onChange(settings)
                    }
                    .xfButton(.bordered)
                }
            }
            .frame(maxWidth: 460, alignment: .leading)
            .padding(XFSpacing.xl)
        }
        .background(XFColor.bg)
    }

    private func debugSlider(_ label: String, _ value: Binding<Double>,
                             in range: ClosedRange<Double>, step: Double,
                             fmt: String) -> some View {
        row(label) {
            HStack(spacing: XFSpacing.xs) {
                Slider(value: value, in: range, step: step).frame(width: 180)
                Text(String(format: fmt, value.wrappedValue))
                    .font(XFFont.mono(12)).foregroundColor(XFColor.textMuted)
                    .frame(width: 40, alignment: .trailing)
            }
        }
    }

    // MARK: - MIDI Learn

    /// Estado del monitor + último mensaje visto.
    private var midiMonitor: some View {
        HStack(spacing: XFSpacing.xs) {
            Circle().fill(learn.running ? XFColor.accent : XFColor.textMuted)
                .frame(width: 6, height: 6)
            Text(learn.running ? "escuchando MIDI" : "sin MIDI conectado")
                .font(XFFont.body(10)).foregroundColor(XFColor.textMuted)
            Spacer(minLength: 0)
            if let last = learn.lastSeen {
                Text(last).font(XFFont.mono(10)).foregroundColor(XFColor.textMuted)
            }
        }
        .frame(maxWidth: 380, alignment: .leading)
    }

    /// Botón "Aprender MIDI" (arma la escucha para el comando seleccionado).
    @ViewBuilder private var midiLearnControls: some View {
        HStack(spacing: XFSpacing.xs) {
            Button(learn.armed ? "Escuchando… mueve un control" : "Aprender MIDI") {
                if learn.armed { learn.cancel() } else { learn.arm() }
            }
            .xfButton(learn.armed ? .bordered : .filled)
            .disabled(learn.selected == nil && !learn.armed)
            if learn.armed {
                Button("Cancelar") { learn.cancel() }.xfButton(.bordered)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: 380, alignment: .leading)
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

    /// Fila de un comando MIDI: radio de selección + nombre + campo de texto para
    /// el override + botón de limpiar. El placeholder muestra lo que trae el
    /// perfil (o "sin asignar"). Si está armado apuntando aquí, "mueve un
    /// control…" en vez del campo.
    private func midiRow(_ cmd: PracticeCommand) -> some View {
        let placeholder = profileBindings[cmd.rawValue] ?? "sin asignar"
        let selected = learn.selected == cmd
        let waiting = learn.armed && selected
        let hasOverride = settings.midiCommandOverrides[cmd.rawValue] != nil

        return HStack(spacing: XFSpacing.xs) {
            Button { learn.select(cmd) } label: {
                HStack(spacing: XFSpacing.xs) {
                    Image(systemName: selected ? "largecircle.fill.circle" : "circle")
                        .font(.system(size: 10))
                        .foregroundColor(selected ? XFColor.accent : XFColor.textMuted)
                    Text(cmd.label).font(XFFont.body(12)).lineLimit(1)
                }
            }
            .buttonStyle(.plain)

            Spacer(minLength: XFSpacing.xs)

            if waiting {
                Text("mueve un control…").font(XFFont.mono(10))
                    .foregroundColor(XFColor.accent).frame(width: 132, alignment: .trailing)
            } else {
                TextField(placeholder, text: midiBind(cmd))
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .frame(width: 132)
                    .font(XFFont.mono(11))
                    .multilineTextAlignment(.trailing)
            }

            Button {
                settings.midiCommandOverrides.removeValue(forKey: cmd.rawValue)
                onChange(settings)
            } label: {
                Image(systemName: "xmark.circle.fill").font(.system(size: 11))
            }
            .buttonStyle(.plain)
            .foregroundColor(XFColor.textMuted)
            .opacity(hasOverride ? 1 : 0.2)
            .disabled(!hasOverride)
        }
        .padding(.vertical, 2).padding(.horizontal, XFSpacing.xxs)
        .background(RoundedRectangle(cornerRadius: XFRadius.control, style: .continuous)
            .fill(selected ? XFColor.accent.opacity(0.08) : Color.clear))
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
