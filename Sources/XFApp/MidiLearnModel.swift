// SPDX-License-Identifier: GPL-3.0-only

import Foundation
import Combine
import XFCapture

/// "MIDI Learn" de Ajustes → *MIDI · comandos*: seleccionas un comando, pulsas
/// **Aprender**, y el siguiente control MIDI que muevas queda asignado a ese
/// comando.
///
/// Mientras la pantalla de Ajustes está abierta, `start()` engancha un
/// `MidiMonitorConnector` a todas las fuentes MIDI. `stop()` lo suelta.
public final class MidiLearnModel: ObservableObject {

    /// El monitor está escuchando (hay CoreMIDI abierto).
    @Published public private(set) var running = false
    /// Comando seleccionado en la lista (al que apuntará "Aprender").
    @Published public var selected: PracticeCommand?
    /// Estamos esperando el próximo mensaje MIDI para asignarlo.
    @Published public private(set) var armed = false
    /// Último mensaje visto, para el monitor ("cc 1·24", "note 1·36").
    @Published public private(set) var lastSeen: String?
    /// Si CoreMIDI no se pudo abrir.
    @Published public private(set) var error: String?

    /// Se llama al aprender: comando + asignación. `AppModel` lo persiste.
    public var onLearn: ((PracticeCommand, MidiBinding) -> Void)?

    private let monitor: MidiMonitorConnector

    public init(monitor: MidiMonitorConnector = MidiMonitorConnector()) {
        self.monitor = monitor
        self.monitor.onMessage = { [weak self] s, d1, d2 in
            // el bloque de CoreMIDI llega en su propio hilo
            DispatchQueue.main.async { self?.handle(status: s, data1: d1, data2: d2) }
        }
    }

    public func start() {
        guard !running else { return }
        do {
            try monitor.open()
            running = true
            error = nil
        } catch {
            self.error = "\(error)"
            running = false
        }
    }

    public func stop() {
        monitor.close()
        running = false
        armed = false
    }

    /// Selecciona un comando (o lo deselecciona si ya estaba).
    public func select(_ cmd: PracticeCommand) {
        selected = (selected == cmd) ? nil : cmd
        armed = false
    }

    /// Arma la escucha para el comando seleccionado.
    public func arm() {
        guard selected != nil else { return }
        armed = true
    }

    public func cancel() { armed = false }

    /// **Puro** (sin CoreMIDI): procesa un mensaje. Actualiza `lastSeen` y, si
    /// está armado, asigna y desarma. Se llama en el hilo principal.
    func handle(status: UInt8, data1: UInt8, data2: UInt8) {
        let hi = status & 0xF0
        let ch = Int(status & 0x0F) + 1
        let kind = hi == 0xB0 ? "cc" : ((hi == 0x90 || hi == 0x80) ? "note" : nil)
        if let kind { lastSeen = "\(kind) \(ch)·\(data1)" }

        guard armed, let cmd = selected,
              let bind = MidiBinding.learned(status: status, data1: data1, data2: data2)
        else { return }
        armed = false
        onLearn?(cmd, bind)
    }
}
