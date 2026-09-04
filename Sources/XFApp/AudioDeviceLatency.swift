// SPDX-License-Identifier: GPL-3.0-only

import CoreAudio
import Foundation

/// F.48 (tacto): cuánto dice el propio dispositivo/driver que tarda, para
/// restarlo al puntuar y para mostrarlo en el reparto de latencia (F.50) sin
/// adivinar. Hasta ahora el tramo "driver/HAL" del presupuesto de
/// `CLAUDE.md` §4 era una estimación fija (~3 ms); esto lo mide de verdad,
/// por dispositivo.
///
/// CoreAudio expone dos propiedades **por lado** (entrada/salida) que juntas
/// dan el retardo fijo de ese tramo, aparte del búfer:
/// - `kAudioDevicePropertyLatency`: el propio hardware/driver declara que
///   tarda esto en mover una muestra entre el búfer y el conversor.
/// - `kAudioDevicePropertySafetyOffset`: margen extra que el HAL se reserva
///   antes de tocar el búfer, para no pisarse con el hilo de audio.
///
/// Sumando eso al tamaño de búfer actual (frames) sale el tiempo real de ese
/// lado. No corre en el hilo de audio — son consultas puntuales de
/// CoreAudio, igual que `AudioDeviceList`.
public enum AudioDeviceLatency {

    /// Latencia declarada de UN lado (entrada o salida) de un dispositivo.
    public struct Info: Equatable, Sendable {
        /// Frames que el propio dispositivo/driver declara para este lado.
        public let deviceFrames: Int
        /// Frames de margen de seguridad que reserva el HAL para este lado.
        public let safetyOffsetFrames: Int
        /// Tamaño de búfer actual del dispositivo (frames), el mismo para
        /// entrada y salida.
        public let bufferFrames: Int
        /// Frecuencia de muestreo nominal (Hz).
        public let sampleRate: Double

        public init(deviceFrames: Int, safetyOffsetFrames: Int, bufferFrames: Int, sampleRate: Double) {
            self.deviceFrames = deviceFrames
            self.safetyOffsetFrames = safetyOffsetFrames
            self.bufferFrames = bufferFrames
            self.sampleRate = sampleRate
        }

        /// Frames totales de este tramo: dispositivo + margen + búfer.
        public var totalFrames: Int { deviceFrames + safetyOffsetFrames + bufferFrames }

        /// Lo mismo en milisegundos. `0` si no hay frecuencia de muestreo
        /// válida (nunca debería pasar con un dispositivo real).
        public var totalMs: Double {
            guard sampleRate > 0 else { return 0 }
            return 1000.0 * Double(totalFrames) / sampleRate
        }
    }

    /// Latencia declarada por el dispositivo `id` en el lado `scope`
    /// (`kAudioObjectPropertyScopeInput` / `kAudioObjectPropertyScopeOutput`).
    /// `nil` si el dispositivo no tiene ese lado, o si CoreAudio no responde
    /// (algunos dispositivos virtuales/agregados no exponen estas claves).
    public static func info(for id: AudioDeviceID, scope: AudioObjectPropertyScope) -> Info? {
        guard let deviceFrames = uint32Property(id, kAudioDevicePropertyLatency, scope: scope),
              let safetyFrames = uint32Property(id, kAudioDevicePropertySafetyOffset, scope: scope)
        else { return nil }
        // Búfer y sample rate son del dispositivo entero, no por lado.
        let bufferFrames = uint32Property(id, kAudioDevicePropertyBufferFrameSize,
                                           scope: kAudioObjectPropertyScopeGlobal) ?? 0
        let sr = doubleProperty(id, kAudioDevicePropertyNominalSampleRate,
                                 scope: kAudioObjectPropertyScopeGlobal) ?? 0
        return Info(deviceFrames: Int(deviceFrames), safetyOffsetFrames: Int(safetyFrames),
                    bufferFrames: Int(bufferFrames), sampleRate: sr)
    }

    /// Latencia de SALIDA de `device`. Envuelve `info(for:scope:)` con el
    /// scope correcto para que quien dibuja la UI (`AppRootView`) no tenga
    /// que importar CoreAudio — mismo patrón que
    /// `AudioDeviceList.outputChannelPairs(for:)`.
    public static func outputInfo(for device: AudioDeviceList.Device) -> Info? {
        info(for: device.id, scope: kAudioObjectPropertyScopeOutput)
    }
    /// Igual que `outputInfo` pero de ENTRADA.
    public static func inputInfo(for device: AudioDeviceList.Device) -> Info? {
        info(for: device.id, scope: kAudioObjectPropertyScopeInput)
    }

    // MARK: - propiedades crudas

    private static func uint32Property(_ id: AudioDeviceID, _ selector: AudioObjectPropertySelector,
                                        scope: AudioObjectPropertyScope) -> UInt32? {
        var addr = AudioObjectPropertyAddress(mSelector: selector, mScope: scope,
                                               mElement: kAudioObjectPropertyElementMain)
        guard AudioObjectHasProperty(id, &addr) else { return nil }
        var size = UInt32(MemoryLayout<UInt32>.size)
        var value: UInt32 = 0
        let status = AudioObjectGetPropertyData(id, &addr, 0, nil, &size, &value)
        return status == noErr ? value : nil
    }

    private static func doubleProperty(_ id: AudioDeviceID, _ selector: AudioObjectPropertySelector,
                                        scope: AudioObjectPropertyScope) -> Double? {
        var addr = AudioObjectPropertyAddress(mSelector: selector, mScope: scope,
                                               mElement: kAudioObjectPropertyElementMain)
        guard AudioObjectHasProperty(id, &addr) else { return nil }
        var size = UInt32(MemoryLayout<Double>.size)
        var value: Double = 0
        let status = AudioObjectGetPropertyData(id, &addr, 0, nil, &size, &value)
        return status == noErr ? value : nil
    }
}
