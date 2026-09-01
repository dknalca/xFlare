// SPDX-License-Identifier: GPL-3.0-only

/// Parametros de forma de una sesion: cuantas series tiene el bloque principal y
/// cuantos compases dura cada una (`docs/CURRICULUM.md` §3: "3 series x 4
/// compases").
///
/// La duracion del calentamiento y del descanso NO vive aqui: la maquina de
/// estados avanza por eventos (`beginSeries()`, `endRest()`), no por reloj. Quien
/// conduce la sesion (el driver de audio, contando compases con `XFClock`)
/// decide cuando disparar esos eventos. Asi la maquina es determinista y
/// testeable sin tiempo real, igual que `Transport`.
public struct SessionConfig: Equatable, Sendable {

    /// Numero de series del bloque principal. `docs/CURRICULUM.md` §3 usa 3.
    public let seriesCount: Int

    /// Compases por serie. `docs/CURRICULUM.md` §3 usa 4.
    public let barsPerSeries: Int

    public init(seriesCount: Int = 3, barsPerSeries: Int = 4) {
        precondition(seriesCount >= 1, "una sesion necesita al menos una serie")
        precondition(barsPerSeries >= 1, "una serie necesita al menos un compas")
        self.seriesCount = seriesCount
        self.barsPerSeries = barsPerSeries
    }

    /// Valores por defecto del currículo (3 series de 4 compases).
    public static let standard = SessionConfig()
}
