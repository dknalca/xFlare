// SPDX-License-Identifier: GPL-3.0-only

import SwiftUI
import AppKit
import XFDesign

/// La **Librería** de medios: dos pestañas, **Instrumentales** (loops / bases) y
/// **Samples** (de scratch). El usuario guarda aquí sus ficheros para tenerlos a
/// mano en la práctica sin volver a buscarlos en el disco.
///
/// (Fase 1: gestión de la lista + persistencia en `AppSettings`. Pendiente:
/// pre-análisis del tempo para que cargar sea instantáneo, y asignar samples a
/// botones MIDI para cambiar entre varios en mitad de una sesión.)
struct MediaLibraryView: View {

    let instrumentals: [String]
    let samples: [String]
    var onInstrumentalsChanged: ([String]) -> Void = { _ in }
    var onSamplesChanged: ([String]) -> Void = { _ in }

    private let audioTypes = ["wav", "aif", "aiff", "caf", "mp3", "m4a", "aac"]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Librería").font(XFFont.title(22)).padding(XFSpacing.xl).padding(.bottom, 0)
            TabView {
                mediaList(
                    title: "Instrumentales",
                    hint: "Loops y bases para practicar encima. Se cargan desde el panel "
                        + "«Base» de la práctica.",
                    items: instrumentals, cap: 24,
                    onChange: onInstrumentalsChanged
                ).tabItem { Text("Instrumentales") }

                mediaList(
                    title: "Samples",
                    hint: "Samples de scratch. Se eligen en el menú «Sample» del panel "
                        + "«Mezcla». (Asignarlos a botones MIDI: próximamente.)",
                    items: samples, cap: 12,
                    onChange: onSamplesChanged
                ).tabItem { Text("Samples") }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(XFColor.bg)
    }

    private func mediaList(title: String, hint: String, items: [String], cap: Int,
                           onChange: @escaping ([String]) -> Void) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: XFSpacing.md) {
                Text(hint).font(XFFont.body(11)).foregroundColor(XFColor.textMuted)
                    .fixedSize(horizontal: false, vertical: true)

                HStack {
                    Button("Añadir…") { add(to: items, cap: cap, onChange: onChange) }
                        .xfButton(.filled)
                    Text("\(items.count) / \(cap)")
                        .font(XFFont.mono(11)).foregroundColor(XFColor.textMuted)
                    Spacer()
                }

                if items.isEmpty {
                    Text("Nada guardado todavía.")
                        .font(XFFont.body(12)).foregroundColor(XFColor.textMuted)
                        .padding(.top, XFSpacing.sm)
                } else {
                    VStack(spacing: XFSpacing.xs) {
                        ForEach(items, id: \.self) { path in
                            row(path: path, in: items, onChange: onChange)
                        }
                    }
                }
            }
            .frame(maxWidth: 520, alignment: .leading)
            .padding(XFSpacing.xl)
        }
        .background(XFColor.bg)
    }

    private func row(path: String, in items: [String],
                     onChange: @escaping ([String]) -> Void) -> some View {
        let url = URL(fileURLWithPath: path)
        let exists = FileManager.default.fileExists(atPath: path)
        return HStack(spacing: XFSpacing.sm) {
            Image(systemName: "waveform").foregroundColor(XFColor.textMuted)
            VStack(alignment: .leading, spacing: 1) {
                Text(url.deletingPathExtension().lastPathComponent)
                    .font(XFFont.bodyMedium(13)).lineLimit(1)
                Text(exists ? url.deletingLastPathComponent().path : "no se encuentra el fichero")
                    .font(XFFont.body(9))
                    .foregroundColor(exists ? XFColor.textMuted : Color(hex: 0xE5484D))
                    .lineLimit(1).truncationMode(.middle)
            }
            Spacer(minLength: 0)
            Button {
                onChange(items.filter { $0 != path })
            } label: {
                Image(systemName: "xmark.circle.fill").foregroundColor(XFColor.textMuted)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 7).padding(.horizontal, XFSpacing.sm)
        .background(RoundedRectangle(cornerRadius: XFRadius.control, style: .continuous)
            .fill(XFColor.surface))
    }

    private func add(to items: [String], cap: Int, onChange: @escaping ([String]) -> Void) {
        let panel = NSOpenPanel()
        panel.allowedFileTypes = audioTypes
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.prompt = "Añadir"
        guard panel.runModal() == .OK else { return }
        var next = items
        for url in panel.urls where !next.contains(url.path) {
            next.insert(url.path, at: 0)
        }
        onChange(Array(next.prefix(cap)))
    }
}
