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

    /// Opciones para la exportación de vídeo (F.4).
    public static let videoFpsOptions = [24, 30, 60]
    /// Lado mayor del vídeo en píxeles: estándar / alta.
    public static let videoLongSideOptions = [1280, 1600, 2400]

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
    /// Reasignaciones MIDI de comandos hechas por el usuario (pisan al perfil).
    /// Clave = nombre del comando (`cue`, `freeze`, …); valor = `"note:1:36"`.
    /// Se serializa como `cue=note:1:36;freeze=cc:0:64`.
    public var midiCommandOverrides: [String: String]
    /// Muestra el contador de fotogramas en la práctica (diagnóstico, B7.2b).
    public var showFPS: Bool
    /// Samples de scratch recordados (F.3): rutas, la más reciente primero. El
    /// asset por defecto no está aquí. Se serializa separando por `\n`.
    public var sampleLibrary: [String]
    /// FPS del vídeo exportado (F.4).
    public var videoFps: Int
    /// Lado mayor del vídeo exportado, en píxeles (F.4).
    public var videoLongSide: Int

    public static let defaults = AppSettings(
        username: "", hamster: false, metronomeEnabled: true, bufferFrames: 512,
        toleranceScale: 1.0, highContrast: false, reduceMotion: false, allUnlocked: true,
        lastScratchSamplePath: "", midiCommandOverrides: [:], showFPS: false,
        sampleLibrary: [], videoFps: 30, videoLongSide: 1600)

    public init(username: String, hamster: Bool, metronomeEnabled: Bool, bufferFrames: Int,
                toleranceScale: Double, highContrast: Bool, reduceMotion: Bool,
                allUnlocked: Bool = true, lastScratchSamplePath: String = "",
                midiCommandOverrides: [String: String] = [:], showFPS: Bool = false,
                sampleLibrary: [String] = [], videoFps: Int = 30, videoLongSide: Int = 1600) {
        self.username = String(username.prefix(40))
        self.hamster = hamster
        self.metronomeEnabled = metronomeEnabled
        self.bufferFrames = AppSettings.bufferOptions.contains(bufferFrames) ? bufferFrames : 512
        self.toleranceScale = toleranceScale
        self.highContrast = highContrast
        self.reduceMotion = reduceMotion
        self.allUnlocked = allUnlocked
        self.lastScratchSamplePath = lastScratchSamplePath
        self.midiCommandOverrides = midiCommandOverrides
        self.showFPS = showFPS
        // dedup preservando orden, tope 12
        var seen = Set<String>()
        self.sampleLibrary = sampleLibrary.filter { !$0.isEmpty && seen.insert($0).inserted }.prefix(12).map { $0 }
        self.videoFps = AppSettings.videoFpsOptions.contains(videoFps) ? videoFps : 30
        self.videoLongSide = AppSettings.videoLongSideOptions.contains(videoLongSide) ? videoLongSide : 1600
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
        static let midiCommands = "midi.commandOverrides"
        static let showFPS = "diag.showFPS"
        static let sampleLibrary = "practice.sampleLibrary"
        static let videoFps = "video.fps"
        static let videoLongSide = "video.longSide"
    }

    /// `cue=note:1:36;freeze=cc:0:64` -> diccionario.
    private static func parseMidi(_ s: String) -> [String: String] {
        var out: [String: String] = [:]
        for pair in s.split(separator: ";") {
            let kv = pair.split(separator: "=", maxSplits: 1)
            if kv.count == 2 { out[String(kv[0])] = String(kv[1]) }
        }
        return out
    }
    private static func serializeMidi(_ d: [String: String]) -> String {
        d.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: ";")
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
            lastScratchSamplePath: raw[Key.lastSample] ?? d.lastScratchSamplePath,
            midiCommandOverrides: AppSettings.parseMidi(raw[Key.midiCommands] ?? ""),
            showFPS: bool(Key.showFPS, d.showFPS),
            sampleLibrary: (raw[Key.sampleLibrary] ?? "").split(separator: "\n").map(String.init),
            videoFps: int(Key.videoFps, d.videoFps),
            videoLongSide: int(Key.videoLongSide, d.videoLongSide))
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
            Key.midiCommands: AppSettings.serializeMidi(midiCommandOverrides),
            Key.showFPS: showFPS ? "1" : "0",
            Key.sampleLibrary: sampleLibrary.joined(separator: "\n"),
            Key.videoFps: String(videoFps),
            Key.videoLongSide: String(videoLongSide),
        ]
    }
}
