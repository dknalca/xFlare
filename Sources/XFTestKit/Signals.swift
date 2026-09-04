// SPDX-License-Identifier: GPL-3.0-only

import Foundation

/// Generadores de señales sintéticas para tests de audio / timecode. Puros y
/// deterministas: mismas entradas → mismas muestras en las dos arquitecturas.
public enum Signals {

    // MARK: - PCM mono float

    /// Seno de `freq` Hz, `seconds` s, a `sampleRate`, amplitud pico `amplitude`.
    public static func sine(freq: Double, seconds: Double,
                            sampleRate: Double = 48_000, amplitude: Double = 0.5) -> [Float] {
        let n = max(0, Int(seconds * sampleRate))
        let w = 2.0 * Double.pi * freq / sampleRate
        return (0..<n).map { Float(amplitude * sin(w * Double($0))) }
    }

    /// `seconds` de silencio (ceros) a `sampleRate`.
    public static func silence(seconds: Double, sampleRate: Double = 48_000) -> [Float] {
        [Float](repeating: 0, count: max(0, Int(seconds * sampleRate)))
    }

    // MARK: - timecode de cuadratura (estéreo int16 intercalado)

    /// Vinilo de timecode sintético: dos senoidales a `carrierHz` (canal
    /// primario y secundario) desfasadas `secondaryPhaseDeg` grados. Es lo que
    /// espera `xf_timecoder` / `TimecodeMotionSource` para decodificar velocidad
    /// y sentido sin un vinilo real:
    ///  - `carrierHz` fija la **velocidad**: con un perfil de `resolution = 1000`,
    ///    1000 Hz ≈ 1,0× y 1500 Hz ≈ 1,5×.
    ///  - `secondaryPhaseDeg` fija el **sentido**: `+90` adelante, `-90` atrás
    ///    (hamster / reverse).
    ///
    /// Estéreo 16 bits intercalado `[L, R, L, R, …]`, `frames * 2` muestras.
    public static func quadratureTimecode(carrierHz: Double = 1_000,
                                          secondaryPhaseDeg: Double = 90,
                                          seconds: Double,
                                          sampleRate: Double = 48_000,
                                          amplitude: Double = 10_000) -> [Int16] {
        let frames = max(0, Int(seconds * sampleRate))
        var out = [Int16](repeating: 0, count: frames * 2)
        let w = 2.0 * Double.pi * carrierHz / sampleRate
        let ph2 = secondaryPhaseDeg * Double.pi / 180.0
        for i in 0..<frames {
            out[i * 2]     = clampI16(amplitude * sin(w * Double(i)))
            out[i * 2 + 1] = clampI16(amplitude * sin(w * Double(i) + ph2))
        }
        return out
    }

    private static func clampI16(_ x: Double) -> Int16 {
        let r = x.rounded()
        if r >= Double(Int16.max) { return Int16.max }
        if r <= Double(Int16.min) { return Int16.min }
        return Int16(r)
    }
}
