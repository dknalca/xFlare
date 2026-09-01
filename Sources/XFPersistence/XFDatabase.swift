// SPDX-License-Identifier: GPL-3.0-only

import Foundation
import GRDB

/// La base de datos local de xFlare: un fichero SQLite que el usuario puede
/// copiar (soberanía del usuario, `CLAUDE.md` §3). Envuelve GRDB y aplica las
/// migraciones de `Schema` al abrir.
///
/// Usa una `DatabaseQueue` (una sola conexión, accesos serializados). Para una
/// app de práctica en local no hace falta el `DatabasePool`; si algún día el
/// perfilado dice otra cosa, se cambia aquí sin tocar a los que la usan.
///
/// Las lecturas y escrituras tipadas (histórico, progreso, repetición
/// espaciada...) se añaden sobre `writer` en las tareas B10.2 y siguientes.
public struct XFDatabase {

    /// La conexión de escritura. `DatabaseQueue` conforma `DatabaseWriter`, que
    /// también permite leer.
    public let writer: DatabaseWriter

    /// Abre (o crea) la base en `url` y aplica las migraciones pendientes.
    public init(url: URL) throws {
        let queue = try DatabaseQueue(path: url.path, configuration: Self.configuration)
        try Schema.migrator.migrate(queue)
        self.writer = queue
    }

    /// Base en memoria, para tests. Mismo migrador que la de disco.
    public static func inMemory() throws -> XFDatabase {
        let queue = try DatabaseQueue(configuration: configuration)
        try Schema.migrator.migrate(queue)
        return XFDatabase(writer: queue)
    }

    private init(writer: DatabaseWriter) {
        self.writer = writer
    }

    /// `true` si la base tiene aplicadas todas las migraciones que conoce esta
    /// versión de la app.
    public func isUpToDate() throws -> Bool {
        try writer.read(Schema.migrator.hasCompletedMigrations)
    }

    // MARK: - configuración

    private static var configuration: Configuration {
        var config = Configuration()
        // Las claves foráneas (borrado en cascada de `attemptEvent`, `SET NULL`
        // de `attempt.sessionId`) tienen que estar activas. GRDB ya las activa
        // por defecto; lo dejamos explícito para que no dependa del defecto.
        config.foreignKeysEnabled = true
        return config
    }
}
