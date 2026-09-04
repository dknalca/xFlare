// SPDX-License-Identifier: GPL-3.0-only

import Foundation
import XFPrimitives
import XFCapture

/// `FaderSource` de mentira para tests. Gemela de `FakeMotionSource`: modo
/// script (una muestra por `latest()`, repite la última al acabar) o modo fijo
/// (`fixed`, reasignable), más el conteo de `start()` / `stop()` y un
/// `startError` opcional.
public final class FakeFaderSource: FaderSource {

    public var script: [FaderSample]
    public var fixed: FaderSample?
    public var startError: Error?

    public private(set) var startCount = 0
    public private(set) var stopCount = 0
    private var cursor = 0

    public init(script: [FaderSample] = [], fixed: FaderSample? = nil) {
        self.script = script
        self.fixed = fixed
    }

    public var isConnected: Bool { startCount > stopCount }

    public func start() throws {
        if let e = startError { throw e }
        startCount += 1
    }

    public func stop() {
        stopCount += 1
        cursor = 0
    }

    public func latest() -> FaderSample? {
        guard isConnected else { return nil }
        guard !script.isEmpty else { return fixed }
        let s = script[min(cursor, script.count - 1)]
        cursor += 1
        return s
    }
}
