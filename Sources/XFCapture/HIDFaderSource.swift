// SPDX-License-Identifier: GPL-3.0-only

import XFPrimitives

/// Fuente de fader por **HID** (ruta de respaldo si la mesa no expone el
/// crossfader por MIDI — ADR-021).
///
/// El pegamento con `IOHIDManager` (casar el dispositivo, registrar el callback
/// de input report) es hardware y va en B6.4, junto al de MIDI. Aquí la fuente se
/// **alimenta por fuera** con `ingest(report:hostTime:)`, igual que
/// `ReplayFaderSource` se alimenta con `seek`. Así la decodificación y la
/// binarización se prueban sin mesa.
public final class HIDFaderSource: FaderSource {

    public let config: HIDCrossfaderConfig
    private var binarizer: FaderBinarizer
    private var last: FaderSample?
    private var running = false

    public init(config: HIDCrossfaderConfig, binarizer: FaderBinarizer) {
        self.config = config
        self.binarizer = binarizer
    }

    public var isConnected: Bool { running }

    /// Marca la fuente lista. La conexión real del `IOHIDManager` la hace el
    /// conector de B6.4 y luego llama a `ingest(...)`.
    public func start() throws {
        running = true
        last = nil
    }

    public func stop() {
        running = false
    }

    public func latest() -> FaderSample? { last }

    /// Lo llama el conector IOHID cada vez que llega un input report del fader.
    /// `data` son los bytes del report SIN el byte de report ID.
    public func ingest(report data: [UInt8], hostTime: UInt64) {
        guard running, let v = config.value(fromReport: data) else { return }
        let open = binarizer.update(rawValue: v)
        last = FaderSample(hostTime: hostTime, value: v, isOpen: open)
    }
}
