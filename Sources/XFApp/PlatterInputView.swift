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
/// - `P`        : congelar / descongelar (para la reproduccion sin salir)
/// - `1`        : cue 1 (volver al inicio del sample)
/// - `2`        : reinicia la instrumental desde el principio
/// - `flechas ↑↓`: BPM +/- 1
/// - `Esc`      : salir
struct PlatterInputView: NSViewRepresentable {

    var onScroll: (Double) -> Void       // rueda de ratón: impulso (puntos)
    /// F.44 — trackpad con los dedos puestos: velocidad de la mano en **puntos/s**
    /// (la vista la calcula de Δx/Δt). Control de posición, no de impulso.
    var onScrub: (Double) -> Void = { _ in }
    /// F.44 — dedos fuera del trackpad: vuelve la inercia + fricción.
    var onScrubEnd: () -> Void = {}
    var onNudge: (Bool) -> Void          // true = adelante
    var onFaderClosed: (Bool) -> Void
    var onFreeze: () -> Void
    var onCue: () -> Void
    var onRestartInstrumental: () -> Void = {}
    var onBPM: (Double) -> Void
    var currentBPM: () -> Double
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

        /// F.44 — `timestamp` del último evento de scrub del trackpad, para sacar
        /// la velocidad de la mano de `Δx/Δt`. `0` = no hay gesto en curso.
        private var lastScrubStamp: TimeInterval = 0

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
            // F.03 — ignora la INERCIA del trackpad: macOS sigue mandando
            // eventos de scroll despues de levantar los dedos (`momentumPhase`
            // != []). Sin este filtro el plato recibe empujones de una mano que
            // ya no esta, y encima la sesion le aplica su friccion -> el disco
            // se escapa hacia delante justo cuando quieres pararlo.
            if event.momentumPhase != [] { return }

            // F.44 — control de POSICION mientras los dedos estan en el trackpad.
            // `phase` distingue "mano puesta" (.began/.changed/.stationary) de
            // "mano fuera" (.ended/.cancelled). La velocidad del plato pasa a ser
            // la de la mano (`Δx/Δt`), no un impulso acumulado: si paras la mano
            // sin levantarla, el plato se para en seco.
            if event.phase.contains(.ended) || event.phase.contains(.cancelled) {
                lastScrubStamp = 0
                owner.onScrubEnd()
                return
            }
            if event.phase.contains(.began) || event.phase.contains(.changed)
                || event.phase.contains(.stationary) {
                let stamp = event.timestamp
                let dt = lastScrubStamp > 0 ? stamp - lastScrubStamp : 1.0 / 120.0
                lastScrubStamp = stamp
                // acota `dt` a [1/240, 1/30] s: un hueco largo entre eventos no
                // debe traducirse en una velocidad ridiculamente pequena o enorme.
                let d = min(1.0 / 30.0, max(1.0 / 240.0, dt))
                owner.onScrub(Double(event.scrollingDeltaX) / d)   // puntos/s
                return
            }

            // raton de RUEDA (sin `phase`): impulso clasico, paso grande escalado.
            let dx = event.hasPreciseScrollingDeltas
                ? event.scrollingDeltaX
                : event.deltaX * 8
            if dx != 0 { owner.onScroll(Double(dx)) }
        }

        override func keyDown(with event: NSEvent) {
            switch event.keyCode {
            case 0:   owner.onNudge(false)                 // A
            case 2:   owner.onNudge(true)                  // D
            case 49:  owner.onFaderClosed(true)            // Espacio
            case 35:  owner.onFreeze()                     // P
            case 18:  owner.onCue()                        // 1  (cue 1)
            case 19:  owner.onRestartInstrumental()        // 2  (reinicia la base)
            case 126: owner.onBPM(owner.currentBPM() + 5)  // flecha arriba
            case 125: owner.onBPM(owner.currentBPM() - 5)  // flecha abajo
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
