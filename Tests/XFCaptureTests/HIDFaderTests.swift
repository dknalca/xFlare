// SPDX-License-Identifier: GPL-3.0-only
import XCTest
@testable import XFCapture
import XFProfiles

/// Ruta HID del crossfader (respaldo de ADR-021): decodificación de reports y la
/// fuente `HIDFaderSource`.
final class HIDFaderTests: XCTestCase {

    // MARK: - HIDCrossfaderConfig desde perfil

    private func hidProfile() throws -> DeviceProfile {
        let ini = try INIDocument(text: """
        [profile]
        id = mesa-hid
        name = Mesa HID
        vendor = -
        schema = 1
        revision = 1
        verified = true
        [crossfader]
        method = hid
        hid.vendor_id  = 0x13e5
        hid.product_id = 0x0006
        hid.usage_page = 0x01
        hid.usage      = 0x04
        hid.report_id  = 3
        hid.byte_offset = 2
        hid.byte_length = 2
        hid.big_endian  = false
        hid.min = 0
        hid.max = 1023
        hid.invert = true
        cut_in.left = 0.05
        cut_in.right = 0.95
        """)
        return try DeviceProfile.parse(resolved: ini)
    }

    func testParseaConfigDesdeElPerfil() throws {
        let cfg = try HIDCrossfaderConfig(from: hidProfile())
        XCTAssertEqual(cfg.vendorID, 0x13e5)
        XCTAssertEqual(cfg.productID, 0x0006)
        XCTAssertEqual(cfg.usagePage, 0x01)
        XCTAssertEqual(cfg.reportID, 3)
        XCTAssertEqual(cfg.byteOffset, 2)
        XCTAssertEqual(cfg.byteLength, 2)
        XCTAssertFalse(cfg.bigEndian)
        XCTAssertEqual(cfg.rawMax, 1023)
        XCTAssertTrue(cfg.invert)
    }

    func testFallaSiElMetodoNoEsHID() throws {
        let ini = try INIDocument(text: """
        [profile]
        id = x
        name = X
        vendor = -
        schema = 1
        revision = 1
        verified = true
        [crossfader]
        method = midi
        midi.channel = 1
        midi.cc = 0
        midi.min = 0
        midi.max = 127
        """)
        let p = try DeviceProfile.parse(resolved: ini)
        XCTAssertThrowsError(try HIDCrossfaderConfig(from: p)) { e in
            XCTAssertEqual(e as? HIDCrossfaderConfig.ConfigError, .notHIDMethod)
        }
    }

    func testFallaSiFaltaClaveObligatoria() throws {
        let ini = try INIDocument(text: """
        [profile]
        id = x
        name = X
        vendor = -
        schema = 1
        revision = 1
        verified = true
        [crossfader]
        method = hid
        hid.vendor_id = 0x1
        """)
        let p = try DeviceProfile.parse(resolved: ini)
        XCTAssertThrowsError(try HIDCrossfaderConfig(from: p)) { e in
            guard case HIDCrossfaderConfig.ConfigError.missing(let k) = e else { return XCTFail() }
            XCTAssertTrue(k.contains("product_id") || k.contains("byte_offset"))
        }
    }

    // MARK: - value(fromReport:)

    func test1Byte() {
        let cfg = HIDCrossfaderConfig(vendorID: 1, productID: 1, byteOffset: 1,
                                     byteLength: 1, rawMin: 0, rawMax: 255)
        XCTAssertEqual(cfg.value(fromReport: [0xFF, 0x00, 0xFF]) ?? -1, Float(0), accuracy: 1e-6)
        XCTAssertEqual(cfg.value(fromReport: [0xFF, 128, 0xFF]) ?? -1, Float(128) / 255, accuracy: 1e-6)
        XCTAssertEqual(cfg.value(fromReport: [0xFF, 255]) ?? -1, Float(1), accuracy: 1e-6)
    }

    func test2ByteLittleEndian() {
        let cfg = HIDCrossfaderConfig(vendorID: 1, productID: 1, byteOffset: 0,
                                     byteLength: 2, bigEndian: false, rawMin: 0, rawMax: 1023)
        // 0x03FF = 1023 (LE: FF 03)
        XCTAssertEqual(cfg.value(fromReport: [0xFF, 0x03]) ?? -1, 1.0, accuracy: 1e-6)
        // 512 -> 0x0200 (LE: 00 02)
        XCTAssertEqual(cfg.value(fromReport: [0x00, 0x02]) ?? -1, 512.0 / 1023.0, accuracy: 1e-6)
    }

    func test2ByteBigEndian() {
        let cfg = HIDCrossfaderConfig(vendorID: 1, productID: 1, byteOffset: 0,
                                     byteLength: 2, bigEndian: true, rawMin: 0, rawMax: 1023)
        XCTAssertEqual(cfg.value(fromReport: [0x03, 0xFF]) ?? -1, 1.0, accuracy: 1e-6)
    }

    func testInvertYClamp() {
        let cfg = HIDCrossfaderConfig(vendorID: 1, productID: 1, byteOffset: 0,
                                     byteLength: 1, rawMin: 0, rawMax: 100, invert: true)
        XCTAssertEqual(cfg.value(fromReport: [0]) ?? -1, 1.0, accuracy: 1e-6)     // invertido
        XCTAssertEqual(cfg.value(fromReport: [100]) ?? -1, 0.0, accuracy: 1e-6)
        XCTAssertEqual(cfg.value(fromReport: [200]) ?? -1, 0.0, accuracy: 1e-6)   // clamp: raw>max -> v=1 -> invert -> 0
    }

    func testReportCorto() {
        let cfg = HIDCrossfaderConfig(vendorID: 1, productID: 1, byteOffset: 4, byteLength: 2)
        XCTAssertNil(cfg.value(fromReport: [0, 1, 2, 3]))   // no llega a offset+len
    }

    // MARK: - HIDFaderSource

    func testFuenteBinarizaYRespetaRunning() throws {
        let cfg = HIDCrossfaderConfig(vendorID: 1, productID: 1, byteOffset: 0,
                                     byteLength: 1, rawMin: 0, rawMax: 255)
        let bin = FaderBinarizer(cutIn: 0.5, hysteresis: 0.1)
        let src = HIDFaderSource(config: cfg, binarizer: bin)

        src.ingest(report: [255], hostTime: 10)   // aún no start()
        XCTAssertNil(src.latest())

        try src.start()
        src.ingest(report: [255], hostTime: 20)   // value 1.0 -> abre
        XCTAssertEqual(src.latest()?.isOpen, true)
        XCTAssertEqual(src.latest()?.hostTime, 20)
        src.ingest(report: [0], hostTime: 30)     // value 0.0 -> cierra
        XCTAssertEqual(src.latest()?.isOpen, false)

        src.stop()
        src.ingest(report: [255], hostTime: 40)   // ignorado
        XCTAssertEqual(src.latest()?.hostTime, 30)
    }
}
