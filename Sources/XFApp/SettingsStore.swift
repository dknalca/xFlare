// SPDX-License-Identifier: GPL-3.0-only

import Foundation

/// Persistencia de `AppSettings` en un **fichero de texto** que el usuario puede
/// ver, editar y copiar (`CLAUDE.md` §3: los datos son ficheros locales).
///
/// `~/Library/Application Support/xFlare/settings.json` — un JSON plano
/// `{ "clave": "valor" }` con las mismas claves que `AppSettings.raw`. Se
/// escribe **atómicamente en cada cambio** (no depende de que `cfprefsd` vacíe
/// a tiempo, que era la causa de que "no se guardara de una vez a otra" cuando
/// la app se cerraba de golpe).
///
/// El `UserDefaults` de antes se mantiene como espejo y como origen de
/// **migración**: si no hay fichero pero sí un plist viejo, se lee y se escribe
/// el fichero una vez.
enum SettingsStore {

    /// `~/Library/Application Support/xFlare/settings.json`.
    static func fileURL() -> URL {
        let base = (try? FileManager.default.url(for: .applicationSupportDirectory,
                                                 in: .userDomainMask,
                                                 appropriateFor: nil, create: true))
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("xFlare/settings.json")
    }

    /// Lee el fichero. `nil` si no existe o no se puede parsear (el que llama
    /// decide el fallback).
    static func load() -> AppSettings? {
        let url = fileURL()
        guard let data = try? Data(contentsOf: url),
              let obj = try? JSONSerialization.jsonObject(with: data),
              let dict = obj as? [String: String] else {
            return nil
        }
        return AppSettings(raw: dict)
    }

    /// Escribe el fichero de forma atómica. Claves ordenadas y con sangría para
    /// que sea legible y el diff sea estable si el usuario lo mete en git.
    static func save(_ s: AppSettings) {
        let url = fileURL()
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let data = try JSONSerialization.data(
                withJSONObject: s.raw, options: [.prettyPrinted, .sortedKeys])
            try data.write(to: url, options: .atomic)
        } catch {
            // Si falla el fichero seguimos teniendo el espejo en UserDefaults;
            // no hay nada útil que hacer aquí salvo no reventar.
        }
    }
}
