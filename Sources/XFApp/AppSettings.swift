// SPDX-License-Identifier: GPL-3.0-only

/// Los ajustes de la app (`docs/UI_DESIGN.md` §3.7). Todo local: sin cuenta, sin
/// nube, sin telemetría (`CLAUDE.md` §3).
///
/// Se guarda como clave/valor de texto en `XFPersistence` (tabla `setting`).
/// `AppSettings` es el envoltorio tipado: `init(raw:)` lee, `.raw` escribe, y
/// cualquier clave ausente o ilegible cae a su valor por defecto.
public struct AppSettings: Equatable, Sendable {

    /// Tamaños de buffer de audio que se ofrecen (frames @ 48 kHz). Rango amplio
    /// a propósito: sirve para aislar si el buffer es la causa de un crepiteo.
    public static let bufferOptions = [64, 128, 256, 512, 1024, 2048]

    /// Nombre de usuario, solo para etiquetar las estadísticas locales.
    public var username: String
    public var hamster: Bool
    public var metronomeEnabled: Bool
    public var bufferFrames: Int
    /// Multiplica las ventanas de tolerancia de clicks. `1.0` = estándar; subirlo
    /// afloja (para cabezotas), bajarlo aprieta.
    public var toleranceScale: Double
    public var highContrast: Bool
    public var reduceMotion: Bool
    /// Sin puerta de progresión: todos los niveles y variantes abiertos.
    /// Provisional mientras se prueba; por defecto `true`.
    public var allUnlocked: Bool
    /// Ruta del último sample de scratch que cargó el usuario (F.3). Vacío = el
    /// asset por defecto. Se recarga al abrir la práctica si el fichero sigue ahí.
    public var lastScratchSamplePath: String

    public static let defaults = AppSettings(
        username: "", hamster: false, metronomeEnabled: true, bufferFrames: 512,
        toleranceScale: 1.0, highContrast: false, reduceMotion: false, allUnlocked: true,
        lastScratchSamplePath: "")

    public init(username: String, hamster: Bool, metronomeEnabled: Bool, bufferFrames: Int,
                toleranceScale: Double, highContrast: Bool, reduceMotion: Bool,
                allUnlocked: Bool = true, lastScratchSamplePath: String = "") {
        self.username = String(username.prefix(40))
        self.hamster = hamster
        self.metronomeEnabled = metronomeEnabled
        self.bufferFrames = AppSettings.bufferOptions.contains(bufferFrames) ? bufferFrames : 512
        self.toleranceScale = toleranceScale
        self.highContrast = highContrast
        self.reduceMotion = reduceMotion
        self.allUnlocked = allUnlocked
        self.lastScratchSamplePath = lastScratchSamplePath
    }

    // MARK: - clave/valor

    private enum Key {
        static let username = "user.name"
        static let hamster = "hamster"
        static let metronome = "metronome.enabled"
        static let buffer = "audio.bufferFrames"
        static let tolerance = "scoring.toleranceScale"
        static let contrast = "a11y.highContrast"
        static let motion = "a11y.reduceMotion"
        static let allUnlocked = "progression.allUnlocked"
        static let lastSample = "practice.lastScratchSample"
    }

    public init(raw: [String: String]) {
        let d = AppSettings.defaults
        func bool(_ k: String, _ fallback: Bool) -> Bool { raw[k].map { $0 == "1" || $0 == "true" } ?? fallback }
        func int(_ k: String, _ fallback: Int) -> Int { raw[k].flatMap(Int.init) ?? fallback }
        func dbl(_ k: String, _ fallback: Double) -> Double { raw[k].flatMap(Double.init) ?? fallback }

        self.init(
            username: raw[Key.username] ?? d.username,
            hamster: bool(Key.hamster, d.hamster),
            metronomeEnabled: bool(Key.metronome, d.metronomeEnabled),
            bufferFrames: int(Key.buffer, d.bufferFrames),
            toleranceScale: max(0.5, min(2.0, dbl(Key.tolerance, d.toleranceScale))),
            highContrast: bool(Key.contrast, d.highContrast),
            reduceMotion: bool(Key.motion, d.reduceMotion),
            allUnlocked: bool(Key.allUnlocked, d.allUnlocked),
            lastScratchSamplePath: raw[Key.lastSample] ?? d.lastScratchSamplePath)
    }

    public var raw: [String: String] {
        [
            Key.username: username,
            Key.hamster: hamster ? "1" : "0",
            Key.metronome: metronomeEnabled ? "1" : "0",
            Key.buffer: String(bufferFrames),
            Key.tolerance: String(toleranceScale),
            Key.contrast: highContrast ? "1" : "0",
            Key.motion: reduceMotion ? "1" : "0",
            Key.allUnlocked: allUnlocked ? "1" : "0",
            Key.lastSample: lastScratchSamplePath,
        ]
    }
}
