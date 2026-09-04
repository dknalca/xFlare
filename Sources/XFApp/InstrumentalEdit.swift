// SPDX-License-Identifier: GPL-3.0-only

import Foundation

/// Ajustes que el usuario ha hecho sobre una instrumental de la Librería en el
/// **editor** (`InstrumentalEditorView`), antes de practicar encima. Se guardan
/// por ruta de fichero (`InstrumentalEditStore`).
///
/// Todo opcional: si un campo es `nil` / vacío, la práctica usa lo que detectó
/// `TempoAnalyzer`.
public struct InstrumentalEdit: Codable, Equatable {

    /// BPM fijado a mano. `nil` = usar el detectado.
    public var bpm: Double?
    /// Segundo del fichero donde cae el **"1"** (primer tiempo del primer
    /// compás). `nil` = usar la fase detectada.
    public var downbeatSeconds: Double?
    /// Tiempos por compás (para dibujar la rejilla). Normalmente 4.
    public var beatsPerBar: Int
    /// Puntos Cue con nombre para saltar a partes concretas.
    public var cues: [Cue]
    /// Regiones para hacer **loop infinito** de un trozo. Solo una puede estar
    /// activa a la vez (`activeLoopID`).
    public var loops: [LoopRegion]
    /// La región de loop activa (o `nil` = base entera).
    public var activeLoopID: UUID?

    public struct Cue: Codable, Equatable, Identifiable {
        public var id: UUID
        public var name: String
        public var atSeconds: Double
        public init(id: UUID = UUID(), name: String, atSeconds: Double) {
            self.id = id
            self.name = name
            self.atSeconds = max(0, atSeconds)
        }
    }

    public struct LoopRegion: Codable, Equatable, Identifiable {
        public var id: UUID
        public var name: String
        public var startSeconds: Double
        public var endSeconds: Double
        public init(id: UUID = UUID(), name: String, startSeconds: Double, endSeconds: Double) {
            self.id = id
            self.name = name
            let a = max(0, min(startSeconds, endSeconds))
            let b = max(startSeconds, endSeconds)
            self.startSeconds = a
            self.endSeconds = b
        }
    }

    public init(bpm: Double? = nil, downbeatSeconds: Double? = nil,
                beatsPerBar: Int = 4, cues: [Cue] = [], loops: [LoopRegion] = [],
                activeLoopID: UUID? = nil) {
        self.bpm = bpm.map { min(300, max(20, $0)) }
        self.downbeatSeconds = downbeatSeconds.map { max(0, $0) }
        self.beatsPerBar = min(12, max(1, beatsPerBar))
        self.cues = cues.sorted { $0.atSeconds < $1.atSeconds }
        self.loops = loops
        // la región activa tiene que existir
        self.activeLoopID = loops.contains { $0.id == activeLoopID } ? activeLoopID : nil
    }

    /// La región de loop activa, si la hay.
    public var activeLoop: LoopRegion? {
        guard let id = activeLoopID else { return nil }
        return loops.first { $0.id == id }
    }

    /// `true` si no aporta nada sobre la detección automática (no se guarda).
    public var isEmpty: Bool {
        bpm == nil && downbeatSeconds == nil && beatsPerBar == 4
            && cues.isEmpty && loops.isEmpty
    }
}
