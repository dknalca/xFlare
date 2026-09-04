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
    /// Buffer de arranque: 128 frames (2,7 ms). El compromiso seguro del Intel
    /// de 2015 (ADR-024); recorta ~16 ms frente a 512 (F.04).
    public static let defaultBufferFrames = 128

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
    /// Instrumentales / loops que el usuario ha guardado en su librería: rutas,
    /// la más reciente primero. Se serializa separando por `\n`.
    public var instrumentalLibrary: [String]
    /// 4 slots de sample asignables a botones MIDI (`Sample 1`…`Sample 4`) para
    /// cambiar de sample en caliente durante una sesión. `""` = slot vacío.
    /// Siempre 4 entradas. Se serializa separando por `\n`.
    public var sampleSlots: [String]
    /// FPS del vídeo exportado (F.4).
    public var videoFps: Int
    /// Lado mayor del vídeo exportado, en píxeles (F.4).
    public var videoLongSide: Int

    /// UID del dispositivo de SALIDA elegido (`AudioDeviceList.Device.uid`).
    /// `""` = el de salida por defecto del sistema.
    public var outputDeviceUID: String
    /// Primer canal (1-based) del PAR estéreo de salida a usar dentro de ese
    /// dispositivo — p. ej. `3` = canales 3 y 4. `1` = por defecto (los dos
    /// primeros). En una interfaz multicanal (Rane 72: 10 salidas) el 1 casi
    /// nunca es el que hace falta.
    public var outputChannel: Int
    /// Igual que `outputDeviceUID` pero para la ENTRADA (captura de timecode
    /// cuando exista B4.2). `""` = el de entrada por defecto.
    public var inputDeviceUID: String
    /// Igual que `outputChannel` pero para la entrada.
    public var inputChannel: Int

    // MARK: - Debug: "tacto" del plato (ventana Ajustes › Debug)
    /// Suavizado (ms) de la velocidad del plato de scratch. Menos = más seco y el
    /// audio sigue mejor al gesto; más = más suave pero con retardo. Def. 3.
    public var platterGlideMs: Double
    /// |v| por debajo de la cual el scratch se atenúa con un taper de coseno
    /// (F.47; antes rampa lineal) hasta enmudecer — el bloqueador de DC aguas
    /// abajo mata el zumbido del cabezal quieto. Def. 0,04 (antes 0,12: el
    /// bloqueador de DC deja bajar el umbral sin que vuelva el zumbido).
    /// `0` = sin puerta.
    public var platterSpeedGate: Double
    /// Fricción del plato: cómo de rápido frena al soltar (1/s del decaimiento
    /// exponencial). Más = frena antes. Def. 1,8.
    public var platterFriction: Double
    /// Multiplicador de la sensibilidad del trackpad al girar el plato. Def. 1,0.
    public var trackpadSensitivity: Double

    // F.04 — arranca en `defaultBufferFrames` (128), no en 512: recorta ~16 ms
    // de latencia de ida+vuelta. Si aparecen overloads, subir a mano en Ajustes
    // › Audio (la subida automática al detectar overloads es B1.6, pendiente).
    public static let defaults = AppSettings(
        username: "", hamster: false, metronomeEnabled: true, bufferFrames: defaultBufferFrames,
        toleranceScale: 1.0, highContrast: false, reduceMotion: false, allUnlocked: true,
        lastScratchSamplePath: "", midiCommandOverrides: [:], showFPS: false,
        sampleLibrary: [], videoFps: 30, videoLongSide: 1600)

    public init(username: String, hamster: Bool, metronomeEnabled: Bool, bufferFrames: Int,
                toleranceScale: Double, highContrast: Bool, reduceMotion: Bool,
                allUnlocked: Bool = true, lastScratchSamplePath: String = "",
                midiCommandOverrides: [String: String] = [:], showFPS: Bool = false,
                sampleLibrary: [String] = [], videoFps: Int = 30, videoLongSide: Int = 1600,
                platterGlideMs: Double = 3.0, platterSpeedGate: Double = 0.04,
                platterFriction: Double = 1.8, trackpadSensitivity: Double = 1.0,
                instrumentalLibrary: [String] = [], sampleSlots: [String] = [],
                outputDeviceUID: String = "", outputChannel: Int = 1,
                inputDeviceUID: String = "", inputChannel: Int = 1) {
        self.username = String(username.prefix(40))
        self.hamster = hamster
        self.metronomeEnabled = metronomeEnabled
        self.bufferFrames = AppSettings.bufferOptions.contains(bufferFrames)
            ? bufferFrames : AppSettings.defaultBufferFrames
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
        var seenI = Set<String>()
        self.instrumentalLibrary = instrumentalLibrary.filter { !$0.isEmpty && seenI.insert($0).inserted }.prefix(200).map { $0 }
        // siempre 4 slots: se rellena con "" o se recorta.
        self.sampleSlots = (0..<4).map { sampleSlots.indices.contains($0) ? sampleSlots[$0] : "" }
        self.videoFps = AppSettings.videoFpsOptions.contains(videoFps) ? videoFps : 30
        self.videoLongSide = AppSettings.videoLongSideOptions.contains(videoLongSide) ? videoLongSide : 1600
        // Debug: rangos amplios pero acotados para no romper el motor.
        self.platterGlideMs      = min(12.0, max(0.5, platterGlideMs))
        self.platterSpeedGate    = min(0.4,  max(0.0, platterSpeedGate))
        self.platterFriction     = min(6.0,  max(0.3, platterFriction))
        self.trackpadSensitivity = min(2.0,  max(0.2, trackpadSensitivity))
        self.outputDeviceUID = outputDeviceUID
        self.outputChannel = max(1, outputChannel)
        self.inputDeviceUID = inputDeviceUID
        self.inputChannel = max(1, inputChannel)
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
        static let instrumentalLibrary = "media.instrumentalLibrary"
        static let sampleSlots = "media.sampleSlots"
        static let videoFps = "video.fps"
        static let videoLongSide = "video.longSide"
        static let platterGlideMs = "debug.platterGlideMs"
        static let platterSpeedGate = "debug.platterSpeedGate"
        static let platterFriction = "debug.platterFriction"
        static let trackpadSensitivity = "debug.trackpadSensitivity"
        static let outputDeviceUID = "audio.outputDeviceUID"
        static let outputChannel = "audio.outputChannel"
        static let inputDeviceUID = "audio.inputDeviceUID"
        static let inputChannel = "audio.inputChannel"
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
            videoLongSide: int(Key.videoLongSide, d.videoLongSide),
            platterGlideMs: dbl(Key.platterGlideMs, d.platterGlideMs),
            platterSpeedGate: dbl(Key.platterSpeedGate, d.platterSpeedGate),
            platterFriction: dbl(Key.platterFriction, d.platterFriction),
            trackpadSensitivity: dbl(Key.trackpadSensitivity, d.trackpadSensitivity),
            instrumentalLibrary: (raw[Key.instrumentalLibrary] ?? "").split(separator: "\n").map(String.init),
            sampleSlots: (raw[Key.sampleSlots] ?? "").components(separatedBy: "\n"),
            outputDeviceUID: raw[Key.outputDeviceUID] ?? d.outputDeviceUID,
            outputChannel: int(Key.outputChannel, d.outputChannel),
            inputDeviceUID: raw[Key.inputDeviceUID] ?? d.inputDeviceUID,
            inputChannel: int(Key.inputChannel, d.inputChannel))
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
            Key.instrumentalLibrary: instrumentalLibrary.joined(separator: "\n"),
            Key.sampleSlots: sampleSlots.joined(separator: "\n"),
            Key.videoFps: String(videoFps),
            Key.videoLongSide: String(videoLongSide),
            Key.platterGlideMs: String(platterGlideMs),
            Key.platterSpeedGate: String(platterSpeedGate),
            Key.platterFriction: String(platterFriction),
            Key.trackpadSensitivity: String(trackpadSensitivity),
            Key.outputDeviceUID: outputDeviceUID,
            Key.outputChannel: String(outputChannel),
            Key.inputDeviceUID: inputDeviceUID,
            Key.inputChannel: String(inputChannel),
        ]
    }
}
