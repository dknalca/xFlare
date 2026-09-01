// SPDX-License-Identifier: GPL-3.0-only

/// Los ajustes de la app (`docs/UI_DESIGN.md` §3.7). Todo local: sin cuenta, sin
/// nube, sin telemetría (`CLAUDE.md` §3).
///
/// Se guarda como clave/valor de texto en `XFPersistence` (tabla `setting`).
/// `AppSettings` es el envoltorio tipado: `init(raw:)` lee, `.raw` escribe, y
/// cualquier clave ausente o ilegible cae a su valor por defecto.
public struct AppSettings: Equatable, Sendable {

    public var hamster: Bool
    public var metronomeEnabled: Bool
    public var bufferFrames: Int
    /// Multiplica las ventanas de tolerancia de clicks. `1.0` = estándar; subirlo
    /// afloja (para cabezotas), bajarlo aprieta.
    public var toleranceScale: Double
    public var highContrast: Bool
    public var reduceMotion: Bool

    public static let defaults = AppSettings(
        hamster: false, metronomeEnabled: true, bufferFrames: 64,
        toleranceScale: 1.0, highContrast: false, reduceMotion: false)

    public init(hamster: Bool, metronomeEnabled: Bool, bufferFrames: Int,
                toleranceScale: Double, highContrast: Bool, reduceMotion: Bool) {
        self.hamster = hamster
        self.metronomeEnabled = metronomeEnabled
        self.bufferFrames = bufferFrames
        self.toleranceScale = toleranceScale
        self.highContrast = highContrast
        self.reduceMotion = reduceMotion
    }

    // MARK: - clave/valor

    private enum Key {
        static let hamster = "hamster"
        static let metronome = "metronome.enabled"
        static let buffer = "audio.bufferFrames"
        static let tolerance = "scoring.toleranceScale"
        static let contrast = "a11y.highContrast"
        static let motion = "a11y.reduceMotion"
    }

    public init(raw: [String: String]) {
        let d = AppSettings.defaults
        func bool(_ k: String, _ fallback: Bool) -> Bool { raw[k].map { $0 == "1" || $0 == "true" } ?? fallback }
        func int(_ k: String, _ fallback: Int) -> Int { raw[k].flatMap(Int.init) ?? fallback }
        func dbl(_ k: String, _ fallback: Double) -> Double { raw[k].flatMap(Double.init) ?? fallback }

        self.init(
            hamster: bool(Key.hamster, d.hamster),
            metronomeEnabled: bool(Key.metronome, d.metronomeEnabled),
            bufferFrames: [64, 128].contains(int(Key.buffer, d.bufferFrames)) ? int(Key.buffer, d.bufferFrames) : d.bufferFrames,
            toleranceScale: max(0.5, min(2.0, dbl(Key.tolerance, d.toleranceScale))),
            highContrast: bool(Key.contrast, d.highContrast),
            reduceMotion: bool(Key.motion, d.reduceMotion))
    }

    public var raw: [String: String] {
        [
            Key.hamster: hamster ? "1" : "0",
            Key.metronome: metronomeEnabled ? "1" : "0",
            Key.buffer: String(bufferFrames),
            Key.tolerance: String(toleranceScale),
            Key.contrast: highContrast ? "1" : "0",
            Key.motion: reduceMotion ? "1" : "0",
        ]
    }
}
