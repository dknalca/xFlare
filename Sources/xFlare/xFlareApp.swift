// SPDX-License-Identifier: GPL-3.0-only
//
// xFlare — ejecutable de la app. Cascara fina: monta `AppModel` y `AppRootView`
// de XFApp y ya. Toda la logica vive en los modulos SPM.
//
// Ejecutar:  swift run xFlare   (o abrir Package.swift en Xcode y Run)
//
// CONTENIDO (`data/` y `profiles/`): el `.app` distribuido los lee de
// `Contents/Resources/` (`BundleContentLoader`); ahi los deja el script de
// empaquetado del DMG (B12a.4). En `swift run` no hay bundle con recursos, asi
// que se cae a `RepoContentLoader` (lee del repo via `#filePath`).

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

    @StateObject private var model = AppModel.boot(content: XFlareApp.contentLoader())

    /// El `.app` empaquetado trae `data/` y `profiles/` en `Contents/Resources/`;
    /// si estan, se leen de ahi. Si no (p. ej. `swift run` en dev), del repo.
    static func contentLoader() -> ContentLoader {
        if let bundle = BundleContentLoader(), bundle.hasCatalog {
            return bundle
        }
        return RepoContentLoader()
    }

    var body: some Scene {
        WindowGroup("xFlare") {
            AppRootView(model: model)
                .frame(minWidth: 960, minHeight: 640)
        }
    }
}
