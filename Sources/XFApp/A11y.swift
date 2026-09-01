// SPDX-License-Identifier: GPL-3.0-only

import SwiftUI
import XFDesign

/// Piezas de accesibilidad (`docs/UI_DESIGN.md` §4). `XFDesign` está sellado, así
/// que los ajustes de alto contraste viven aquí, encima de sus tokens.
public enum A11y {

    /// Modo alto contraste: sube `ghost` al 60 % y engorda los trazos.
    public struct Palette: Equatable, Sendable {
        public var ghostOpacity: Double
        public var strokeWidth: Double
        public var userStrokeWidth: Double

        public static let standard = Palette(ghostOpacity: 0.35, strokeWidth: 3, userStrokeWidth: 3)
        public static let highContrast = Palette(ghostOpacity: 0.60, strokeWidth: 4, userStrokeWidth: 5)

        public static func active(highContrast: Bool) -> Palette {
            highContrast ? .highContrast : .standard
        }
    }

    // MARK: - descripciones para VoiceOver

    /// El resumen de resultados leído en voz alta (`docs/UI_DESIGN.md` §4:
    /// "VoiceOver en navegación y resultados").
    public static func resultsDescription(_ s: ResultsSummary) -> String {
        let filled = s.stars.filter(\.filled).count
        var parts = ["\(filled) de 3 estrellas.",
                     "\(s.scoreText.replacingOccurrences(of: "/", with: "de")), \(s.accuracyPercent) por ciento."]
        if s.isBestScore { parts.append("Tu mejor marca.") }
        let missing = s.stars.compactMap { row -> String? in
            guard let c = row.condition else { return nil }
            return "\(row.title): \(c)"
        }
        if !missing.isEmpty { parts.append("Falta " + missing.joined(separator: " ")) }
        for d in s.diagnostics { parts.append(d) }
        return parts.joined(separator: " ")
    }

    /// El anuncio de la autopista como región en vivo: el resumen del compás.
    public static func highwayLiveAnnouncement(bar: Int, ofBars total: Int,
                                               accuracyPercent: Int?) -> String {
        var s = "Compás \(bar) de \(total)."
        if let a = accuracyPercent { s += " \(a) por ciento." }
        return s
    }
}
