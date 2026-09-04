// SPDX-License-Identifier: GPL-3.0-only

import SwiftUI
import AppKit
import XFDesign

/// Mini-editor de una instrumental de la Librería, **antes** de practicar encima:
/// ajustar tempo y dónde cae el "1", poner puntos Cue para saltar a partes
/// concretas, y marcar regiones para hacer **loop infinito** de un trozo.
///
/// Reproduce de verdad (engancha `EngineHandle`): play/pausa, pinchar la onda
/// para saltar, y oír el loop de una región mientras se ajusta. Al guardar, el
/// `InstrumentalEdit` queda por fichero (`InstrumentalEditStore`) y la práctica
/// lo usa en vez de volver a detectar el tempo.
struct InstrumentalEditorView: View {

    let path: String
    let engine: EngineHandle?
    let content: ContentLoader
    /// Análisis de tempo ya hecho (caché de la Librería), como semilla.
    var cachedAnalysis: () -> TempoAnalyzer.Result?
    var initialEdit: InstrumentalEdit?
    var onSave: (InstrumentalEdit) -> Void
    var onExit: () -> Void

    // audio decodificado + onda
    @State private var pcm: [Float] = []
    @State private var durationSeconds: Double = 0
    @State private var waveImage: NSImage?
    @State private var loading = true

    // el ajuste en curso
    @State private var bpm: Double = 120
    @State private var downbeat: Double = 0
    @State private var beatsPerBar: Int = 4
    @State private var cues: [InstrumentalEdit.Cue] = []
    @State private var loops: [InstrumentalEdit.LoopRegion] = []
    @State private var activeLoopID: UUID?

    // transporte
    @State private var playing = false
    @State private var headFraction: Double = 0
    @State private var bpmText = ""
    @State private var editingBPM = false
    @State private var tap = TapTempo()
    @State private var seeded = false

    // zoom de la onda: `zoom` 1 = toda la pista; mayor = ampliado. `viewStart` es
    // el borde izquierdo visible, en fracción 0…1 del fichero.
    @State private var zoom: Double = 1
    @State private var viewStart: Double = 0
    @State private var panAnchor: Double? = nil

    private let sr = 48_000.0
    private let clock = Timer.publish(every: 1.0 / 30.0, on: .main, in: .common).autoconnect()

    private var name: String {
        URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent
    }
    private var headSeconds: Double { headFraction * max(0.001, durationSeconds) }
    private var barSeconds: Double { Double(beatsPerBar) * 60.0 / max(20, bpm) }

    /// Fracción del fichero visible (1/zoom).
    private var visibleFrac: Double { 1.0 / max(1, zoom) }
    /// X (px) de un instante `t` (s) dentro de la ventana visible de ancho `w`.
    private func x(_ t: Double, _ w: CGFloat) -> CGFloat {
        guard durationSeconds > 0 else { return 0 }
        return CGFloat((t / durationSeconds - viewStart) / visibleFrac) * w
    }
    /// Instante (s) en la posición `px` de la ventana visible de ancho `w`.
    private func timeAt(px: CGFloat, _ w: CGFloat) -> Double {
        (viewStart + Double(px / max(1, w)) * visibleFrac) * durationSeconds
    }
    private func clampView() {
        viewStart = min(max(0, viewStart), max(0, 1 - visibleFrac))
    }
    private func setZoom(_ z: Double) {
        let old = zoom
        zoom = min(64, max(1, z))
        // mantener el cabezal (o el centro) en el mismo sitio al ampliar
        let focus = min(max(headFraction, viewStart), viewStart + visibleFrac)
        _ = old
        viewStart = focus - visibleFrac / 2
        clampView()
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            if loading {
                Spacer()
                Text("Analizando la onda…").foregroundColor(XFColor.textMuted)
                Spacer()
            } else {
                waveformPanel
                    .frame(maxWidth: .infinity)
                    .frame(height: 220)
                    .padding(.horizontal, XFSpacing.xl)
                    .padding(.top, XFSpacing.md)
                ScrollView { controls.padding(XFSpacing.xl) }
            }
        }
        .background(XFColor.bg)
        .foregroundColor(XFColor.text)
        .onAppear(perform: load)
        .onDisappear { engine?.setTransport(bpm: bpm, ppq: 480, playing: false) }
        .onReceive(clock) { _ in
            guard playing, let p = engine?.instrumentalProgress, p >= 0 else { return }
            headFraction = p
            // con zoom, la ventana sigue al cabezal si se sale por un borde.
            if zoom > 1 {
                if p < viewStart + visibleFrac * 0.08 || p > viewStart + visibleFrac * 0.92 {
                    viewStart = p - visibleFrac / 2
                    clampView()
                }
            }
        }
    }

    // MARK: - cabecera

    private var header: some View {
        HStack(spacing: XFSpacing.md) {
            Button(action: exit) { Image(systemName: "chevron.left") }.buttonStyle(.plain)
            Text(name).font(XFFont.bodyMedium(15)).lineLimit(1).truncationMode(.middle)
            Spacer()
            Button("Guardar") { save() }.xfButton(.filled)
        }
        .padding(.horizontal, XFSpacing.xl).padding(.vertical, XFSpacing.sm)
        .background(XFColor.surface)
    }

    private struct BeatMark: Identifiable { let k: Int; let x: CGFloat; let isBar: Bool; let bar: Int; var id: Int { k } }

    /// Líneas de la rejilla dentro de la ventana visible: una por negra, marcando
    /// las de compás. Solo se emiten las que caen en pantalla (zoom).
    private func beatMarks(width w: CGFloat) -> [BeatMark] {
        guard bpm > 20, durationSeconds > 0 else { return [] }
        let beat = 60.0 / bpm
        let tMin = viewStart * durationSeconds
        let tMax = (viewStart + visibleFrac) * durationSeconds
        var out: [BeatMark] = []
        var k = max(0, Int(((tMin - downbeat) / beat).rounded(.down)))
        while true {
            let t = downbeat + Double(k) * beat
            if t > tMax || t > durationSeconds { break }
            if t >= tMin {
                let isBar = ((k % beatsPerBar) + beatsPerBar) % beatsPerBar == 0
                out.append(BeatMark(k: k, x: x(t, w), isBar: isBar, bar: k / beatsPerBar + 1))
            }
            k += 1
            if out.count > 2_000 { break }
        }
        return out
    }

    // MARK: - onda + rejilla + marcadores

    private var waveformPanel: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: XFRadius.control).fill(XFColor.surface)

                if let img = waveImage {
                    // la imagen entera mide `w * zoom`; se desplaza a la izquierda
                    // según `viewStart` para enseñar solo la ventana visible.
                    Image(nsImage: img).resizable()
                        .frame(width: w * CGFloat(zoom), height: h - 16)
                        .offset(x: -CGFloat(viewStart) * w * CGFloat(zoom), y: 8)
                        .opacity(0.9)
                }

                // regiones de loop (sombreadas; la activa en acento)
                ForEach(loops) { r in
                    let x0 = x(r.startSeconds, w)
                    let x1 = x(r.endSeconds, w)
                    Rectangle()
                        .fill((r.id == activeLoopID ? XFColor.accent : XFColor.textMuted)
                            .opacity(r.id == activeLoopID ? 0.20 : 0.10))
                        .frame(width: max(1, x1 - x0), height: h)
                        .offset(x: x0)
                }

                // rejilla de compases (líneas) + números arriba
                ForEach(beatMarks(width: w), id: \.k) { m in
                    Rectangle()
                        .fill(m.isBar ? XFColor.text.opacity(0.35) : XFColor.textMuted.opacity(0.18))
                        .frame(width: m.isBar ? 1.5 : 1, height: h)
                        .offset(x: m.x)
                    if m.isBar {
                        Text("\(m.bar)").font(.system(size: 8)).foregroundColor(XFColor.textMuted)
                            .offset(x: m.x + 3, y: 2)
                    }
                }

                // cues
                ForEach(cues) { c in
                    VStack(spacing: 1) {
                        Text(c.name).font(XFFont.mono(8)).foregroundColor(Color(hex: 0xF5C542))
                            .fixedSize()
                        Rectangle().fill(Color(hex: 0xF5C542)).frame(width: 1.5)
                    }
                    .frame(height: h, alignment: .top)
                    .offset(x: x(c.atSeconds, w) - 1)
                }

                // cabezal
                Rectangle().fill(XFColor.accent).frame(width: 2, height: h)
                    .offset(x: x(headSeconds, w) - 1)
            }
            .clipShape(RoundedRectangle(cornerRadius: XFRadius.control))
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { g in
                    guard zoom > 1 else { return }
                    if panAnchor == nil { panAnchor = viewStart }
                    let dxFrac = Double(-g.translation.width / max(1, w)) * visibleFrac
                    viewStart = (panAnchor ?? viewStart) + dxFrac
                    clampView()
                }
                .onEnded { g in
                    defer { panAnchor = nil }
                    // sin apenas movimiento = pinchar para saltar
                    if abs(g.translation.width) < 4 {
                        let t = timeAt(px: g.location.x, w)
                        let f = min(1, max(0, t / max(0.001, durationSeconds)))
                        headFraction = f
                        engine?.seekInstrumental(fraction: f)
                    }
                })
        }
    }

    // MARK: - controles

    private var controls: some View {
        VStack(alignment: .leading, spacing: XFSpacing.lg) {
            transportRow
            tempoRow
            cuesSection
            loopsSection
        }
        .frame(maxWidth: 620, alignment: .leading)
    }

    private var transportRow: some View {
        HStack(spacing: XFSpacing.md) {
            Button { togglePlay() } label: {
                Image(systemName: playing ? "pause.fill" : "play.fill")
                    .frame(width: 34, height: 28)
                    .background(RoundedRectangle(cornerRadius: 6).fill(XFColor.surface))
            }
            .buttonStyle(.plain).keyboardShortcut(.space, modifiers: [])
            Text(timeLabel(headSeconds) + " / " + timeLabel(durationSeconds))
                .font(XFFont.mono(11)).foregroundColor(XFColor.textMuted)
            Spacer()
            // zoom de la onda
            HStack(spacing: 4) {
                Image(systemName: "magnifyingglass").font(.system(size: 10)).foregroundColor(XFColor.textMuted)
                chip("−") { setZoom(zoom / 2) }
                Text(zoom <= 1 ? "todo" : "\(Int(zoom))×")
                    .font(XFFont.mono(10)).foregroundColor(XFColor.textMuted).frame(minWidth: 30)
                chip("+") { setZoom(zoom * 2) }
            }
            Button("Volver al inicio") { seek(0) }.buttonStyle(.plain)
                .font(XFFont.body(11)).foregroundColor(XFColor.accent)
        }
    }

    private var tempoRow: some View {
        VStack(alignment: .leading, spacing: XFSpacing.xs) {
            Text("TEMPO Y REJILLA").font(XFFont.body(9)).kerning(0.6).foregroundColor(XFColor.textMuted)
            HStack(spacing: XFSpacing.sm) {
                if editingBPM {
                    TextField("BPM", text: $bpmText, onCommit: {
                        if let v = Double(bpmText.replacingOccurrences(of: ",", with: ".")) {
                            bpm = min(300, max(20, (v * 10).rounded() / 10))
                        }
                        editingBPM = false
                    })
                    .textFieldStyle(.roundedBorder).font(XFFont.mono(12)).frame(width: 66)
                } else {
                    Button { bpmText = String(format: "%.1f", bpm); editingBPM = true } label: {
                        Text(String(format: "%.1f BPM", bpm)).font(XFFont.mono(12)).foregroundColor(XFColor.accent)
                    }.buttonStyle(.plain)
                }
                chip("TAP") { if let b = tap.tap() { bpm = b } }
                chip("÷2") { bpm = max(20, (bpm / 2 * 10).rounded() / 10) }
                chip("×2") { bpm = min(300, (bpm * 2 * 10).rounded() / 10) }
                Divider().frame(height: 18)
                chip("◀") { downbeat = max(0, downbeat - 0.01) }
                chip("▶") { downbeat += 0.01 }
                Button("fijar el 1 aquí") { downbeat = headSeconds.truncatingRemainder(dividingBy: max(0.001, barSeconds)) }
                    .buttonStyle(.plain).font(XFFont.body(10)).foregroundColor(XFColor.accent)
            }
            HStack(spacing: XFSpacing.sm) {
                Text("Compás").font(XFFont.body(10)).foregroundColor(XFColor.textMuted)
                chip("−") { beatsPerBar = max(1, beatsPerBar - 1) }
                Text("\(beatsPerBar)/4").font(XFFont.mono(11)).frame(minWidth: 34)
                chip("+") { beatsPerBar = min(12, beatsPerBar + 1) }
            }
        }
    }

    private var cuesSection: some View {
        VStack(alignment: .leading, spacing: XFSpacing.xs) {
            HStack {
                Text("PUNTOS CUE").font(XFFont.body(9)).kerning(0.6).foregroundColor(XFColor.textMuted)
                Spacer()
                Button("+ Cue aquí") { addCue() }.buttonStyle(.plain)
                    .font(XFFont.body(10)).foregroundColor(XFColor.accent)
            }
            if cues.isEmpty {
                Text("Marca partes de la instrumental para saltar a ellas en la práctica.")
                    .font(XFFont.body(10)).foregroundColor(XFColor.textMuted)
            }
            ForEach($cues) { $c in
                HStack(spacing: XFSpacing.sm) {
                    TextField("nombre", text: $c.name).textFieldStyle(.roundedBorder)
                        .font(XFFont.body(11)).frame(width: 160)
                    Text(timeLabel(c.atSeconds)).font(XFFont.mono(10)).foregroundColor(XFColor.textMuted)
                    chip("▶") { seek(c.atSeconds / max(0.001, durationSeconds)) }
                    Spacer()
                    Button { cues.removeAll { $0.id == c.id } } label: { Image(systemName: "trash") }
                        .buttonStyle(.plain).foregroundColor(XFColor.textMuted)
                }
            }
        }
    }

    private var loopsSection: some View {
        VStack(alignment: .leading, spacing: XFSpacing.xs) {
            HStack {
                Text("REGIONES DE LOOP").font(XFFont.body(9)).kerning(0.6).foregroundColor(XFColor.textMuted)
                Spacer()
                Button("+ Región (4 compases)") { addLoop() }.buttonStyle(.plain)
                    .font(XFFont.body(10)).foregroundColor(XFColor.accent)
            }
            if loops.isEmpty {
                Text("Marca un trozo y actívalo: la base repetirá SOLO esa parte, infinito.")
                    .font(XFFont.body(10)).foregroundColor(XFColor.textMuted)
            }
            ForEach($loops) { $r in
                loopRow($r)
            }
        }
    }

    private func loopRow(_ r: Binding<InstrumentalEdit.LoopRegion>) -> some View {
        let active = r.wrappedValue.id == activeLoopID
        return VStack(spacing: 3) {
            HStack(spacing: XFSpacing.sm) {
                TextField("nombre", text: r.name).textFieldStyle(.roundedBorder)
                    .font(XFFont.body(11)).frame(width: 140)
                Button { toggleLoop(r.wrappedValue) } label: {
                    Text(active ? "◉ activo" : "activar")
                        .font(XFFont.body(10))
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(RoundedRectangle(cornerRadius: 4)
                            .fill(active ? XFColor.accent.opacity(0.2) : XFColor.surface))
                        .foregroundColor(active ? XFColor.accent : XFColor.textMuted)
                }.buttonStyle(.plain)
                Spacer()
                Button { removeLoop(r.wrappedValue.id) } label: { Image(systemName: "trash") }
                    .buttonStyle(.plain).foregroundColor(XFColor.textMuted)
            }
            HStack(spacing: 6) {
                Text("duración").font(XFFont.body(9)).foregroundColor(XFColor.textMuted)
                chip("÷2") { scaleLoop(r, by: 0.5) }
                chip("×2") { scaleLoop(r, by: 2) }
                let dur = r.wrappedValue.endSeconds - r.wrappedValue.startSeconds
                Text(String(format: "%.2f s · %.1f comp.", dur, dur / max(0.001, barSeconds)))
                    .font(XFFont.mono(9)).foregroundColor(XFColor.textMuted)
                Spacer()
            }
            HStack(spacing: 4) {
                HStack(spacing: 4) {
                    Text("inicio").font(XFFont.body(9)).foregroundColor(XFColor.textMuted)
                    chip("◀") { nudge(r, startBy: -0.1) }
                    chip("▶") { nudge(r, startBy: 0.1) }
                    chip("↦") { r.wrappedValue.startSeconds = headSeconds; clampLoop(r); reapplyLoop() }
                    Text(timeLabel(r.wrappedValue.startSeconds)).font(XFFont.mono(9)).foregroundColor(XFColor.textMuted)
                }
                Spacer()
                HStack(spacing: 4) {
                    Text(timeLabel(r.wrappedValue.endSeconds)).font(XFFont.mono(9)).foregroundColor(XFColor.textMuted)
                    chip("↤") { r.wrappedValue.endSeconds = headSeconds; clampLoop(r); reapplyLoop() }
                    chip("◀") { nudge(r, endBy: -0.1) }
                    chip("▶") { nudge(r, endBy: 0.1) }
                    Text("fin").font(XFFont.body(9)).foregroundColor(XFColor.textMuted)
                }
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - acciones

    private func load() {
        guard !seeded else { return }
        seeded = true
        let url = URL(fileURLWithPath: path)
        DispatchQueue.global(qos: .userInitiated).async {
            let mono = AudioAsset.loadMono(url, sampleRate: sr) ?? []
            let wave = WaveformColored.build(mono, sampleRate: sr, buckets: min(max(200, mono.count / 200), 6_000))
            let img = WaveformImage.render(wave, width: 1600, height: 200).map { NSImage(cgImage: $0, size: .zero) }
            let dur = Double(mono.count) / sr
            DispatchQueue.main.async {
                pcm = mono
                durationSeconds = dur
                waveImage = img
                seedEdit(fileSeconds: dur)
                loading = false
                startEngine()
            }
        }
    }

    private func seedEdit(fileSeconds: Double) {
        if let e = initialEdit {
            bpm = e.bpm ?? (cachedAnalysis()?.bpm ?? 120)
            downbeat = e.downbeatSeconds ?? (cachedAnalysis().map { Double($0.phaseFrames) / sr } ?? 0)
            beatsPerBar = e.beatsPerBar
            cues = e.cues
            loops = e.loops
            activeLoopID = e.activeLoopID
        } else if let a = cachedAnalysis() {
            bpm = (a.bpm * 10).rounded() / 10
            downbeat = Double(a.phaseFrames) / sr
        }
        _ = fileSeconds
    }

    private func startEngine() {
        guard let engine = engine, !pcm.isEmpty else { return }
        // Arranca la salida de audio si aún no está (si venías de una práctica ya
        // suena y esto es no-op). Sin esto, abrir el editor "en frío" no oía nada.
        _ = engine.startOutput()
        engine.loadInstrumental(pcm, nativeBPM: bpm)
        engine.setInstrumentalNativeBPM(bpm)
        engine.setMasterGain(0.9)
        engine.setInstrumentalGain(0.85)
        engine.setScratchGain(0)
        engine.metronomeEnabled = false
        engine.setTransport(bpm: bpm, ppq: 480, playing: playing)
        reapplyLoop()
    }

    private func togglePlay() {
        playing.toggle()
        engine?.setTransport(bpm: bpm, ppq: 480, playing: playing)
    }

    private func seek(_ fraction: Double) {
        let f = min(1, max(0, fraction))
        headFraction = f
        engine?.seekInstrumental(fraction: f)
    }

    private func addCue() {
        let n = cues.count + 1
        cues.append(.init(name: "Cue \(n)", atSeconds: headSeconds))
        cues.sort { $0.atSeconds < $1.atSeconds }
    }

    private func addLoop() {
        let start = headSeconds
        let end = min(durationSeconds, start + 4 * barSeconds)
        let r = InstrumentalEdit.LoopRegion(name: "Loop \(loops.count + 1)",
                                            startSeconds: start, endSeconds: end)
        loops.append(r)
    }

    private func removeLoop(_ id: UUID) {
        loops.removeAll { $0.id == id }
        if activeLoopID == id { activeLoopID = nil; reapplyLoop() }
    }

    private func toggleLoop(_ r: InstrumentalEdit.LoopRegion) {
        activeLoopID = (activeLoopID == r.id) ? nil : r.id
        reapplyLoop()
    }

    private func nudge(_ r: Binding<InstrumentalEdit.LoopRegion>, startBy d: Double = 0, endBy e: Double = 0) {
        r.wrappedValue.startSeconds += d
        r.wrappedValue.endSeconds += e
        clampLoop(r)
        reapplyLoop()
    }

    /// Multiplica la duración de la región por `factor` (×2 / ÷2), dejando el
    /// inicio fijo. Se recorta al fichero.
    private func scaleLoop(_ r: Binding<InstrumentalEdit.LoopRegion>, by factor: Double) {
        let a = r.wrappedValue.startSeconds
        let len = max(0.05, (r.wrappedValue.endSeconds - a) * factor)
        r.wrappedValue.endSeconds = a + len
        clampLoop(r)
        reapplyLoop()
    }

    private func clampLoop(_ r: Binding<InstrumentalEdit.LoopRegion>) {
        var a = max(0, min(r.wrappedValue.startSeconds, r.wrappedValue.endSeconds))
        var b = min(durationSeconds, max(r.wrappedValue.startSeconds, r.wrappedValue.endSeconds))
        if b - a < 0.05 { b = min(durationSeconds, a + 0.05); a = max(0, b - 0.05) }
        r.wrappedValue.startSeconds = a
        r.wrappedValue.endSeconds = b
    }

    /// Aplica al motor la región activa (o la limpia).
    private func reapplyLoop() {
        guard let engine = engine, durationSeconds > 0 else { return }
        if let id = activeLoopID, let r = loops.first(where: { $0.id == id }) {
            engine.setInstrumentalLoopRegion(start: r.startSeconds / durationSeconds,
                                             end: r.endSeconds / durationSeconds)
        } else {
            engine.setInstrumentalLoopRegion(start: -1, end: 0)
        }
    }

    private func save() {
        let a = cachedAnalysis()
        let e = InstrumentalEdit(
            bpm: (a.map { abs($0.bpm - bpm) < 0.05 } == true) ? nil : bpm,
            downbeatSeconds: (a.map { abs(Double($0.phaseFrames) / sr - downbeat) < 0.005 } == true) ? nil : downbeat,
            beatsPerBar: beatsPerBar, cues: cues, loops: loops, activeLoopID: activeLoopID)
        onSave(e)
        exit()
    }

    private func exit() {
        engine?.setTransport(bpm: bpm, ppq: 480, playing: false)
        onExit()
    }

    // MARK: - util

    private func timeLabel(_ s: Double) -> String {
        let t = max(0, s)
        return String(format: "%d:%04.1f", Int(t) / 60, t.truncatingRemainder(dividingBy: 60))
    }

    private func chip(_ label: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label).font(XFFont.mono(10))
                .frame(width: 26, height: 20)
                .background(RoundedRectangle(cornerRadius: 4).fill(XFColor.surface))
                .overlay(RoundedRectangle(cornerRadius: 4).stroke(XFColor.stroke, lineWidth: 1))
                .foregroundColor(XFColor.text)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain).fixedSize()
    }
}
