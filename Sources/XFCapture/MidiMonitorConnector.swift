// SPDX-License-Identifier: GPL-3.0-only

import CoreMIDI
import Foundation

/// Monitor **genérico** de CoreMIDI: se engancha a todas las fuentes MIDI y
/// entrega cada mensaje ya troceado (status/data1/data2) a un bloque. Lo usa el
/// "MIDI Learn" de Ajustes (mientras está abierto, escucha; al llegar un
/// mensaje con el campo armado, esa nota/CC pasa a ser la asignación) Y,
/// durante toda la sesión real (`AppModel.midiMonitor`, F.61), reparte cada
/// mensaje a `MidiCommandSource` y a `MidiFaderSource` a la vez — es EL
/// conector CoreMIDI de producción, no uno específico del crossfader (ese,
/// `MidiFaderConnector`, se planeó pero nunca llegó a usarse y se borró).
///
/// **Sin tests propios**: es solo la conexión con el sistema (confirmada con
/// hardware real, ADR-021/F.61). El troceo del flujo (running status, SysEx,
/// tiempo real) está probado en `MidiFaderSource`.
public final class MidiMonitorConnector {

    /// Se llama (en el hilo de CoreMIDI) por cada mensaje de canal recibido.
    public var onMessage: ((_ status: UInt8, _ data1: UInt8, _ data2: UInt8) -> Void)?

    private var client = MIDIClientRef()
    private var inputPort = MIDIPortRef()
    private var connected: [MIDIEndpointRef] = []

    public init() {}

    /// ¿Hay al menos una fuente MIDI conectada?
    public private(set) var isOpen = false

    /// Abre el cliente y se conecta a todas las fuentes MIDI presentes. Lanza si
    /// CoreMIDI falla.
    public func open() throws {
        guard !isOpen else { return }

        var status = MIDIClientCreateWithBlock("xFlare.monitor" as CFString, &client) { _ in }
        guard status == noErr else { throw MidiError.osStatus(status, "MIDIClientCreate") }

        status = MIDIInputPortCreateWithBlock(client, "xFlare.monitor.in" as CFString, &inputPort) {
            [weak self] listPtr, _ in
            self?.handle(packetList: listPtr)
        }
        guard status == noErr else { throw MidiError.osStatus(status, "MIDIInputPortCreate") }

        let n = MIDIGetNumberOfSources()
        for i in 0..<n {
            let src = MIDIGetSource(i)
            guard src != 0 else { continue }
            if MIDIPortConnectSource(inputPort, src, nil) == noErr {
                connected.append(src)
            }
        }
        isOpen = true
    }

    public func close() {
        for src in connected { MIDIPortDisconnectSource(inputPort, src) }
        connected.removeAll()
        if inputPort != 0 { MIDIPortDispose(inputPort); inputPort = 0 }
        if client != 0 { MIDIClientDispose(client); client = 0 }
        isOpen = false
    }

    deinit { close() }

    private func handle(packetList: UnsafePointer<MIDIPacketList>) {
        var packet = packetList.pointee.packet
        for _ in 0..<packetList.pointee.numPackets {
            withUnsafePointer(to: &packet) { p in
                let length = Int(p.pointee.length)
                let bytes: [UInt8] = withUnsafeBytes(of: p.pointee.data) { raw in
                    (0..<length).map { raw[$0] }
                }
                for m in MidiFaderSource.messages(from: bytes) {
                    onMessage?(m.status, m.data1, m.data2)
                }
            }
            packet = MIDIPacketNext(&packet).pointee
        }
    }

    public enum MidiError: Error, CustomStringConvertible {
        case osStatus(OSStatus, String)
        public var description: String {
            switch self {
            case .osStatus(let s, let ctx): return "\(ctx) falló (OSStatus \(s))"
            }
        }
    }
}
