// SPDX-License-Identifier: GPL-3.0-only

import SwiftUI
import AppKit
import XFDesign

/// Editor de un sample de scratch de la Librería: elegir **dónde empieza** la
/// parte útil y **cuánto dura** (acotado a `AudioAsset.scratchMaxSeconds`, para
/// que el scratch responda bien). Se puede **escuchar** el recorte en bucle.
///
/// Guarda un `SampleEdit` por fichero (`SampleEditStore`); la práctica lo usa en
/// vez de la detección automática del punto cero (`SampleTrim`, F.3).
struct SampleEditorView: View {

    let path: String
    let engine: EngineHandle?
    var initialEdit: SampleEdit?
    var onSave: (SampleEdit) -> Void
    var onExit: () -> Void

    @State private var pcm: [Float] = []
    @State private var durationSeconds: Double = 0
    @State private var windowImage: NSImage?
    @State private var renderGen = 0
    @State private var loading = true
    @State private var seeded = false

    // el recorte en curso
    @State private var startSec: Double = 0
    @State private var lengthSec: Double = AudioAsset.scratchMaxSeconds

    // vista
    @State private var zoom: Double = 1
    @State private var viewStart: Double = 0
    @State private var dragKind: DragKind? = nil
    @State private var dragAnchor: (start: Double, len: Double, view: Double)? = nil
    @State private var previewing = false

    private enum DragKind { case start, end, body, pan }

    private let sr = 48_000.0
    private var name: String { URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent }
    private var endSec: Double { min(durationSeconds, startSec + lengthSec) }
    private var maxLen: Double { AudioAsset.scratchMaxSeconds }

    private var visibleFrac: Double { 1.0 / max(1, zoom) }
    private func x(_ t: Double, _ w: CGFloat) -> CGFloat {
        guard durationSeconds > 0 else { return 0 }
        return CGFloat((t / durationSeconds - viewStart) / visibleFrac) * w
    }
    private func timeAt(px: CGFloat, _ w: CGFloat) -> Double {
        (viewStart + Double(px / max(1, w)) * visibleFrac) * durationSeconds
    }
    private func clampView() { viewStart = min(max(0, viewStart), max(0, 1 - visibleFrac)) }

    var body: some View {
        VStack(spacing: 0) {
            header
            if loading {
                Spacer(); Text("Analizando la onda…").foregroundColor(XFColor.textMuted); Spacer()
            } else {
                wavePanel
                    .frame(maxWidth: .infinity).frame(height: 200)
                    .padding(.horizontal, XFSpacing.xl).padding(.top, XFSpacing.md)
                controls.padding(XFSpacing.xl)
                Spacer()
            }
        }
        .background(XFColor.bg).foregroundColor(XFColor.text)
        .onAppear(perform: load)
        .onDisappear { engine?.stopPreview() }
    }

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

    // MARK: - onda + ventana de recorte

    private var wavePanel: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            let xa = x(startSec, w), xb = x(endSec, w)
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: XFRadius.control).fill(XFColor.surface)

                if let img = windowImage {
                    Image(nsImage: img).resizable()
                        .frame(width: w, height: h - 12).offset(y: 6).opacity(0.9)
                }

                // fuera de la ventana: oscurecido
                Rectangle().fill(XFColor.bg.opacity(0.55))
                    .frame(width: max(0, xa), height: h)
                Rectangle().fill(XFColor.bg.opacity(0.55))
                    .frame(width: max(0, w - xb), height: h).offset(x: xb)

                // ventana seleccionada + asas
                Rectangle().fill(XFColor.accent.opacity(0.10))
                    .frame(width: max(1, xb - xa), height: h).offset(x: xa)
                handle.offset(x: xa - 4)
                handle.offset(x: xb - 4)
            }
            .clipShape(RoundedRectangle(cornerRadius: XFRadius.control))
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { g in dragChanged(g, w: w, xa: xa, xb: xb) }
                .onEnded { g in dragEnded(g, w: w) })
        }
    }

    private var handle: some View {
        Rectangle().fill(XFColor.accent).frame(width: 8)
            .overlay(Rectangle().fill(Color.white.opacity(0.5)).frame(width: 2))
    }

    private func dragChanged(_ g: DragGesture.Value, w: CGFloat, xa: CGFloat, xb: CGFloat) {
        if dragKind == nil {
            let px = g.startLocation.x
            if abs(px - xa) < 12 { dragKind = .start }
            else if abs(px - xb) < 12 { dragKind = .end }
            else if px > xa && px < xb { dragKind = .body }
            else { dragKind = .pan }
            dragAnchor = (startSec, lengthSec, viewStart)
        }
        guard let a = dragAnchor else { return }
        let dt = Double(g.translation.width / max(1, w)) * visibleFrac * durationSeconds
        switch dragKind {
        case .start:
            let ns = min(durationSeconds - 0.05, max(0, a.start + dt))
            startSec = ns
            lengthSec = min(maxLen, min(a.len, durationSeconds - ns))
        case .end:
            lengthSec = min(maxLen, max(0.05, min(a.len + dt, durationSeconds - a.start)))
        case .body:
            startSec = min(durationSeconds - lengthSec, max(0, a.start + dt))
        case .pan:
            viewStart = a.view - Double(g.translation.width / max(1, w)) * visibleFrac
            clampView()
        case nil: break
        }
    }

    private func dragEnded(_ g: DragGesture.Value, w: CGFloat) {
        defer { dragKind = nil; dragAnchor = nil }
        if dragKind == .pan, abs(g.translation.width) >= 4 { renderWindow() }
        if previewing { startPreview() }   // re-audición del nuevo recorte
    }

    // MARK: - controles

    private var controls: some View {
        VStack(alignment: .leading, spacing: XFSpacing.md) {
            HStack(spacing: XFSpacing.md) {
                Button { previewing ? stopPreview() : startPreview() } label: {
                    HStack(spacing: 5) {
                        Image(systemName: previewing ? "stop.fill" : "play.fill")
                        Text(previewing ? "Parar" : "Escuchar el recorte")
                    }
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(RoundedRectangle(cornerRadius: 6).fill(XFColor.surface))
                }
                .buttonStyle(.plain)

                Spacer()
                Image(systemName: "magnifyingglass").font(.system(size: 10)).foregroundColor(XFColor.textMuted)
                chip("−") { setZoom(zoom / 2) }
                Text(zoom <= 1 ? "todo" : "\(Int(zoom))×").font(XFFont.mono(10))
                    .foregroundColor(XFColor.textMuted).frame(minWidth: 30)
                chip("+") { setZoom(zoom * 2) }
            }

            HStack(spacing: XFSpacing.md) {
                Text("Inicio").font(XFFont.body(10)).foregroundColor(XFColor.textMuted)
                chip("◀") { nudgeStart(-0.02) }
                chip("▶") { nudgeStart(0.02) }
                Text(String(format: "%.3f s", startSec)).font(XFFont.mono(10)).foregroundColor(XFColor.text)

                Text("Duración").font(XFFont.body(10)).foregroundColor(XFColor.textMuted)
                    .padding(.leading, XFSpacing.md)
                chip("◀") { nudgeLen(-0.02) }
                chip("▶") { nudgeLen(0.02) }
                Text(String(format: "%.3f s", lengthSec)).font(XFFont.mono(10)).foregroundColor(XFColor.text)
                Spacer()
                Button("usar todo (máx.)") {
                    startSec = 0
                    lengthSec = min(maxLen, durationSeconds)
                    if previewing { startPreview() }
                }
                .buttonStyle(.plain).font(XFFont.body(10)).foregroundColor(XFColor.accent)
            }

            Text("El scratch responde mejor con un sample corto: la duración se "
                 + "limita a \(String(format: "%.1f", maxLen)) s.")
                .font(XFFont.body(10)).foregroundColor(XFColor.textMuted)
        }
        .frame(maxWidth: 640, alignment: .leading)
    }

    // MARK: - acciones

    private func load() {
        guard !seeded else { return }
        seeded = true
        let url = URL(fileURLWithPath: path)
        DispatchQueue.global(qos: .userInitiated).async {
            let mono = AudioAsset.loadMono(url, sampleRate: sr) ?? []
            let dur = Double(mono.count) / sr
            DispatchQueue.main.async {
                pcm = mono
                durationSeconds = dur
                if let e = initialEdit {
                    startSec = min(max(0, e.startSeconds), max(0, dur - 0.05))
                    lengthSec = min(maxLen, min(e.lengthSeconds, dur - startSec))
                } else {
                    startSec = 0
                    lengthSec = min(maxLen, dur)
                }
                loading = false
                renderWindow()
            }
        }
    }

    /// (Re)dibuja la onda del tramo visible a resolución alta (nítida al zoom).
    private func renderWindow() {
        guard !pcm.isEmpty else { return }
        renderGen &+= 1
        let gen = renderGen
        let n = pcm.count
        let a = min(max(0, Int(viewStart * Double(n))), n - 2)
        let b = min(n, max(a + 2, Int((viewStart + visibleFrac) * Double(n))))
        let slice = Array(pcm[a..<b])
        DispatchQueue.global(qos: .userInitiated).async {
            let wave = WaveformColored.build(slice, sampleRate: sr,
                                             buckets: min(max(200, slice.count / 48), 4_000))
            let img = WaveformImage.render(wave, width: 2400, height: 200)
                .map { NSImage(cgImage: $0, size: .zero) }
            DispatchQueue.main.async { if gen == renderGen, let img { windowImage = img } }
        }
    }

    private func setZoom(_ z: Double) {
        let focus = (startSec + endSec) / 2 / max(0.001, durationSeconds)
        zoom = min(64, max(1, z))
        viewStart = focus - visibleFrac / 2
        clampView()
        renderWindow()
    }

    private func nudgeStart(_ d: Double) {
        startSec = min(durationSeconds - 0.05, max(0, startSec + d))
        lengthSec = min(lengthSec, durationSeconds - startSec)
        if previewing { startPreview() }
    }
    private func nudgeLen(_ d: Double) {
        lengthSec = min(maxLen, max(0.05, min(lengthSec + d, durationSeconds - startSec)))
        if previewing { startPreview() }
    }

    private func startPreview() {
        guard let engine = engine, !pcm.isEmpty else { return }
        let e = SampleEdit(startSeconds: startSec, lengthSeconds: lengthSec)
        guard let r = e.frameRange(frameCount: pcm.count, sampleRate: sr) else { return }
        engine.previewLoop(Array(pcm[r]))
        previewing = true
    }
    private func stopPreview() {
        engine?.stopPreview()
        previewing = false
    }

    private func save() {
        onSave(SampleEdit(startSeconds: startSec, lengthSeconds: lengthSec))
        exit()
    }
    private func exit() { engine?.stopPreview(); onExit() }

    private func chip(_ label: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label).font(XFFont.mono(10))
                .frame(width: 26, height: 20)
                .background(RoundedRectangle(cornerRadius: 4).fill(XFColor.surface))
                .overlay(RoundedRectangle(cornerRadius: 4).stroke(XFColor.stroke, lineWidth: 1))
                .foregroundColor(XFColor.text).contentShape(Rectangle())
        }
        .buttonStyle(.plain).fixedSize()
    }
}
