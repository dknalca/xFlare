// SPDX-License-Identifier: GPL-3.0-only

import Foundation
import GRDB

/// B10.4 — calibración por dispositivo (guardar, leer, listar, borrar).
extension XFDatabase {

    /// Inserta o reemplaza la calibración de un dispositivo (clave `deviceKey`).
    public func saveCalibration(_ calibration: DeviceCalibration) throws {
        try writer.write { try calibration.save($0) }
    }

    public func calibration(deviceKey: String) throws -> DeviceCalibration? {
        try writer.read { try DeviceCalibration.fetchOne($0, key: deviceKey) }
    }

    /// Todas las calibraciones guardadas, de la más reciente a la más antigua
    /// (para la pantalla "Mi mesa").
    public func allCalibrations() throws -> [DeviceCalibration] {
        try writer.read { db in
            try DeviceCalibration
                .order(Column("updatedAt").desc)
                .fetchAll(db)
        }
    }

    public func deleteCalibration(deviceKey: String) throws {
        _ = try writer.write { try DeviceCalibration.deleteOne($0, key: deviceKey) }
    }
}
