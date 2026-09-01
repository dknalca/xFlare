// SPDX-License-Identifier: GPL-3.0-only

/// La pantalla "Mi mesa" (`docs/UI_DESIGN.md` §3.8): los perfiles de mesa
/// disponibles, con su insignia de verificación y si hay calibración guardada.
/// Value types puros; la vista los pinta y el "probar en vivo" va por fuera.

public struct MyTableRow: Equatable, Sendable, Identifiable {

    public enum Source: String, Sendable { case bundled, user }

    public var profileId: String
    public var name: String
    public var source: Source
    /// `true` si el perfil está verificado contra hardware real (si no, lleva el
    /// aviso "SIN VERIFICAR" que da `XFProfiles`).
    public var verified: Bool
    /// `true` si hay una `DeviceCalibration` guardada para este perfil.
    public var hasCalibration: Bool
    /// Última latencia medida con este perfil, ms.
    public var latencyMs: Double?

    public var id: String { profileId }

    public init(profileId: String, name: String, source: Source, verified: Bool,
                hasCalibration: Bool, latencyMs: Double? = nil) {
        self.profileId = profileId
        self.name = name
        self.source = source
        self.verified = verified
        self.hasCalibration = hasCalibration
        self.latencyMs = latencyMs
    }
}

public struct MyTable: Equatable, Sendable {

    public var rows: [MyTableRow]
    /// El perfil activo ahora mismo, o `nil` si no hay ninguno elegido.
    public var activeProfileId: String?

    public init(rows: [MyTableRow], activeProfileId: String? = nil) {
        self.rows = rows
        self.activeProfileId = activeProfileId
    }

    public var active: MyTableRow? {
        activeProfileId.flatMap { id in rows.first { $0.profileId == id } }
    }

    /// Filas ordenadas: primero el activo, luego los verificados, luego el resto,
    /// y dentro de cada grupo por nombre.
    public var sorted: [MyTableRow] {
        rows.sorted { a, b in
            func rank(_ r: MyTableRow) -> Int {
                if r.profileId == activeProfileId { return 0 }
                return r.verified ? 1 : 2
            }
            let (ra, rb) = (rank(a), rank(b))
            return ra != rb ? ra < rb : a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
        }
    }

    public var verifiedCount: Int { rows.filter(\.verified).count }
    public var calibratedCount: Int { rows.filter(\.hasCalibration).count }
}
