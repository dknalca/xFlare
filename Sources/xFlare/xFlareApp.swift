// SPDX-License-Identifier: GPL-3.0-only
//
// xFlare — ejecutable de la app. Cascara fina: monta `AppModel` y `AppRootView`
// de XFApp y ya. Toda la logica vive en los modulos SPM.
//
// Ejecutar:  swift run xFlare   (o abrir Package.swift en Xcode y Run)
//
// NOTA (B12): en dev, `AppModel.boot()` lee `data/` y `profiles/` del repo via
// `RepoContentLoader`. El empaquetado de esos recursos en el bundle del .app es
// tarea del bloque de distribucion.

import SwiftUI
import AppKit
import XFApp

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

    @StateObject private var model = AppModel.boot()

    var body: some Scene {
        WindowGroup("xFlare") {
            AppRootView(model: model)
                .frame(minWidth: 960, minHeight: 640)
        }
    }
}
