// SPDX-License-Identifier: GPL-3.0-only

import CoreMIDI
import Foundation

/// El pegamento con **CoreMIDI clasico** (`MIDIPacketList`, `docs/PLATFORM_SUPPORT.md`):
/// crea el cliente y un puerto de entrada, se conecta a todas las fuentes MIDI y
/// alimenta un `MidiFaderSource` con cada mensaje.
///
/// **No tiene tests**: necesita un dispositivo MIDI real. La logica que si se
/// prueba (troceo del flujo con running status, decodificacion del CC) esta en
/// `MidiFaderSource`. Este fichero es solo la conexion con el sistema.
public final class MidiFaderConnector {

    private let source: MidiFaderSource
    private var client = MIDIClientRef()
    private var inputPort = MIDIPortRef()
    private var connected: [MIDIEndpointRef] = []

    public init(source: MidiFaderSource) {
        self.source = source
    }

    /// Abre el cliente y se engancha a todas las fuentes MIDI presentes. Lanza si
    /// CoreMIDI falla.
    public func open() throws {
        var status = MIDIClientCreateWithBlock("xFlare" as CFString, &client) { _ in }
        guard status == noErr else { throw MidiError.osStatus(status, "MIDIClientCreate") }

        // Puerto de entrada con bloque: recibe un MIDIPacketList por lote.
        status = MIDIInputPortCreateWithBlock(client, "xFlare.in" as CFString, &inputPort) {
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
    }

    public func close() {
        for src in connected { MIDIPortDisconnectSource(inputPort, src) }
        connected.removeAll()
        if inputPort != 0 { MIDIPortDispose(inputPort); inputPort = 0 }
        if client != 0 { MIDIClientDispose(client); client = 0 }
    }

    deinit { close() }

    // MARK: - lectura

    private func handle(packetList: UnsafePointer<MIDIPacketList>) {
        var packet = packetList.pointee.packet
        for _ in 0..<packetList.pointee.numPackets {
            withUnsafePointer(to: &packet) { p in
                let length = Int(p.pointee.length)
                let bytes: [UInt8] = withUnsafeBytes(of: p.pointee.data) { raw in
                    (0..<length).map { raw[$0] }
                }
                let hostTime = p.pointee.timeStamp   // dominio mach_absolute_time
                for m in MidiFaderSource.messages(from: bytes) {
                    source.ingest(status: m.status, data1: m.data1, data2: m.data2,
                                  hostTime: hostTime)
                }
            }
            packet = MIDIPacketNext(&packet).pointee
        }
    }

    public enum MidiError: Error, CustomStringConvertible {
        case osStatus(OSStatus, String)
        public var description: String {
            switch self {
            case .osStatus(let s, let ctx): return "\(ctx) fallo (OSStatus \(s))"
            }
        }
    }
}
