// SPDX-License-Identifier: GPL-3.0-only

import CoreGraphics

/// Un tramo del carril de fader: desde `xRange.lowerBound` hasta
/// `xRange.upperBound` (en puntos de vista), el crossfader está abierto o
/// cerrado. `docs/NOTATION.md` §2.3: negro = abierto, gris = cerrado.
public struct FaderBand: Equatable, Sendable {
    public var xRange: ClosedRange<CGFloat>
    public var isOpen: Bool

    public init(xRange: ClosedRange<CGFloat>, isOpen: Bool) {
        self.xRange = xRange
        self.isOpen = isOpen
    }
}
