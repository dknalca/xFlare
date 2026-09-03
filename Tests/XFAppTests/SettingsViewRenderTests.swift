// SPDX-License-Identifier: GPL-3.0-only
import XCTest
import SwiftUI
import AppKit
@testable import XFApp

/// Regresión: la pantalla de Ajustes debe rendir con tamaño (el `Form` de
/// macOS 11 se quedaba en blanco). Ahora son dos pestañas (General / MIDI) con
/// layout manual.
final class SettingsViewRenderTests: XCTestCase {

    private func editableFields(_ v: NSView) -> Int {
        var n = 0
        if let tf = v as? NSTextField, tf.isEditable { n += 1 }
        for s in v.subviews { n += editableFields(s) }
        return n
    }

    private func hasTabView(_ v: NSView) -> Bool {
        if v is NSTabView { return true }
        return v.subviews.contains { hasTabView($0) }
    }

    func testAjustesRindeConLasDosPestanas() {
        let v = SettingsView(settings: .defaults,
                             profileBindings: ["cue": "note:1:36"],
                             onChange: { _ in })
        let host = NSHostingController(rootView: v)
        host.view.frame = NSRect(x: 0, y: 0, width: 900, height: 720)
        host.view.layoutSubtreeIfNeeded()

        XCTAssertGreaterThan(host.view.fittingSize.height, 100, "no debe colapsar")
        // la pestaña visible al abrir es "General": al menos el campo de nombre
        XCTAssertGreaterThanOrEqual(editableFields(host.view), 1, "falta el campo Nombre")
        // Ajustes es un TabView (General / MIDI)
        XCTAssertTrue(hasTabView(host.view), "Ajustes debe rendir como pestañas")
    }
}
