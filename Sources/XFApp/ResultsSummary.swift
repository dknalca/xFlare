// SPDX-License-Identifier: GPL-3.0-only

import XFAnalysis

/// Lo que pinta la pantalla de resultados (`docs/UI_DESIGN.md` §3.4): las tres
/// estrellas (las apagadas **con su condición escrita**), la puntuación sobre el
/// máximo, y el diagnóstico en lenguaje natural.
///
/// Value type puro: traduce lo que ya calculó `XFAnalysis` a texto listo para
/// pintar. No decide nada.
public struct ResultsSummary: Equatable, Sendable {

    public struct StarRow: Equatable, Sendable {
        public var filled: Bool
        public var title: String            // "Completado" / "Limpio" / "Sólido"
        /// Qué falta para encenderla. `nil` si ya está encendida.
        public var condition: String?
    }

    /// Siempre tres, de la 1ª a la 3ª.
    public var stars: [StarRow]
    /// "3.840 / 4.800".
    public var scoreText: String
    public var accuracyPercent: Int
    /// `Record` discreto si es tu mejor marca.
    public var isBestScore: Bool
    /// Las frases del coach, en orden.
    public var diagnostics: [String]

    private static let titles = ["Completado", "Limpio", "Sólido"]
    private static let prefixes = ["★ ", "★★ ", "★★★ "]
    private static let defaults = [
        "Llega al final con al menos el 70 %.",
        "85 % o más y ningún evento a 0.",
        "95 %, σ ≤ 15 ms y al BPM objetivo.",
    ]

    /// A partir de los campos ya calculados (contrato testeable).
    public static func build(score: Int, maxScore: Int, starCount: Int,
                             starReasons: [String], diagnostics: [String],
                             isBestScore: Bool) -> ResultsSummary {
        let accuracy = maxScore > 0 ? Double(score) / Double(maxScore) : 0
        let rows = (0..<3).map { slot -> StarRow in
            let filled = starCount >= slot + 1
            return StarRow(filled: filled, title: titles[slot],
                           condition: filled ? nil : conditionText(for: slot, reasons: starReasons))
        }
        return ResultsSummary(
            stars: rows,
            scoreText: "\(grouped(score)) / \(grouped(maxScore))",
            accuracyPercent: Int((accuracy * 100).rounded()),
            isBestScore: isBestScore,
            diagnostics: diagnostics)
    }

    /// Atajo desde un `Report` de `XFAnalysis`.
    public static func build(report: Report, isBestScore: Bool) -> ResultsSummary {
        build(score: report.score, maxScore: report.maxScore, starCount: report.stars,
              starReasons: report.starReasons, diagnostics: report.diagnostics.map(\.text),
              isBestScore: isBestScore)
    }

    // MARK: - interno

    private static func conditionText(for slot: Int, reasons: [String]) -> String {
        let mine = reasons.filter { matchesSlot($0, slot: slot) }.map { strip($0, slot: slot) }
        return mine.isEmpty ? defaults[slot] : mine.joined(separator: " ")
    }

    /// El prefijo del slot 0 ("★ ") también prefija a los otros: se comprueba del
    /// más largo al más corto.
    private static func matchesSlot(_ reason: String, slot: Int) -> Bool {
        for s in stride(from: 2, through: 0, by: -1) where reason.hasPrefix(prefixes[s]) {
            return s == slot
        }
        return false
    }

    private static let knownTitles = ["Completado", "Limpio", "Solido", "Sólido"]

    /// Quita el "★★ " y, si lo trae, el "Título: " (la vista ya pone el título).
    private static func strip(_ reason: String, slot: Int) -> String {
        var s = reason
        for p in stride(from: 2, through: 0, by: -1) where s.hasPrefix(prefixes[p]) {
            s = String(s.dropFirst(prefixes[p].count)); break
        }
        if let r = s.range(of: ": "), knownTitles.contains(String(s[..<r.lowerBound])) {
            s = String(s[r.upperBound...])
        }
        return s
    }

    /// Agrupa los millares con punto (`docs/UI_DESIGN.md` §3.4).
    static func grouped(_ n: Int) -> String {
        let digits = Array(String(abs(n)))
        var out: [Character] = []
        for (i, d) in digits.reversed().enumerated() {
            if i > 0, i % 3 == 0 { out.append(".") }
            out.append(d)
        }
        return (n < 0 ? "-" : "") + String(out.reversed())
    }
}
