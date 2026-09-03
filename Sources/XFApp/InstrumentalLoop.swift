// SPDX-License-Identifier: GPL-3.0-only

import Foundation

/// Cálculo **puro** del "modo loop" de una instrumental subida por el usuario.
///
/// Un fichero que sube el usuario se trata siempre como un bucle de `bars`
/// compases que suena a **velocidad natural** (nunca se estira el audio). Lo que
/// se calcula aquí es cómo cuadricularlo: el BPM de la rejilla se **deriva** del
/// nº de compases y de la duración real del fichero, de modo que el metrónomo y
/// las líneas de compás queden clavados al bucle aunque la detección de tempo
/// haya fallado. `loadInstrumental` usa `guess(...)` al cargar; los botones −/+
/// del panel usan `locked(...)`.
struct InstrumentalLoop: Equatable {
    /// Compases que se considera que dura el fichero.
    var bars: Int
    /// BPM derivado para la rejilla (puede ser fraccionario).
    var bpm: Double
    /// Longitud del bucle en ticks del patrón.
    var loopTicks: Double

    private static let barsCeiling = 32
    private static let bpmLow = 70.0
    private static let bpmHigh = 180.0

    /// Fija `bars` explícitamente y recalcula BPM y ticks.
    static func locked(bars: Int, fileSeconds: Double,
                       beatsPerBar: Int, ppq: Int) -> InstrumentalLoop {
        let b = min(barsCeiling, max(1, bars))
        let secs = max(0.01, fileSeconds)
        let beats = b * max(1, beatsPerBar)
        return InstrumentalLoop(bars: b,
                                bpm: Double(beats) * 60.0 / secs,
                                loopTicks: Double(beats) * Double(max(1, ppq)))
    }

    /// Adivina los compases: desde las negras del análisis de tempo si las hay,
    /// o suponiendo ~2 s por compás (120 BPM en 4/4). Después parte o dobla la
    /// cuenta hasta que el BPM caiga en 70…180, lo que corrige los medios y
    /// dobles tiempos típicos de la detección. Más compases en el mismo fichero
    /// = más BPM.
    static func guess(fileSeconds: Double, beatsPerBar: Int, ppq: Int,
                      analyzedBeats: Int?) -> InstrumentalLoop {
        let bpb = max(1, beatsPerBar)
        let secs = max(0.01, fileSeconds)
        var bars: Int
        if let beats = analyzedBeats, beats > 0 {
            bars = Int((Double(beats) / Double(bpb)).rounded())
        } else {
            bars = Int((secs / (Double(bpb) * 0.5)).rounded())
        }
        bars = min(barsCeiling, max(1, bars))

        func bpmFor(_ b: Int) -> Double { Double(b * bpb) * 60.0 / secs }
        while bpmFor(bars) > bpmHigh, bars > 1            { bars /= 2 }
        while bpmFor(bars) < bpmLow,  bars * 2 <= 2 * barsCeiling { bars *= 2 }

        return locked(bars: bars, fileSeconds: secs, beatsPerBar: bpb, ppq: ppq)
    }
}
