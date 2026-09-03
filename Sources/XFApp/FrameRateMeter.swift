// SPDX-License-Identifier: GPL-3.0-only

import Foundation

/// Mide fps a partir de los instantes de fotograma que le pasa la escena
/// (`update(_:)` de SpriteKit). **Puro**: no toca SpriteKit ni relojes, así se
/// prueba sin ventana. Diagnóstico de B7.2b (60 fps estables en el Intel de 2015).
struct FrameRateMeter {

    /// Nº de fotogramas que se promedian (a 60 fps ≈ 2 s).
    let window: Int
    private var deltas: [Double] = []
    private var last: Double = 0

    init(window: Int = 120) { self.window = max(2, window) }

    /// Registra el instante de un fotograma (segundos, monótono).
    mutating func tick(_ now: Double) {
        defer { last = now }
        guard last > 0, now > last else { return }
        let dt = now - last
        // un salto > 1 s no es un "drop": es la ventana en segundo plano, un
        // breakpoint o un cambio de escena. Se descarta la ventana y a empezar.
        guard dt < 1.0 else { deltas.removeAll(keepingCapacity: true); return }
        deltas.append(dt)
        if deltas.count > window { deltas.removeFirst(deltas.count - window) }
    }

    /// Hay muestras suficientes para que la media signifique algo.
    var hasData: Bool { deltas.count >= 10 }

    /// fps medio de la ventana.
    var averageFPS: Double {
        guard !deltas.isEmpty else { return 0 }
        let mean = deltas.reduce(0, +) / Double(deltas.count)
        return mean > 0 ? 1.0 / mean : 0
    }

    /// El peor fotograma de la ventana, en milisegundos.
    var worstMs: Double { (deltas.max() ?? 0) * 1000 }

    /// Cuántos fotogramas de la ventana pasaron de `budgetMs`.
    func droppedFrames(budgetMs: Double) -> Int {
        let b = budgetMs / 1000
        return deltas.reduce(0) { $0 + ($1 > b ? 1 : 0) }
    }

    /// Fotogramas "perdidos de verdad": los que tardaron más de **1,5 periodos**
    /// del objetivo (a 60 fps → > 25 ms; se saltaron un vsync). Un fotograma a
    /// 16,8 ms no cuenta: está en el borde, es jitter normal.
    func missedVsyncs(targetFPS: Double = 60) -> Int {
        droppedFrames(budgetMs: 1.5 * 1000.0 / max(1, targetFPS))
    }

    /// Resumen de una línea para el overlay.
    func summary(targetFPS: Double = 60) -> String {
        guard hasData else { return "fps —" }
        return String(format: "%.0f fps · peor %.1f ms · saltos %d/%d",
                      averageFPS, worstMs, missedVsyncs(targetFPS: targetFPS), deltas.count)
    }
}
