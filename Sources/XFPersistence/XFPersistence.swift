// SPDX-License-Identifier: GPL-3.0-only
//
// XFPersistence — CAPA 1. GRDB 6.x: base local (sesiones, intentos, progreso
// agregado, repeticion espaciada, ajustes, calibracion por dispositivo).
// Sin UI, sin hardware. Depende de XFNotation y de GRDB.
//
// Estado: B10.1 hecho — `XFDatabase` abre el fichero SQLite y `Schema` define
// el migrador con la migracion `v1` (todas las tablas del bloque B10). El
// codigo de consulta tipado llega en B10.2 y siguientes.

/// Espacio de nombres y version del contrato publico de XFPersistence.
public enum XFPersistence {
    public static let apiVersion = 1
}
