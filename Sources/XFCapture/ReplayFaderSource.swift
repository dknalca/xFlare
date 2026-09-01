// SPDX-License-Identifier: GPL-3.0-only

import XFPrimitives

/// Reproduce las muestras de fader de una sesion grabada. Gemelo de
/// `ReplayMotionSource`.
public final class ReplayFaderSource: FaderSource {

    private let samples: [FaderSample]
    private var cursor = 0
    private var running = false

    public init(_ samples: [FaderSample]) {
        self.samples = samples
    }

    public convenience init(session: XFSession) {
        self.init(session.fader)
    }

    public var isConnected: Bool { running }

    public func start() throws {
        running = true
        cursor = 0
    }

    public func stop() {
        running = false
    }

    public func latest() -> FaderSample? {
        guard running, cursor > 0 else { return nil }
        return samples[cursor - 1]
    }

    public func seek(toHostTime hostTime: UInt64) {
        while cursor < samples.count && samples[cursor].hostTime <= hostTime {
            cursor += 1
        }
    }

    public var allSamples: [FaderSample] { samples }
    public var isFinished: Bool { cursor >= samples.count }
}
