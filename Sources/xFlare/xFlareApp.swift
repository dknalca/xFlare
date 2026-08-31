// SPDX-License-Identifier: GPL-3.0-only
//
// xFlare — ejecutable de la app.
//
// ESTADO (andamiaje): esto es solo el CASCARON. Abre una ventana y pinta la
// pantalla de inicio MAQUETADA, sin logica: nada responde. Las pantallas de
// verdad se implementan en el bloque B11 (XFApp) y este `@main` pasara a
// montar la vista raiz real de XFApp. De momento importa XFApp solo para que
// el ejecutable enlace todo el grafo de modulos y sirva de prueba de humo.
//
// Ejecutar:  swift run xFlare      (o abrir Package.swift en Xcode y darle a Run)

import SwiftUI
import AppKit
import XFApp   // solo para forzar el enlace del grafo completo; aun es un stub

// Un ejecutable SPM no trae bundle ni Info.plist. Sin esto, la ventana puede
// salir sin icono en el Dock ni barra de menu y sin recibir foco.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}

@main
struct XFlareApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    // Marcador de que el grafo enlaza. Se quita cuando XFApp tenga vista raiz.
    private let linkedModuleVersion = XFApp.scaffoldingVersion

    var body: some Scene {
        WindowGroup("xFlare") {
            HomeScaffoldView()
                .frame(minWidth: 900, minHeight: 620)
        }
    }
}
