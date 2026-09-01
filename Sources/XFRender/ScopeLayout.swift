// SPDX-License-Identifier: GPL-3.0-only

import CoreGraphics
import Foundation

/// Convierte lecturas del plato (`ScopeReading`) en la figura del scope circular
/// (`ScopeFigure`). **Puro**: sin SpriteKit, sin estado. El historial del rastro
/// lo aporta quien llama (un búfer de las últimas lecturas); así el scope es una
/// función de sus entradas y se testea sin pantalla.
///
/// El scope es un Lissajous reconstruido: en vez de las dos portadoras en
/// cuadratura crudas (que viven en la capa RT), usa la **fase acumulada**
/// (`position`) para el ángulo y la **confianza** para el radio. Señal limpia →
/// círculo regular; aguja sucia → el punto se hunde y `isDegraded`.
public struct ScopeLayout {

    /// Por debajo de esta confianza, la señal se considera degradada.
    public var degradedBelow: Double

    public init(degradedBelow: Double = 0.4) {
        self.degradedBelow = degradedBelow
    }

    /// - Parameter readings: las últimas lecturas, de la más vieja a la más
    ///   nueva. La última es "ahora". Vacío = sin señal.
    public func figure(readings: [ScopeReading], geometry g: ScopeGeometry) -> ScopeFigure {
        let center = g.center
        let R = g.referenceRadius

        func clampConfidence(_ c: Double) -> Double { min(1, max(0, c)) }
        func point(position: Double, confidence: Double) -> CGPoint {
            let angle = position * 2 * .pi
            let r = R * CGFloat(clampConfidence(confidence))
            return CGPoint(x: center.x + r * CGFloat(cos(angle)),
                           y: center.y + r * CGFloat(sin(angle)))
        }

        guard let now = readings.last else {
            return ScopeFigure(center: center, referenceRadius: R, dot: center,
                               dotRadiusFraction: 0, angleRadians: 0,
                               trail: [], isDegraded: true)
        }

        let conf = clampConfidence(now.confidence)
        let dot = point(position: now.position, confidence: now.confidence)
        let trail = readings.map { point(position: $0.position, confidence: $0.confidence) }

        // ángulo normalizado a [0, 2π)
        let raw = (now.position * 2 * .pi).truncatingRemainder(dividingBy: 2 * .pi)
        let angle = CGFloat(raw < 0 ? raw + 2 * .pi : raw)

        return ScopeFigure(center: center, referenceRadius: R, dot: dot,
                           dotRadiusFraction: CGFloat(conf), angleRadians: angle,
                           trail: trail, isDegraded: now.confidence < degradedBelow)
    }
}
