// SPDX-License-Identifier: GPL-3.0-only

import SwiftUI
import AppKit
import XFDesign

/// La **Librería** de medios: dos pestañas, **Instrumentales** (loops / bases) y
/// **Samples** (de scratch). El usuario guarda aquí sus ficheros para tenerlos a
/// mano en la práctica. Se pueden **arrastrar y soltar** audios sobre cualquiera
/// de las dos listas.
///
/// Las instrumentales se **pre-analizan** (tempo, fase, compases) al añadirlas
/// (`InstrumentalAnalysisCache`), así cargar una en la práctica es instantáneo.
struct MediaLibraryView: View {

    let instrumentals: [String]
    let samples: [String]
    let sampleSlots: [String]
    @ObservedObject var analysisCache: InstrumentalAnalysisCache
    var sampleRate: Double = 48_000
    var onInstrumentalsChanged: ([String]) -> Void = { _ in }
    var onSamplesChanged: ([String]) -> Void = { _ in }
    var onSampleSlotsChanged: ([String]) -> Void = { _ in }
    /// Abrir el editor de una instrumental (tempo/rejilla, cues, loops).
    var onEditInstrumental: (String) -> Void = { _ in }
    /// Abrir el editor de un sample (inicio + duración).
    var onEditSample: (String) -> Void = { _ in }

    private static let audioExts: Set<String> = ["wav", "aif", "aiff", "caf", "mp3", "m4a", "aac"]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Librería").font(XFFont.title(22)).padding(XFSpacing.xl).padding(.bottom, 0)
            TabView {
                DropList(
                    hint: "Loops y bases para practicar encima. El botón de ajustes de "
                        + "cada una abre el editor (tempo, rejilla, cues, loops).",
                    items: instrumentals, cap: 200, showAnalysis: true,
                    analysisCache: analysisCache, sampleRate: sampleRate,
                    audioExts: Self.audioExts, onChange: onInstrumentalsChanged,
                    onEdit: onEditInstrumental
                ).tabItem { Text("Instrumentales") }

                samplesTab.tabItem { Text("Samples") }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(XFColor.bg)
        .onAppear { analysisCache.analyzeAll(instrumentals, sampleRate: sampleRate) }
    }

    /// Pestaña de samples: los 4 **slots MIDI** arriba + la lista de samples.
    private var samplesTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: XFSpacing.lg) {
                VStack(alignment: .leading, spacing: XFSpacing.sm) {
                    Text("SLOTS MIDI").font(XFFont.body(9)).kerning(0.6)
                        .foregroundColor(XFColor.textMuted)
                    Text("Asigna un sample a cada slot y luego, en Ajustes › MIDI, un "
                         + "botón a «Sample 1»…«Sample 4» para cambiar de sample en "
                         + "mitad de una sesión.")
                        .font(XFFont.body(10)).foregroundColor(XFColor.textMuted)
                        .fixedSize(horizontal: false, vertical: true)
                    ForEach(0..<4, id: \.self) { i in slotRow(i) }
                }

                DropList(hint: "Samples de scratch. El botón de ajustes de cada uno "
                            + "abre el editor (elegir inicio y duración).",
                         items: samples, cap: 12, showAnalysis: false,
                         analysisCache: analysisCache, sampleRate: sampleRate,
                         audioExts: Self.audioExts, onChange: onSamplesChanged,
                         onEdit: onEditSample)
                    .frame(minHeight: 240)
            }
            .frame(maxWidth: 560, alignment: .leading)
            .padding(XFSpacing.xl)
        }
        .background(XFColor.bg)
    }

    private func slotRow(_ i: Int) -> some View {
        let current = sampleSlots.indices.contains(i) ? sampleSlots[i] : ""
        let name = current.isEmpty ? "— vacío —"
            : URL(fileURLWithPath: current).deletingPathExtension().lastPathComponent
        return HStack(spacing: XFSpacing.sm) {
            Text("Sample \(i + 1)").font(XFFont.mono(11)).foregroundColor(XFColor.textMuted)
                .frame(width: 62, alignment: .leading)
            Menu {
                Button("— vacío —") { setSlot(i, "") }
                if !samples.isEmpty { Divider() }
                ForEach(samples, id: \.self) { path in
                    Button(URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent) {
                        setSlot(i, path)
                    }
                }
            } label: {
                HStack {
                    Text(name).font(XFFont.body(11)).lineLimit(1).truncationMode(.middle)
                    Spacer()
                    Image(systemName: "chevron.up.chevron.down").font(.system(size: 8))
                        .foregroundColor(XFColor.textMuted)
                }
                .foregroundColor(current.isEmpty ? XFColor.textMuted : XFColor.text)
                .padding(.vertical, 5).padding(.horizontal, XFSpacing.sm)
                .background(RoundedRectangle(cornerRadius: XFRadius.control).fill(XFColor.surface))
            }
            .menuStyle(.borderlessButton)
        }
    }

    private func setSlot(_ i: Int, _ path: String) {
        var slots = (0..<4).map { sampleSlots.indices.contains($0) ? sampleSlots[$0] : "" }
        slots[i] = path
        onSampleSlotsChanged(slots)
    }

}

/// Una lista con zona de arrastrar-y-soltar + botón "Añadir…".
private struct DropList: View {
    let hint: String
    let items: [String]
    let cap: Int
    let showAnalysis: Bool
    @ObservedObject var analysisCache: InstrumentalAnalysisCache
    let sampleRate: Double
    let audioExts: Set<String>
    let onChange: ([String]) -> Void
    /// Si no es `nil`, cada fila (con análisis) muestra un botón de editar.
    var onEdit: ((String) -> Void)? = nil

    @State private var targeted = false
    @State private var recurse = true

    /// A partir de tantos ficheros nuevos se pide confirmación (analizar tarda ~1 s
    /// por pista).
    private let manyThreshold = 20

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: XFSpacing.md) {
                Text(hint).font(XFFont.body(11)).foregroundColor(XFColor.textMuted)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: XFSpacing.sm) {
                    Button("Añadir ficheros…") { openPanel() }.xfButton(.filled)
                    Button("Añadir carpeta…") { openFolder() }.xfButton(.bordered)
                    Toggle("subcarpetas", isOn: $recurse)
                        .toggleStyle(.checkbox).font(XFFont.body(11))
                    Spacer()
                    Text("\(items.count) / \(cap)")
                        .font(XFFont.mono(11)).foregroundColor(XFColor.textMuted)
                }

                VStack(spacing: XFSpacing.xs) {
                    if items.isEmpty {
                        Text("Arrastra audios aquí o pulsa «Añadir…».")
                            .font(XFFont.body(12)).foregroundColor(XFColor.textMuted)
                            .frame(maxWidth: .infinity).padding(.vertical, XFSpacing.lg)
                    } else {
                        ForEach(items, id: \.self) { row(path: $0) }
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(XFSpacing.xs)
                .background(RoundedRectangle(cornerRadius: XFRadius.control, style: .continuous)
                    .fill(targeted ? XFColor.accent.opacity(0.10) : Color.clear))
                .overlay(RoundedRectangle(cornerRadius: XFRadius.control, style: .continuous)
                    .strokeBorder(targeted ? XFColor.accent : XFColor.stroke,
                                  style: StrokeStyle(lineWidth: 1, dash: targeted ? [] : [3, 3])))
            }
            .frame(maxWidth: 560, alignment: .leading)
            .padding(XFSpacing.xl)
        }
        .background(XFColor.bg)
        .onDrop(of: ["public.file-url"], isTargeted: $targeted) { providers in
            resolveURLs(providers) { urls in add(urls) }
            return true
        }
    }

    @ViewBuilder private func row(path: String) -> some View {
        let url = URL(fileURLWithPath: path)
        let exists = FileManager.default.fileExists(atPath: path)
        HStack(spacing: XFSpacing.sm) {
            Image(systemName: "waveform").foregroundColor(XFColor.textMuted)
            VStack(alignment: .leading, spacing: 1) {
                Text(url.deletingPathExtension().lastPathComponent)
                    .font(XFFont.bodyMedium(13)).lineLimit(1)
                HStack(spacing: 6) {
                    Text(exists ? url.deletingLastPathComponent().path : "no se encuentra el fichero")
                        .foregroundColor(exists ? XFColor.textMuted : Color(hex: 0xE5484D))
                        .lineLimit(1).truncationMode(.middle)
                    if showAnalysis { Text("·").foregroundColor(XFColor.stroke); analysisTag(path) }
                }
                .font(XFFont.body(9))
            }
            Spacer(minLength: 0)
            if exists, let onEdit {
                Button { onEdit(path) } label: {
                    Image(systemName: "slider.horizontal.below.rectangle").foregroundColor(XFColor.accent)
                }
                .buttonStyle(.plain)
                .help(showAnalysis ? "Editar tempo, rejilla, cues y loops" : "Editar inicio y duración")
            }
            Button { onChange(items.filter { $0 != path }); analysisCache.forget(path) } label: {
                Image(systemName: "xmark.circle.fill").foregroundColor(XFColor.textMuted)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 7).padding(.horizontal, XFSpacing.sm)
        .background(RoundedRectangle(cornerRadius: XFRadius.control, style: .continuous)
            .fill(XFColor.surface))
    }

    @ViewBuilder private func analysisTag(_ path: String) -> some View {
        if analysisCache.analyzing.contains(path) {
            Text("analizando…").foregroundColor(XFColor.accent)
        } else if let r = analysisCache.result(for: path, sampleRate: sampleRate) {
            let bars = max(1, Int((Double(r.beats) / 4.0).rounded()))
            Text("≈ \(Int(r.bpm.rounded())) BPM · \(bars) \(bars == 1 ? "compás" : "compases")")
                .foregroundColor(XFColor.textMuted)
        } else {
            Text("sin analizar").foregroundColor(XFColor.textMuted)
        }
    }

    // MARK: - añadir

    private func openPanel() {
        let panel = NSOpenPanel()
        panel.allowedFileTypes = Array(audioExts)
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.prompt = "Añadir"
        guard panel.runModal() == .OK else { return }
        add(panel.urls)
    }

    private func openFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Escanear"
        guard panel.runModal() == .OK, let dir = panel.url else { return }
        add(scan(dir, recursive: recurse))
    }

    /// Todos los audios de `dir` (opcionalmente en subcarpetas).
    private func scan(_ dir: URL, recursive: Bool) -> [URL] {
        let fm = FileManager.default
        let opts: FileManager.DirectoryEnumerationOptions =
            recursive ? [.skipsHiddenFiles] : [.skipsHiddenFiles, .skipsSubdirectoryDescendants]
        guard let en = fm.enumerator(at: dir, includingPropertiesForKeys: nil, options: opts) else { return [] }
        return en.compactMap { $0 as? URL }
            .filter { audioExts.contains($0.pathExtension.lowercased()) }
    }

    private func add(_ urls: [URL]) {
        let ok = urls.filter { audioExts.contains($0.pathExtension.lowercased()) }
        var next = items
        var added = 0
        for url in ok where !next.contains(url.path) { next.insert(url.path, at: 0); added += 1 }
        guard added > 0 else { return }
        let capped = Array(next.prefix(cap))

        // muchas pistas -> avisar antes de lanzar el pre-análisis.
        if showAnalysis, added >= manyThreshold {
            let a = NSAlert()
            a.messageText = "Añadir \(added) instrumentales"
            a.informativeText = "Analizar el tempo de \(added) pistas puede tardar cerca de "
                + "\(added) segundos en segundo plano. Puedes seguir usando la app mientras tanto."
            a.addButton(withTitle: "Añadir y analizar")
            a.addButton(withTitle: "Cancelar")
            guard a.runModal() == .alertFirstButtonReturn else { return }
        }

        onChange(capped)
        if showAnalysis { analysisCache.analyzeAll(capped, sampleRate: sampleRate) }
    }

    /// Saca los `URL` de fichero de los `NSItemProvider` de un drop y llama a
    /// `done` en el hilo principal cuando están todos.
    private func resolveURLs(_ providers: [NSItemProvider], done: @escaping ([URL]) -> Void) {
        let group = DispatchGroup()
        var urls: [URL] = []
        let lock = NSLock()
        for p in providers where p.hasItemConformingToTypeIdentifier("public.file-url") {
            group.enter()
            p.loadDataRepresentation(forTypeIdentifier: "public.file-url") { data, _ in
                if let data, let s = String(data: data, encoding: .utf8),
                   let url = URL(string: s) {
                    lock.lock(); urls.append(url); lock.unlock()
                }
                group.leave()
            }
        }
        group.notify(queue: .main) { done(urls) }
    }
}
