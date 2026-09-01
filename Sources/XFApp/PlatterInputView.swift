// SPDX-License-Identifier: GPL-3.0-only

import SwiftUI
import AppKit

/// Capa transparente que captura el **trackpad** (scroll horizontal = girar el
/// plato) y el **teclado** para la practica rudimentaria. Se pone encima de la
/// autopista (que no tiene controles propios) y se hace primer respondedor al
/// aparecer, para recibir `keyDown`/`keyUp` este donde este el cursor.
///
/// Teclas (layout US por `keyCode`, no por caracter):
/// - `A` / `D`  : plato atras / adelante
/// - `Espacio`  : mantener = crossfader cerrado (chirp)
/// - `flechas ↑↓`: BPM +/- 1
/// - `Esc`      : salir
struct PlatterInputView: NSViewRepresentable {

    var onScroll: (Double) -> Void
    var onNudge: (Bool) -> Void          // true = adelante
    var onFaderClosed: (Bool) -> Void
    var onBPM: (Int) -> Void
    var currentBPM: () -> Int
    var onExit: () -> Void

    func makeNSView(context: Context) -> NSView { CatcherView(owner: self) }

    func updateNSView(_ nsView: NSView, context: Context) {
        (nsView as? CatcherView)?.owner = self
    }

    /// El `NSView` de verdad. Solo reenvia eventos a los closures del `owner`.
    final class CatcherView: NSView {

        var owner: PlatterInputView

        init(owner: PlatterInputView) {
            self.owner = owner
            super.init(frame: .zero)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { nil }

        override var acceptsFirstResponder: Bool { true }
        override func becomeFirstResponder() -> Bool { true }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            // en el siguiente ciclo: la ventana ya tiene la jerarquia montada
            DispatchQueue.main.async { [weak self] in
                guard let self = self, let window = self.window else { return }
                window.makeFirstResponder(self)
            }
        }

        override func scrollWheel(with event: NSEvent) {
            // trackpad: deltas precisos; raton de rueda: paso grande escalado
            let dx: CGFloat = event.hasPreciseScrollingDeltas
                ? event.scrollingDeltaX
                : event.deltaX * 8
            if dx != 0 { owner.onScroll(Double(dx)) }
        }

        override func keyDown(with event: NSEvent) {
            switch event.keyCode {
            case 0:   owner.onNudge(false)                 // A
            case 2:   owner.onNudge(true)                  // D
            case 49:  owner.onFaderClosed(true)            // Espacio
            case 126: owner.onBPM(owner.currentBPM() + 1)  // flecha arriba
            case 125: owner.onBPM(owner.currentBPM() - 1)  // flecha abajo
            case 53:  owner.onExit()                       // Esc
            default:  super.keyDown(with: event)
            }
        }

        override func keyUp(with event: NSEvent) {
            if event.keyCode == 49 {                       // Espacio
                owner.onFaderClosed(false)
            } else {
                super.keyUp(with: event)
            }
        }
    }
}
