// SPDX-License-Identifier: GPL-3.0-only

import XFClock

/// Una subdivision rítmica escrita como `"num/den"` (p. ej. `"1/8"`).
///
/// Es la unidad de duracion de una fase del patron: `1/4` = una negra = PPQ
/// ticks, `1/8` = media negra, etc. Portado de `div_to_ticks` en
/// `tools/xfn_core.py`.
public struct Division: Equatable, Sendable, CustomStringConvertible {
    public let numerator: Int
    public let denominator: Int

    public init?(_ text: String) {
        let parts = text.split(separator: "/", omittingEmptySubsequences: false)
        guard parts.count == 2,
              let n = Int(parts[0]), let d = Int(parts[1]), d != 0 else { return nil }
        self.numerator = n
        self.denominator = d
    }

    public init(numerator: Int, denominator: Int) {
        precondition(denominator != 0)
        self.numerator = numerator
        self.denominator = denominator
    }

    public var description: String { "\(numerator)/\(denominator)" }

    /// Ticks que dura una unidad de esta subdivision.
    /// `round(ppq * 4 * (num/den))`. Con PPQ 480: `1/4`→480, `1/8`→240, `1/16`→120.
    public func unitTicks(ppq: Int = XFClock.ppq) -> Int {
        let value = Double(ppq) * 4.0 * (Double(numerator) / Double(denominator))
        return Int(value.rounded())
    }
}
