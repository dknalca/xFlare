// SPDX-License-Identifier: GPL-3.0-only
//
// spike B4 — banco de pruebas del motor de audio (parte Swift: ventana, trackpad,
// teclado, HUD). El audio va en C (sandbox_audio.c). Prototipo DESECHABLE.
//
//   - Trackpad: desplaza con dos dedos (o arrastra) para mover el "plato".
//     Adelante = el sample avanza; atras = suena al reves. Al soltar, frena.
//   - Espacio: corta el crossfader mientras lo mantienes pulsado.
//   - R: rebobina el sample de scratch.
//   - Esc / cerrar la ventana: salir.

import AppKit

// Física del "plato": impulso del trackpad + fricción, en un timer a 120 Hz.
final class Platter {
    var velocity = 0.0
    var impulse = 0.0

    // Ajusta a gusto: cuánto empuja cada evento de scroll y cuánto frena.
    var sensitivity = 0.0045
    let impulseDecay = 0.55     // el impulso se agota en pocos frames
    let friction = 0.90         // al soltar, la velocidad cae a ~0 en ~150 ms

    func addScroll(_ deltaY: Double) {
        impulse += deltaY * sensitivity
        if impulse > 12 { impulse = 12 }
        if impulse < -12 { impulse = -12 }
    }

    func step() {
        velocity += impulse
        impulse *= impulseDecay
        velocity *= friction
        if abs(velocity) < 1e-4 { velocity = 0 }
        if velocity > 16 { velocity = 16 }
        if velocity < -16 { velocity = -16 }
        sandbox_set_velocity(velocity)
    }
}

final class SandboxView: NSView {
    let platter = Platter()
    private var timer: Timer?

    override var acceptsFirstResponder: Bool { true }
    override var isFlipped: Bool { true }

    override func viewDidMoveToWindow() {
        window?.makeFirstResponder(self)
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 120.0, repeats: true) { [weak self] _ in
            self?.platter.step()
            self?.needsDisplay = true
        }
    }

    // MARK: - entrada

    override func scrollWheel(with e: NSEvent) {
        // scrollingDeltaY: preciso en trackpad. Signo elegido para que "arrastrar
        // hacia arriba" = adelante; si lo notas al revés, cambia el signo aquí.
        platter.addScroll(Double(e.scrollingDeltaY))
    }

    override func mouseDragged(with e: NSEvent) {
        platter.addScroll(Double(-e.deltaY) * 1.4)   // click-drag como alternativa
    }

    override func keyDown(with e: NSEvent) {
        if e.isARepeat { return }
        switch e.keyCode {
        case 49: sandbox_set_fader_open(false)   // espacio: corta
        case 15: sandbox_reset_scratch()          // r
        case 53: NSApp.terminate(nil)             // esc
        default: break
        }
    }

    override func keyUp(with e: NSEvent) {
        if e.keyCode == 49 { sandbox_set_fader_open(true) }
    }

    // MARK: - HUD

    override func draw(_ dirty: NSRect) {
        NSColor(calibratedRed: 0.043, green: 0.051, blue: 0.063, alpha: 1).setFill()
        bounds.fill()

        let vel = sandbox_get_velocity()
        let pos = sandbox_get_scratch_pos()
        let peak = sandbox_get_out_peak()
        let open = sandbox_get_fader_open()

        // velocidad
        let arrow = vel > 0.05 ? "▶" : (vel < -0.05 ? "◀" : "■")
        drawText(String(format: "%@  %+.2f×", arrow, vel),
                 at: NSPoint(x: 24, y: 20), size: 34, weight: .semibold,
                 color: NSColor(calibratedRed: 0.20, green: 0.88, blue: 0.77, alpha: 1))

        // barra de posición del sample
        let track = NSRect(x: 24, y: 84, width: bounds.width - 48, height: 14)
        NSColor(calibratedWhite: 1, alpha: 0.08).setFill()
        NSBezierPath(roundedRect: track, xRadius: 7, yRadius: 7).fill()
        let head = NSRect(x: track.minX, y: track.minY,
                          width: max(4, track.width * CGFloat(pos)), height: track.height)
        NSColor(calibratedRed: 0.20, green: 0.88, blue: 0.77, alpha: 0.9).setFill()
        NSBezierPath(roundedRect: head, xRadius: 7, yRadius: 7).fill()

        // fader
        drawText(open ? "FADER: ABIERTO" : "FADER: CORTE  (espacio)",
                 at: NSPoint(x: 24, y: 116), size: 15, weight: .medium,
                 color: open ? NSColor(calibratedRed: 0.56, green: 0.83, blue: 0.29, alpha: 1)
                             : NSColor(calibratedRed: 1.0, green: 0.30, blue: 0.37, alpha: 1))

        // meter de salida
        let meter = NSRect(x: 24, y: 150, width: (bounds.width - 48) * CGFloat(min(1.0, peak)), height: 8)
        NSColor(calibratedWhite: 1, alpha: 0.06).setFill()
        NSBezierPath(rect: NSRect(x: 24, y: 150, width: bounds.width - 48, height: 8)).fill()
        NSColor(calibratedRed: 0.96, green: 0.77, blue: 0.26, alpha: 1).setFill()
        NSBezierPath(rect: meter).fill()

        drawText("trackpad: mueve el plato   ·   espacio: corta el fader   ·   R: rebobina   ·   esc: salir",
                 at: NSPoint(x: 24, y: bounds.height - 34), size: 12, weight: .regular,
                 color: NSColor(calibratedWhite: 0.6, alpha: 1))
    }

    private func drawText(_ s: String, at p: NSPoint, size: CGFloat,
                          weight: NSFont.Weight, color: NSColor) {
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: size, weight: weight),
            .foregroundColor: color,
        ]
        s.draw(at: p, withAttributes: attrs)
    }
}

// MARK: - localizar los mp3

func findAudio() -> (scratch: String, inst: String)? {
    let scratchRel = "Audio/Sample Scratchs/ahh-fresh.mp3"
    let instRel = "Audio/Intrumental loops/The Turntablist - Break This.mp3"
    let args = CommandLine.arguments
    if args.count >= 3 { return (args[1], args[2]) }

    let fm = FileManager.default
    var dir = URL(fileURLWithPath: fm.currentDirectoryPath)
    for _ in 0..<6 {
        let s = dir.appendingPathComponent(scratchRel).path
        let i = dir.appendingPathComponent(instRel).path
        if fm.fileExists(atPath: s) && fm.fileExists(atPath: i) { return (s, i) }
        dir.deleteLastPathComponent()
    }
    return nil
}

// MARK: - arranque

let app = NSApplication.shared
app.setActivationPolicy(.regular)

guard let audio = findAudio() else {
    FileHandle.standardError.write(Data("""
      No encuentro los mp3. Ejecuta desde la raíz del repo, o pasa las rutas:
        spike/b4-audio-sandbox/sandbox "ruta/al/scratch.mp3" "ruta/a/la/instrumental.mp3"

    """.utf8))
    exit(1)
}

if sandbox_load(audio.scratch, audio.inst) != 0 {
    FileHandle.standardError.write(Data("  fallo al decodificar el audio.\n".utf8))
    exit(1)
}
if sandbox_start() != 0 {
    FileHandle.standardError.write(Data("  fallo al abrir la salida de audio.\n".utf8))
    exit(1)
}

let win = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 620, height: 300),
                   styleMask: [.titled, .closable, .miniaturizable],
                   backing: .buffered, defer: false)
win.title = "xFlare · banco de pruebas de audio (spike B4)"
win.center()
win.contentView = SandboxView(frame: win.contentRect(forFrameRect: win.frame))
win.makeKeyAndOrderFront(nil)
win.isReleasedWhenClosed = false

// salir del proceso al cerrar la ventana
final class Delegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ s: NSApplication) -> Bool { true }
    func applicationWillTerminate(_ n: Notification) { sandbox_stop() }
}
let delegate = Delegate()
app.delegate = delegate

app.activate(ignoringOtherApps: true)
app.run()
