// SPDX-License-Identifier: GPL-3.0-only

import Foundation

/// Las primitivas de composicion: los patrones de mano y de fader indexados por
/// id. Es la entrada del `Composer`.
///
/// No sabe de bundles ni de rutas a proposito (el modulo es puro): se le pasan
/// los JSON ya leidos. La app o los tests deciden de donde salen esos bytes
/// (`data/primitives/*.json`).
public struct PrimitiveSet: Sendable {

    public let handPatterns: [String: HandPattern]
    public let faderPatterns: [String: FaderPattern]

    public init(handPatterns: [String: HandPattern], faderPatterns: [String: FaderPattern]) {
        self.handPatterns = handPatterns
        self.faderPatterns = faderPatterns
    }

    /// Construye a partir del contenido de `hand_patterns.json` y
    /// `fader_patterns.json`. Lanza si algun JSON no cuadra con el modelo (eso
    /// es un fallo de datos, no algo recuperable).
    public init(handPatternsJSON: Data, faderPatternsJSON: Data) throws {
        let dec = JSONDecoder()
        self.handPatterns = try dec.decode([String: HandPattern].self, from: handPatternsJSON)
        self.faderPatterns = try dec.decode([String: FaderPattern].self, from: faderPatternsJSON)
    }

    public func hand(_ id: String) throws -> HandPattern {
        guard let h = handPatterns[id] else { throw XFNError.unknownHandPattern(id) }
        return h
    }

    public func fader(_ id: String) throws -> FaderPattern {
        guard let f = faderPatterns[id] else { throw XFNError.unknownFaderPattern(id) }
        return f
    }
}

/// Errores del modulo. Explicitos para que el fallo diga que dato falta.
public enum XFNError: Error, Equatable, CustomStringConvertible {
    case unknownHandPattern(String)
    case unknownFaderPattern(String)
    case handPatternDoesNotClose(id: String, residual: Double)
    case invalidDivision(String)

    public var description: String {
        switch self {
        case .unknownHandPattern(let id):  return "patron de mano desconocido: \(id)"
        case .unknownFaderPattern(let id): return "patron de fader desconocido: \(id)"
        case .handPatternDoesNotClose(let id, let r):
            return "el patron de mano \(id) no cierra el bucle (dist suma \(r))"
        case .invalidDivision(let s):      return "subdivision invalida: \(s)"
        }
    }
}
