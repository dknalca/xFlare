// SPDX-License-Identifier: GPL-3.0-only

import Foundation

/// Citas y datos de turntablism que se muestran en la pantalla de carga
/// (`citas.md`, en la raíz del repo / recursos del bundle). Una línea por cita.
enum Quotes {

    static let resourcePath = "citas.md"

    /// Todas las líneas no vacías de `citas.md`, o `[]` si no se encuentra.
    static func all(from content: ContentLoader) -> [String] {
        guard let data = try? content.data(resourcePath),
              let text = String(data: data, encoding: .utf8) else { return [] }
        return text
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    /// Una cita al azar, o un texto de reserva si `citas.md` no está disponible.
    static func random(from content: ContentLoader) -> String {
        all(from: content).randomElement()
            ?? "El tocadiscos es un instrumento. Solo hay que aprender a tocarlo."
    }
}
