// SPDX-License-Identifier: GPL-3.0-only

/// Un scratch completo: dos carriles sincronizados sobre una rejilla de ticks
/// (docs/NOTATION.md). Es el resultado de `Composer.compose` y el elemento de
/// `data/scratches/library-v0.1.json`.
///
/// El orden de las propiedades sigue el de la libreria de referencia para que la
/// serializacion salga en el mismo orden de claves.
public struct Scratch: Codable, Sendable, Equatable {

    /// Id estable, kebab-case (`"flare-2c"`).
    public var id: String
    /// Nombre legible.
    public var name: String
    /// Familia tecnica (`"flare"`, `"transformer"`...).
    public var family: String
    /// Nivel de dificultad 1..10.
    public var level: Int
    /// Id del patron de mano usado.
    public var hand: String
    /// Id del patron de fader usado.
    public var fader: String
    /// Subdivision, `"num/den"`.
    public var div: String
    /// Cuantos ciclos del patron de mano encadena.
    public var cycles: Int
    /// Tecnica que hereda del patron de fader.
    public var technique: String
    /// Pulsos por negra (siempre 480, ADR-016).
    public var ppq: Int
    /// BPM de referencia para el que se penso el patron (no es vinculante: el
    /// tempo lo pone la reproduccion).
    public var bpmReference: Int
    /// Duracion total en ticks.
    public var lengthTicks: Int
    /// Numero de cierres de fader (cada uno es un click puntuable).
    public var clickCount: Int
    /// Carril de disco.
    public var record: [RecordPhase]
    /// Carril de fader, ya limpio (sin estados repetidos consecutivos).
    public var faderEvents: [FaderEvent]
    /// Nota para el usuario.
    public var notes: String

    public init(id: String, name: String, family: String, level: Int,
                hand: String, fader: String, div: String, cycles: Int,
                technique: String, ppq: Int, bpmReference: Int,
                lengthTicks: Int, clickCount: Int,
                record: [RecordPhase], faderEvents: [FaderEvent], notes: String) {
        self.id = id
        self.name = name
        self.family = family
        self.level = level
        self.hand = hand
        self.fader = fader
        self.div = div
        self.cycles = cycles
        self.technique = technique
        self.ppq = ppq
        self.bpmReference = bpmReference
        self.lengthTicks = lengthTicks
        self.clickCount = clickCount
        self.record = record
        self.faderEvents = faderEvents
        self.notes = notes
    }
}
