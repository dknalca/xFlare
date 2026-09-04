// SPDX-License-Identifier: GPL-3.0-only

import XFPrimitives

/// Fuente de fader por **MIDI CC**. Misma estructura que `HIDFaderSource`: la
/// conexion con CoreMIDI (crear el cliente/puerto, andar el `MIDIPacketList`) es
/// hardware y vive en `MidiFaderConnector`; aqui la fuente se **alimenta por
/// fuera** con `ingest(...)`, asi la decodificacion y la binarizacion se prueban
/// sin mesa.
public final class MidiFaderSource: FaderSource {

    public let config: MidiCrossfaderConfig
    private var binarizer: FaderBinarizer
    private var last: FaderSample?
    private var running = false

    /// Se llama cuando `isOpen` CAMBIA (no en cada mensaje CC: el crossfader
    /// manda decenas de mensajes por segundo mientras se mueve, la mayoría
    /// sin cruzar el umbral). Quien escuche esto no tiene que sondear
    /// `latest()`; lo usa `AppModel` para avisar a la práctica en vivo.
    public var onChange: ((FaderSample) -> Void)?

    public init(config: MidiCrossfaderConfig, binarizer: FaderBinarizer) {
        self.config = config
        self.binarizer = binarizer
    }

    public var isConnected: Bool { running }

    public func start() throws {
        running = true
        last = nil
    }

    public func stop() { running = false }

    public func latest() -> FaderSample? { last }

    /// Procesa un mensaje MIDI de 3 bytes (status, data1, data2). El conector lo
    /// llama por cada mensaje completo del `MIDIPacketList`. Ignora todo lo que
    /// no sea un Control Change del CC y canal configurados.
    public func ingest(status: UInt8, data1: UInt8, data2: UInt8, hostTime: UInt64) {
        guard running else { return }
        guard status & 0xF0 == 0xB0 else { return }            // 0xB_ = Control Change
        let channel = Int(status & 0x0F) + 1                    // 1..16
        guard config.accepts(channel: channel) else { return }
        guard Int(data1) == config.cc else { return }
        guard let v = config.value(fromCC: Int(data2)) else { return }

        let open = binarizer.update(rawValue: v)
        let sample = FaderSample(hostTime: hostTime, value: v, isOpen: open)
        let changed = last?.isOpen != open
        last = sample
        if changed { onChange?(sample) }
    }

    /// Version comoda para tests / bytes ya troceados.
    public func ingest(bytes: [UInt8], hostTime: UInt64) {
        for m in MidiFaderSource.messages(from: bytes) {
            ingest(status: m.status, data1: m.data1, data2: m.data2, hostTime: hostTime)
        }
    }

    /// Trocea un flujo de bytes MIDI en mensajes de canal completos, respetando
    /// el **status en ejecucion** (running status) y saltando SysEx y los bytes
    /// de tiempo real. Lo usa `MidiFaderConnector` al andar el `MIDIPacketList`.
    /// Para mensajes de un solo dato (`0xC_`, `0xD_`), `data2` va a 0.
    public static func messages(from bytes: [UInt8]) -> [(status: UInt8, data1: UInt8, data2: UInt8)] {
        var out: [(UInt8, UInt8, UInt8)] = []
        var status: UInt8 = 0
        var data: [UInt8] = []
        var inSysEx = false

        func expectedDataCount(_ s: UInt8) -> Int {
            switch s & 0xF0 {
            case 0xC0, 0xD0: return 1
            case 0x80, 0x90, 0xA0, 0xB0, 0xE0: return 2
            default: return 0
            }
        }
        func flushIfComplete() {
            let n = expectedDataCount(status)
            guard n > 0, data.count == n else { return }
            out.append((status, data[0], n == 2 ? data[1] : 0))
            data.removeAll(keepingCapacity: true)
        }

        for b in bytes {
            if b == 0xF0 { inSysEx = true; status = 0; continue }
            if b == 0xF7 { inSysEx = false; continue }
            if inSysEx { continue }
            if b >= 0xF8 { continue }                 // tiempo real: no rompe running status
            if b >= 0x80 {                            // nuevo status
                if b >= 0xF0 { status = 0; data.removeAll(keepingCapacity: true) }  // system common
                else { status = b; data.removeAll(keepingCapacity: true) }
                continue
            }
            guard status != 0 else { continue }        // dato sin status previo
            data.append(b)
            flushIfComplete()
        }
        return out
    }
}
