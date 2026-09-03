// SPDX-License-Identifier: GPL-3.0-only
import XCTest
import SwiftUI
import AppKit
@testable import XFApp

/// Regresión: la pantalla de Ajustes debe rendir con tamaño y con todos los
/// campos editables (nombre + 9 comandos MIDI). El `Form` de macOS 11 se quedaba
/// en blanco con el `ForEach` de comandos; ahora es layout manual.
final class SettingsViewRenderTests: XCTestCase {

    private func editableFields(_ v: NSView) -> Int {
        var n = 0
        if let tf = v as? NSTextField, tf.isEditable { n += 1 }
        for s in v.subviews { n += editableFields(s) }
        return n
    }

    func testSettingsRindeConCamposEditables() {
        let v = SettingsView(settings: .defaults,
                             profileBindings: ["cue": "note:1:36"],
                             onChange: { _ in })
        let host = NSHostingController(rootView: v)
        host.view.frame = NSRect(x: 0, y: 0, width: 900, height: 720)
        host.view.layoutSubtreeIfNeeded()

        XCTAssertGreaterThan(host.view.fittingSize.height, 100, "no debe colapsar")
        // 1 (nombre) + 9 (comandos MIDI)
        XCTAssertGreaterThanOrEqual(editableFields(host.view), 10, "faltan campos de texto")
    }
}
