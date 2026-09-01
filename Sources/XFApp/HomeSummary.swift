// SPDX-License-Identifier: GPL-3.0-only

/// Lo que necesita pintar el Home (`docs/UI_DESIGN.md` §3.2): la rejilla de la
/// matriz, la racha, los minutos de hoy y la tarjeta "Continuar".
///
/// Value type puro: lo arma `XFApp` con lo que saca de `XFPersistence` /
/// `XFNotation`. Aquí no hay consultas.
public struct HomeSummary: Equatable, Sendable {

    /// La tarjeta grande: el ejercicio en curso y su BPM actual.
    public struct ContinueTarget: Equatable, Sendable {
        public var scratchId: String
        public var name: String
        public var bpm: Int
        public init(scratchId: String, name: String, bpm: Int) {
            self.scratchId = scratchId
            self.name = name
            self.bpm = bpm
        }
    }

    public var cells: [MatrixCell]
    public var streakDays: Int
    public var minutesToday: Int
    public var continueTarget: ContinueTarget?
    /// Miniatura TTM por `scratchId`, solo para las celdas donde se muestra
    /// (ahora mismo un par del Nivel 1). El resto no la lleva.
    public var thumbnails: [String: TTMThumbnail]

    public init(cells: [MatrixCell], streakDays: Int, minutesToday: Int,
                continueTarget: ContinueTarget? = nil,
                thumbnails: [String: TTMThumbnail] = [:]) {
        self.cells = cells
        self.streakDays = streakDays
        self.minutesToday = minutesToday
        self.continueTarget = continueTarget
        self.thumbnails = thumbnails
    }

    /// Celdas agrupadas por nivel, en orden ("L1", "L2", …).
    public var cellsByLevel: [(level: String, cells: [MatrixCell])] {
        let groups = Dictionary(grouping: cells, by: \.level)
        return groups.keys.sorted().map { ($0, groups[$0] ?? []) }
    }

    /// Cuántos scratches ha dominado el usuario (la "colección").
    public var masteredCount: Int {
        cells.filter { $0.state == .mastered }.count
    }

    /// `true` si hoy ya cumple el mínimo honesto de práctica (`CURRICULUM` §7).
    public func meetsDailyMinimum(minutes: Int = 10) -> Bool {
        minutesToday >= minutes
    }
}
