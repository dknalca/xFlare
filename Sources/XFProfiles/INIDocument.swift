// SPDX-License-Identifier: GPL-3.0-only

import Foundation

/// Un fichero INI ya parseado: secciones -> (clave -> valor), conservando el
/// orden de aparicion. Equivale a lo que hace `configparser` con
/// `optionxform = str` (claves sensibles a mayusculas) en `tools/xf_profile.py`.
///
/// Reglas del parser (ADR-019, suficientes para los `.conf` de `profiles/`):
/// - `[seccion]` abre seccion.
/// - `clave = valor` o `clave : valor` (se recorta el espacio de ambos lados).
/// - Lineas que empiezan por `#` o `;` son comentarios; lineas en blanco se
///   ignoran. **No** hay comentarios de fin de linea ni lineas de continuacion.
/// - Una clave repetida en la misma seccion se queda con el ultimo valor.
public struct INIDocument: Equatable, Sendable {

    /// Nombres de seccion en orden de aparicion.
    public private(set) var sectionOrder: [String] = []
    /// Un par clave/valor de una seccion.
    public struct Item: Equatable, Sendable {
        public var key: String
        public var value: String
    }

    /// Contenido por seccion: claves en orden de aparicion + su valor.
    public private(set) var sections: [String: [Item]] = [:]

    public init() {}

    // MARK: - lectura

    public func hasSection(_ name: String) -> Bool { sections[name] != nil }

    public func hasOption(_ section: String, _ key: String) -> Bool {
        get(section, key) != nil
    }

    /// Valor de `section.key`, o `nil` si no existe la seccion o la clave.
    public func get(_ section: String, _ key: String) -> String? {
        guard let entries = sections[section] else { return nil }
        // ultima aparicion gana, como configparser
        return entries.last(where: { $0.key == key })?.value
    }

    public func keys(in section: String) -> [String] {
        guard let entries = sections[section] else { return [] }
        var seen = Set<String>()
        var order: [String] = []
        for e in entries where !seen.contains(e.key) {
            seen.insert(e.key)
            order.append(e.key)
        }
        return order
    }

    // MARK: - escritura (para el resolvedor de `extends`)

    public mutating func addSection(_ name: String) {
        if sections[name] == nil {
            sections[name] = []
            sectionOrder.append(name)
        }
    }

    /// Fija `section.key = value`, creando la seccion si hace falta. Si la clave
    /// ya existe, sustituye su valor conservando su posicion.
    public mutating func set(_ section: String, _ key: String, _ value: String) {
        addSection(section)
        if let idx = sections[section]?.firstIndex(where: { $0.key == key }) {
            sections[section]?[idx].value = value
        } else {
            sections[section]?.append(Item(key: key, value: value))
        }
    }

    // MARK: - parseo

    public enum ParseError: Error, Equatable, CustomStringConvertible {
        case keyOutsideSection(line: Int)
        case malformedSectionHeader(line: Int)
        case missingDelimiter(line: Int)

        public var description: String {
            switch self {
            case .keyOutsideSection(let n):     return "linea \(n): clave fuera de toda seccion"
            case .malformedSectionHeader(let n): return "linea \(n): cabecera de seccion mal formada"
            case .missingDelimiter(let n):       return "linea \(n): falta '=' o ':'"
            }
        }
    }

    public init(text: String) throws {
        self.init()
        var current: String? = nil
        for (i, rawLine) in text.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
            let lineNo = i + 1
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("#") || line.hasPrefix(";") { continue }

            if line.hasPrefix("[") {
                guard line.hasSuffix("]"), line.count >= 2 else {
                    throw ParseError.malformedSectionHeader(line: lineNo)
                }
                let name = String(line.dropFirst().dropLast()).trimmingCharacters(in: .whitespaces)
                addSection(name)
                current = name
                continue
            }

            guard let section = current else { throw ParseError.keyOutsideSection(line: lineNo) }
            // primer '=' o ':' que aparezca es el delimitador
            guard let delim = line.firstIndex(where: { $0 == "=" || $0 == ":" }) else {
                throw ParseError.missingDelimiter(line: lineNo)
            }
            let key = String(line[line.startIndex..<delim]).trimmingCharacters(in: .whitespaces)
            let value = String(line[line.index(after: delim)...]).trimmingCharacters(in: .whitespaces)
            set(section, key, value)
        }
    }
}
