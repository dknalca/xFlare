// SPDX-License-Identifier: GPL-3.0-only

import Foundation
import Combine

/// El asistente de mapeo MIDI/HID (`docs/UI_DESIGN.md` §3.9): un monitor de
/// mensajes en crudo y un "MIDI Learn" para el crossfader. Si en **5 s** no llega
/// ningún mensaje MIDI, propone pasar a `audio_return` (tono piloto, ADR-021).
///
/// No mira el reloj: quien lo usa le pasa `now` en cada llamada. Así el timeout
/// se testea sin esperar 5 s de verdad.
public final class MidiMappingModel: ObservableObject {

    public enum Target: String, Sendable { case crossfader }

    /// Los últimos mensajes en crudo, del más reciente al más antiguo (tope 200).
    @Published public private(set) var rawLog: [String] = []
    /// Qué se está aprendiendo ahora, o `nil`.
    @Published public private(set) var learning: Target?
    /// CC MIDI aprendido para el crossfader.
    @Published public private(set) var crossfaderCC: Int?
    /// `true` en cuanto ha llegado el primer mensaje MIDI.
    @Published public private(set) var sawMidi = false

    private var listeningSince: Date?
    private let logCap = 200
    /// Segundos sin MIDI tras los que se propone `audio_return`.
    public let midiTimeout: TimeInterval = 5

    public init() {}

    public func startListening(now: Date) {
        listeningSince = now
        sawMidi = false
        rawLog.removeAll(keepingCapacity: true)
    }

    public func learn(_ target: Target) { learning = target }
    public func cancelLearn() { learning = nil }

    /// Un mensaje MIDI en crudo. `cc` no nil si es un Control Change.
    public func receivedMIDI(raw: String, cc: Int?, value: Int?, now: Date) {
        sawMidi = true
        push("MIDI  \(raw)")
        if let cc, learning == .crossfader {
            crossfaderCC = cc
            learning = nil
        }
    }

    /// Un input report HID en crudo (para mesas que exponen el fader por HID).
    public func receivedHID(raw: String, now: Date) {
        push("HID   \(raw)")
    }

    /// `true` si ya toca proponer `audio_return`: llevamos escuchando más de
    /// `midiTimeout` y no ha llegado ni un mensaje MIDI.
    public func shouldSuggestAudioReturn(now: Date) -> Bool {
        guard let since = listeningSince, !sawMidi else { return false }
        return now.timeIntervalSince(since) >= midiTimeout
    }

    public var isMapped: Bool { crossfaderCC != nil }

    private func push(_ line: String) {
        rawLog.insert(line, at: 0)
        if rawLog.count > logCap { rawLog.removeLast(rawLog.count - logCap) }
    }
}
