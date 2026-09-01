// SPDX-License-Identifier: GPL-3.0-only

/// El navegador de la librería (`docs/UI_DESIGN.md` §3.6): la matriz de scratches
/// con filtros. Value type puro; la vista lo consulta.
public struct LibraryBrowser: Equatable, Sendable {

    public var entries: [LibraryEntry]

    public init(entries: [LibraryEntry]) {
        self.entries = entries
    }

    /// Niveles presentes, en orden ascendente.
    public var levels: [Int] {
        Array(Set(entries.map(\.level))).sorted()
    }

    /// Familias presentes, en orden alfabético.
    public var families: [String] {
        Array(Set(entries.map(\.family))).sorted()
    }

    /// Aplica los filtros. `query` casa por subcadena en el nombre (sin distinguir
    /// mayúsculas ni acentos básicos). `nil` = sin ese filtro.
    public func filtered(query: String? = nil,
                         level: Int? = nil,
                         family: String? = nil,
                         onlyUnlocked: Bool = false) -> [LibraryEntry] {
        let needle = query?.folding(options: [.caseInsensitive, .diacriticInsensitive],
                                    locale: nil)
        return entries.filter { e in
            if let level, e.level != level { return false }
            if let family, e.family != family { return false }
            if onlyUnlocked, !e.isUnlocked { return false }
            if let needle, !needle.isEmpty {
                let hay = e.name.folding(options: [.caseInsensitive, .diacriticInsensitive],
                                         locale: nil)
                if !hay.contains(needle) { return false }
            }
            return true
        }
    }

    /// Filtradas y agrupadas por nivel, en orden.
    public func groupedByLevel(query: String? = nil, family: String? = nil,
                               onlyUnlocked: Bool = false) -> [(level: Int, entries: [LibraryEntry])] {
        let list = filtered(query: query, level: nil, family: family, onlyUnlocked: onlyUnlocked)
        let groups = Dictionary(grouping: list, by: \.level)
        return groups.keys.sorted().map { ($0, groups[$0] ?? []) }
    }
}
