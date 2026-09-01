// SPDX-License-Identifier: GPL-3.0-only

/// Resuelve `extends`: un perfil hereda las secciones enteras del padre y solo
/// escribe lo que cambia. Porta `resolve()` de `tools/xf_profile.py`, incluida
/// la deteccion de herencia circular.
public enum ProfileResolver {

    public enum ResolveError: Error, Equatable, CustomStringConvertible {
        case unknownProfile(String)
        case unknownAncestor(profile: String, ancestor: String)
        case circularInheritance(chain: [String])

        public var description: String {
            switch self {
            case .unknownProfile(let id):
                return "no existe el perfil: \(id)"
            case .unknownAncestor(let p, let a):
                return "\(p): extends apunta a un perfil que no existe: \(a)"
            case .circularInheritance(let chain):
                return "herencia circular: \(chain.joined(separator: " -> "))"
            }
        }
    }

    /// Devuelve el INI de `id` con todos sus `extends` aplicados. `registry` son
    /// todos los perfiles conocidos indexados por id.
    public static func resolve(id: String, in registry: [String: INIDocument]) throws -> INIDocument {
        try resolve(id: id, in: registry, seen: [])
    }

    private static func resolve(id: String, in registry: [String: INIDocument],
                                seen: [String]) throws -> INIDocument {
        guard let child = registry[id] else { throw ResolveError.unknownProfile(id) }
        guard let ancestor = child.get("profile", "extends") else { return child }

        if seen.contains(ancestor) {
            throw ResolveError.circularInheritance(chain: seen + [ancestor])
        }
        guard registry[ancestor] != nil else {
            throw ResolveError.unknownAncestor(profile: id, ancestor: ancestor)
        }

        var merged = try resolve(id: ancestor, in: registry, seen: seen + [ancestor])
        // el hijo pisa al padre, seccion por seccion, clave por clave.
        for section in child.sectionOrder {
            merged.addSection(section)
            for key in child.keys(in: section) {
                merged.set(section, key, child.get(section, key)!)
            }
        }
        return merged
    }
}
