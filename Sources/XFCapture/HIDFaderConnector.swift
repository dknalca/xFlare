// SPDX-License-Identifier: GPL-3.0-only

import Foundation
import IOKit
import IOKit.hid
import XFClock

/// El pegamento con **`IOHIDManager`**: casa el dispositivo por vendor/product
/// (`HIDCrossfaderConfig`), y cuando aparece un dispositivo que encaja le
/// registra un callback de input report que alimenta un `HIDFaderSource`.
///
/// **No tiene tests**: necesita el dispositivo HID real. La decodificacion del
/// report (`HIDCrossfaderConfig.value(fromReport:)`) y la binarizacion
/// (`HIDFaderSource`) si estan probadas. Este fichero es solo la conexion.
///
/// Nota IOKit: el callback de input report a nivel de **manager** no acepta
/// buffer; hay que registrarlo por **dispositivo** con
/// `IOHIDDeviceRegisterInputReportCallback`. Por eso se engancha en el callback
/// de "dispositivo encontrado".
public final class HIDFaderConnector {

    private let source: HIDFaderSource
    private let config: HIDCrossfaderConfig
    private let manager: IOHIDManager
    /// Buffer que IOHID rellena en cada report. Vive tanto como el conector.
    private let reportBuffer: UnsafeMutableBufferPointer<UInt8>

    public init(source: HIDFaderSource, config: HIDCrossfaderConfig, maxReportSize: Int = 64) {
        self.source = source
        self.config = config
        self.manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        self.reportBuffer = .allocate(capacity: max(8, maxReportSize))
        self.reportBuffer.initialize(repeating: 0)
    }

    deinit {
        close()
        reportBuffer.deallocate()
    }

    /// Abre el manager y lo programa en el run loop actual. Lanza si CoreHID no
    /// puede abrir.
    public func open(runLoop: RunLoop = .current) throws {
        var matching: [String: Any] = [
            kIOHIDVendorIDKey as String: config.vendorID,
            kIOHIDProductIDKey as String: config.productID,
        ]
        if let up = config.usagePage { matching[kIOHIDDeviceUsagePageKey as String] = up }
        if let u = config.usage { matching[kIOHIDDeviceUsageKey as String] = u }
        IOHIDManagerSetDeviceMatching(manager, matching as CFDictionary)

        let context = Unmanaged.passUnretained(self).toOpaque()
        IOHIDManagerRegisterDeviceMatchingCallback(manager, HIDFaderConnector.deviceMatched, context)
        IOHIDManagerScheduleWithRunLoop(manager, runLoop.getCFRunLoop(),
                                        CFRunLoopMode.defaultMode.rawValue)

        let result = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        guard result == kIOReturnSuccess else { throw HIDError.open(result) }
    }

    public func close() {
        IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        IOHIDManagerUnscheduleFromRunLoop(manager, CFRunLoopGetCurrent(),
                                          CFRunLoopMode.defaultMode.rawValue)
    }

    // MARK: - callbacks C (no capturan; recuperan `self` del contexto)

    private static let deviceMatched: IOHIDDeviceCallback = { context, _, _, device in
        guard let context else { return }
        let me = Unmanaged<HIDFaderConnector>.fromOpaque(context).takeUnretainedValue()
        IOHIDDeviceRegisterInputReportCallback(
            device, me.reportBuffer.baseAddress!, me.reportBuffer.count,
            HIDFaderConnector.reportCallback, context)
    }

    private static let reportCallback: IOHIDReportCallback = {
        context, _, _, _, _, report, length in
        guard let context else { return }
        let me = Unmanaged<HIDFaderConnector>.fromOpaque(context).takeUnretainedValue()
        // El descriptor del perfil cuenta el offset sin el byte de report ID, que
        // IOHID entrega aparte; `report` ya son los datos.
        let bytes = Array(UnsafeBufferPointer(start: report, count: Int(length)))
        me.source.ingest(report: bytes, hostTime: HostClock.now())
    }

    public enum HIDError: Error, CustomStringConvertible {
        case open(IOReturn)
        public var description: String {
            switch self {
            case .open(let r): return "IOHIDManagerOpen fallo (IOReturn \(r))"
            }
        }
    }
}
