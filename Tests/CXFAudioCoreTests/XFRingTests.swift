// SPDX-License-Identifier: GPL-3.0-only
import XCTest
import Darwin   // sched_yield
import CXFAudioCore

/// B4.1 — ring buffer SPSC lock-free. Tests de comportamiento y una prueba de
/// estres productor/consumidor en dos hilos.
final class XFRingTests: XCTestCase {

    /// Reserva un `xf_ring_t` y su almacenamiento, ya inicializado.
    private func makeRing(capacity: Int) -> (ring: UnsafeMutablePointer<xf_ring_t>,
                                             storage: UnsafeMutablePointer<UInt8>) {
        let ring = UnsafeMutablePointer<xf_ring_t>.allocate(capacity: 1)
        let storage = UnsafeMutablePointer<UInt8>.allocate(capacity: capacity)
        storage.initialize(repeating: 0, count: capacity)
        XCTAssertTrue(xf_ring_init(ring, storage, capacity))
        return (ring, storage)
    }

    private func destroy(_ r: (ring: UnsafeMutablePointer<xf_ring_t>,
                               storage: UnsafeMutablePointer<UInt8>), capacity: Int) {
        r.storage.deinitialize(count: capacity)
        r.storage.deallocate()
        r.ring.deallocate()
    }

    func testInitRechazaCapacidadNoPotenciaDe2() {
        let ring = UnsafeMutablePointer<xf_ring_t>.allocate(capacity: 1)
        defer { ring.deallocate() }
        let storage = UnsafeMutablePointer<UInt8>.allocate(capacity: 100)
        defer { storage.deallocate() }
        XCTAssertFalse(xf_ring_init(ring, storage, 100))   // 100 no es potencia de 2
        XCTAssertFalse(xf_ring_init(ring, storage, 0))
        XCTAssertTrue(xf_ring_init(ring, storage, 64))
    }

    func testEscribeYLeeEnOrden() {
        let cap = 16
        let r = makeRing(capacity: cap)
        defer { destroy(r, capacity: cap) }

        XCTAssertEqual(xf_ring_read_available(r.ring), 0)
        XCTAssertEqual(xf_ring_write_available(r.ring), cap)

        var input: [UInt8] = [1, 2, 3, 4, 5]
        let written = input.withUnsafeBytes { xf_ring_write(r.ring, $0.baseAddress, $0.count) }
        XCTAssertEqual(written, 5)
        XCTAssertEqual(xf_ring_read_available(r.ring), 5)

        var out = [UInt8](repeating: 0, count: 5)
        let read = out.withUnsafeMutableBytes { xf_ring_read(r.ring, $0.baseAddress, $0.count) }
        XCTAssertEqual(read, 5)
        XCTAssertEqual(out, input)
        XCTAssertEqual(xf_ring_read_available(r.ring), 0)
        _ = input
    }

    func testNoPisaCuandoEstaLleno() {
        let cap = 8
        let r = makeRing(capacity: cap)
        defer { destroy(r, capacity: cap) }

        var full = [UInt8](0..<10)                    // 10 bytes en un ring de 8
        let w1 = full.withUnsafeBytes { xf_ring_write(r.ring, $0.baseAddress, $0.count) }
        XCTAssertEqual(w1, 8)                          // solo caben 8
        XCTAssertEqual(xf_ring_write_available(r.ring), 0)

        var one: [UInt8] = [99]
        let w2 = one.withUnsafeBytes { xf_ring_write(r.ring, $0.baseAddress, $0.count) }
        XCTAssertEqual(w2, 0)                          // no pisa
        _ = full; _ = one
    }

    func testDaLaVueltaAlFinalDelBuffer() {
        let cap = 8
        let r = makeRing(capacity: cap)
        defer { destroy(r, capacity: cap) }

        // llena, vacia 6 -> el proximo write empieza cerca del final y da la vuelta
        var a = [UInt8](0..<8)
        _ = a.withUnsafeBytes { xf_ring_write(r.ring, $0.baseAddress, $0.count) }
        XCTAssertEqual(xf_ring_skip(r.ring, 6), 6)

        var b: [UInt8] = [100, 101, 102, 103, 104, 105]   // 6 bytes, cabe (quedan 2 sin leer)
        let wb = b.withUnsafeBytes { xf_ring_write(r.ring, $0.baseAddress, $0.count) }
        XCTAssertEqual(wb, 6)

        var out = [UInt8](repeating: 0, count: 8)
        let rd = out.withUnsafeMutableBytes { xf_ring_read(r.ring, $0.baseAddress, $0.count) }
        XCTAssertEqual(rd, 8)
        XCTAssertEqual(out, [6, 7, 100, 101, 102, 103, 104, 105])
        _ = a; _ = b
    }

    func testReset() {
        let cap = 16
        let r = makeRing(capacity: cap)
        defer { destroy(r, capacity: cap) }
        var x: [UInt8] = [1, 2, 3]
        _ = x.withUnsafeBytes { xf_ring_write(r.ring, $0.baseAddress, $0.count) }
        xf_ring_reset(r.ring)
        XCTAssertEqual(xf_ring_read_available(r.ring), 0)
        XCTAssertEqual(xf_ring_write_available(r.ring), cap)
        _ = x
    }

    /// Estres: el PRODUCTOR corre en un hilo aparte y el CONSUMIDOR en este mismo
    /// (asi el unico estado compartido es el ring, que es justo lo que se prueba).
    /// Se mueve 1 MiB por un ring de 1 KiB y se verifica que la secuencia llega
    /// intacta y en orden (el byte i vale `i & 0xff`).
    func testProductorConsumidorConcurrente() {
        let cap = 1024
        let r = makeRing(capacity: cap)
        defer { destroy(r, capacity: cap) }

        let total = 1 << 20                     // 1 MiB
        let ring = r.ring                       // se captura el puntero, no `self`

        let producer = Thread {
            var sent = 0
            var chunk = [UInt8](repeating: 0, count: 333)   // tamano "feo" a proposito
            while sent < total {
                let n = min(chunk.count, total - sent)
                for k in 0..<n { chunk[k] = UInt8((sent + k) & 0xff) }
                var off = 0
                while off < n {
                    let w = chunk.withUnsafeBytes {
                        xf_ring_write(ring, $0.baseAddress!.advanced(by: off), n - off)
                    }
                    off += w
                    if w == 0 { sched_yield() }
                }
                sent += n
            }
        }
        producer.stackSize = 1 << 20
        producer.start()

        var got = 0
        var firstMismatch = -1
        var buf = [UInt8](repeating: 0, count: 512)
        let deadline = Date().addingTimeInterval(30)
        while got < total {
            if Date() > deadline { break }
            let n = buf.withUnsafeMutableBytes {
                xf_ring_read(ring, $0.baseAddress, min($0.count, total - got))
            }
            if n == 0 { sched_yield(); continue }
            for k in 0..<n where buf[k] != UInt8((got + k) & 0xff) {
                if firstMismatch < 0 { firstMismatch = got + k }
            }
            got += n
        }

        XCTAssertEqual(got, total, "el consumidor no recibio todo")
        XCTAssertEqual(firstMismatch, -1, "byte corrupto en la posicion \(firstMismatch)")
    }
}
