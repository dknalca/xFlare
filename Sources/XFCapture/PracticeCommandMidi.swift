// SPDX-License-Identifier: GPL-3.0-only

import XFProfiles

/// Comandos de práctica que se pueden disparar por MIDI (además del teclado):
/// transporte discreto + el fader como momentáneo + un par de toggles.
public enum PracticeCommand: String, CaseIterable, Sendable, Codable {
    case cue                // vuelve el sample al inicio (tecla 1)
    case restartBase        // reinicia la instrumental (tecla 2)
    case freeze             // congela / descongela (tecla P)
    case record             // arranca / para la grabación de línea
    case bpmUp              // BPM +1
    case bpmDown            // BPM −1
    case fader              // momentáneo: pulsado = crossfader cerrado (Espacio)
    case metronome          // toggle del metrónomo
    case callResponse       // toggle de "Repite conmigo"

    /// Clave en la sección `[transport]` del `.conf` (`command.cue`, …).
    public var confKey: String {
        switch self {
        case .cue:          return "command.cue"
        case .restartBase:  return "command.restart_base"
        case .freeze:       return "command.freeze"
        case .record:       return "command.record"
        case .bpmUp:        return "command.bpm_up"
        case .bpmDown:      return "command.bpm_down"
        case .fader:        return "command.fader"
        case .metronome:    return "command.metronome"
        case .callResponse: return "command.call_response"
        }
    }

    /// El fader es el único momentáneo: pulsar = cerrado, soltar = abierto.
    public var isMomentary: Bool { self == .fader }

    /// Nombre para la UI (Ajustes → MIDI).
    public var label: String {
        switch self {
        case .cue:          return "Cue del sample"
        case .restartBase:  return "Reiniciar la base"
        case .freeze:       return "Congelar"
        case .record:       return "Grabar línea"
        case .bpmUp:        return "BPM +1"
        case .bpmDown:      return "BPM −1"
        case .fader:        return "Fader cerrado (momentáneo)"
        case .metronome:    return "Metrónomo"
        case .callResponse: return "Repite conmigo"
        }
    }
}

/// Lo que emite `MidiCommandSource` al recibir un mensaje mapeado.
public enum PracticeCommandEvent: Equatable, Sendable {
    /// Disparo discreto (cue, freeze, record, bpm…).
    case trigger(PracticeCommand)
    /// El fader: `true` = cerrado (nota pulsada / CC ≥ 64), `false` = abierto.
    case faderClosed(Bool)
}

/// Asignación de un mensaje MIDI a un comando: nota o CC, canal (1-16, `0` =
/// cualquiera) y número (0-127). Se serializa como `"note:1:36"` / `"cc:0:24"`.
public struct MidiBinding: Equatable, Sendable, Codable {

    public enum Kind: String, Sendable, Codable { case note, cc }

    public var kind: Kind
    public var channel: Int   // 1…16, o 0 = cualquiera
    public var number: Int    // 0…127

    public init(kind: Kind, channel: Int, number: Int) {
        self.kind = kind
        self.channel = max(0, min(16, channel))
        self.number = max(0, min(127, number))
    }

    /// Parsea `"note:1:36"`, `"cc:0:24"`, `"note:2:0x30"`. `nil` si no cuadra.
    public init?(_ text: String) {
        let parts = text.split(separator: ":").map { $0.trimmingCharacters(in: .whitespaces) }
        guard parts.count == 3, let kind = Kind(rawValue: parts[0].lowercased()),
              let ch = Int(parts[1]), let num = parseInt(parts[2]) else { return nil }
        self.init(kind: kind, channel: ch, number: num)
    }

    public var text: String { "\(kind.rawValue):\(channel):\(number)" }

    /// ¿Este mensaje MIDI (ya troceado) casa con esta asignación? (el sentido
    /// on/off lo resuelve `MidiCommandMap.event`).
    func matches(status: UInt8, data1: UInt8) -> Bool {
        let hi = status & 0xF0
        let ch = Int(status & 0x0F) + 1
        let kindOK = kind == .cc ? (hi == 0xB0) : (hi == 0x90 || hi == 0x80)
        return kindOK && Int(data1) == number && (channel == 0 || channel == ch)
    }
}

/// Tabla de asignaciones + decodificador **puro**: dado un mensaje MIDI, ¿qué
/// evento de comando? El conector CoreMIDI (`MidiFaderConnector`, hardware) lo
/// alimenta con `ingest`; aquí solo se decide.
public struct MidiCommandMap: Equatable, Sendable {

    public var bindings: [PracticeCommand: MidiBinding]

    public init(bindings: [PracticeCommand: MidiBinding] = [:]) {
        self.bindings = bindings
    }

    /// Lee la sección `[transport]` de un perfil (`command.cue = note:1:36`, …).
    public static func fromProfile(_ ini: INIDocument) -> MidiCommandMap {
        var b: [PracticeCommand: MidiBinding] = [:]
        for cmd in PracticeCommand.allCases {
            if let raw = ini.get("transport", cmd.confKey), let bind = MidiBinding(raw) {
                b[cmd] = bind
            }
        }
        return MidiCommandMap(bindings: b)
    }

    /// El `map` del perfil con los overrides del usuario por encima.
    public func merging(userOverrides: [PracticeCommand: MidiBinding]) -> MidiCommandMap {
        var b = bindings
        for (k, v) in userOverrides { b[k] = v }
        return MidiCommandMap(bindings: b)
    }

    /// Decodifica un mensaje de 3 bytes. Note On (vel > 0) / CC ≥ 64 → dispara
    /// el comando (o `faderClosed(true)`). Note Off / Note On vel 0 / CC < 64 →
    /// solo para el `fader`: `faderClosed(false)`.
    public func event(status: UInt8, data1: UInt8, data2: UInt8) -> PracticeCommandEvent? {
        let hi = status & 0xF0
        let isNoteOff = hi == 0x80 || (hi == 0x90 && data2 == 0)
        let isNoteOn  = hi == 0x90 && data2 > 0
        let isCC      = hi == 0xB0
        guard isNoteOff || isNoteOn || isCC else { return nil }

        for (cmd, bind) in bindings where bind.matches(status: status, data1: data1) {
            if cmd == .fader {
                let closed = isNoteOn || (isCC && data2 >= 64)
                return .faderClosed(closed)
            }
            // discretos: solo al "activar" (Note On, o CC que sube de 64)
            if isNoteOn || (isCC && data2 >= 64) { return .trigger(cmd) }
            return nil
        }
        return nil
    }
}

/// Fuente de **comandos** por MIDI. Como `MidiFaderSource`: la conexión CoreMIDI
/// vive en `MidiFaderConnector` (hardware); aquí se alimenta por fuera con
/// `ingest` y se prueba sin mesa.
public final class MidiCommandSource {

    public var map: MidiCommandMap
    /// Se llama con cada evento decodificado.
    public var onCommand: ((PracticeCommandEvent) -> Void)?

    public init(map: MidiCommandMap = MidiCommandMap()) { self.map = map }

    public func ingest(status: UInt8, data1: UInt8, data2: UInt8) {
        if let e = map.event(status: status, data1: data1, data2: data2) {
            onCommand?(e)
        }
    }

    /// Bytes crudos de un `MIDIPacket` (respeta running status vía
    /// `MidiFaderSource.messages`).
    public func ingest(bytes: [UInt8]) {
        for m in MidiFaderSource.messages(from: bytes) {
            ingest(status: m.status, data1: m.data1, data2: m.data2)
        }
    }
}

private func parseInt(_ s: String) -> Int? {
    if s.lowercased().hasPrefix("0x") { return Int(s.dropFirst(2), radix: 16) }
    return Int(s)
}
