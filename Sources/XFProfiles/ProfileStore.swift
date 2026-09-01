// SPDX-License-Identifier: GPL-3.0-only

import Foundation

/// Carga los perfiles del bundle y de la carpeta del usuario, resuelve `extends`
/// y ofrece autodeteccion por nombre de puerto (B5b.4 / B5b.5).
///
/// Precedencia (docs/DEVICE_PROFILES.md §5): los de fabrica primero, los del
/// usuario **encima** — si comparten id, gana el del usuario.
public struct ProfileStore {

    /// Un perfil cargado: su INI en crudo, de donde salio y (si valida) su forma
    /// tipada ya resuelta.
    public struct Entry: Equatable {
        public enum Origin: Equatable { case bundled, user }
        public let id: String
        public let origin: Origin
        public let raw: INIDocument
        /// `nil` si el perfil no resuelve/parsea (el error queda en `problem`).
        public let profile: DeviceProfile?
        public let problem: String?
        public let isExample: Bool
    }

    /// Todos los perfiles por id, ya con la precedencia aplicada.
    public let entries: [String: Entry]

    /// Registry en crudo (para el validador y el resolvedor).
    public var registry: [String: INIDocument] {
        entries.mapValues { $0.raw }
    }

    // MARK: - construccion

    /// - Parameters:
    ///   - bundled: (nombreFichero, contenido) de `profiles/` del bundle.
    ///   - user: idem de la carpeta del usuario. Pisan a los de fabrica por id.
    public init(bundled: [(filename: String, text: String)],
                user: [(filename: String, text: String)] = []) {
        var acc: [String: Entry] = [:]
        func ingest(_ files: [(filename: String, text: String)], origin: Entry.Origin) {
            for f in files {
                let stem = (f.filename as NSString).deletingPathExtension
                let isExample = f.filename.hasSuffix(".example")
                guard let ini = try? INIDocument(text: f.text) else {
                    // sin id fiable: se indexa por el nombre del fichero
                    acc[stem] = Entry(id: stem, origin: origin, raw: INIDocument(),
                                      profile: nil, problem: "no se puede parsear el INI",
                                      isExample: isExample)
                    continue
                }
                let id = ini.get("profile", "id") ?? stem
                acc[id] = Entry(id: id, origin: origin, raw: ini,
                                profile: nil, problem: nil, isExample: isExample)
            }
        }
        ingest(bundled, origin: .bundled)
        ingest(user, origin: .user)

        // segunda pasada: ahora que estan todos, resolver y tipar cada uno.
        let rawRegistry = acc.mapValues { $0.raw }
        for (id, e) in acc {
            guard e.problem == nil else { continue }
            do {
                let resolved = try ProfileResolver.resolve(id: id, in: rawRegistry)
                let profile = try DeviceProfile.parse(resolved: resolved)
                acc[id] = Entry(id: id, origin: e.origin, raw: e.raw,
                                profile: profile, problem: nil, isExample: e.isExample)
            } catch {
                acc[id] = Entry(id: id, origin: e.origin, raw: e.raw,
                                profile: nil, problem: "\(error)", isExample: e.isExample)
            }
        }
        self.entries = acc
    }

    // MARK: - consulta

    public func profile(id: String) -> DeviceProfile? { entries[id]?.profile }

    /// Todos los perfiles utilizables (que resuelven y parsean), ordenados por id.
    public var usableProfiles: [DeviceProfile] {
        entries.values.compactMap { $0.profile }.sorted { $0.id < $1.id }
    }

    // MARK: - autodeteccion (B5b.4)

    public enum Autodetect: Equatable {
        /// Exactamente un perfil casa: se usa.
        case unique(DeviceProfile)
        /// Varios casan: **no se elige**, se pregunta.
        case ambiguous([DeviceProfile])
        /// Ninguno casa.
        case none
    }

    /// Busca el perfil cuyo `[match]` (comodines `*`) case con alguno de los
    /// nombres de puerto MIDI o de dispositivo de audio presentes. Si hay empate
    /// no decide: devuelve `.ambiguous` (criterio de B5b.4).
    public func autodetect(midiPortNames: [String], audioDeviceNames: [String]) -> Autodetect {
        let hits = usableProfiles.filter { p in
            if let g = p.match.midiPort, midiPortNames.contains(where: { GlobMatch.matches(pattern: g, $0) }) {
                return true
            }
            if let g = p.match.audioDevice, audioDeviceNames.contains(where: { GlobMatch.matches(pattern: g, $0) }) {
                return true
            }
            return false
        }
        switch hits.count {
        case 0:  return .none
        case 1:  return .unique(hits[0])
        default: return .ambiguous(hits.sorted { $0.id < $1.id })
        }
    }
}
