// SPDX-License-Identifier: GPL-3.0-only

import CoreAudio
import Foundation

/// Enumera los dispositivos de audio del sistema, para rellenar los
/// desplegables de Entrada/Salida del asistente de calibración (paso 1) con
/// dispositivos **reales** — hasta ahora `AppRootView` no le pasaba ninguno y
/// los desplegables se veían vacíos, sin nada que asignar.
///
/// Es el mismo par de llamadas CoreAudio que ya prueba
/// `spike/b1-latency/passthrough.c --list` (que sí ve la Rane 72 dúplex, con
/// sus 14 canales de entrada y 10 de salida); esto es la versión Swift, para
/// el hilo principal — nada de esto corre en el hilo de audio (la regla de
/// CLAUDE.md §7 es solo para el callback RT de `CXFAudioCore`).
public enum AudioDeviceList {

    /// Un dispositivo de audio del sistema con lo que hace falta para
    /// mostrarlo y para pasarle su UID a `EngineHandle.start(deviceUID:)`.
    public struct Device: Identifiable, Equatable, Sendable {
        public let id: AudioDeviceID
        public let name: String
        public let uid: String
        public let inputChannels: Int
        public let outputChannels: Int
    }

    /// Todos los dispositivos con al menos un canal de entrada o de salida.
    public static func all() -> [Device] {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size) == noErr,
              size > 0 else { return [] }
        let count = Int(size) / MemoryLayout<AudioDeviceID>.size
        var ids = [AudioDeviceID](repeating: 0, count: count)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &ids) == noErr
        else { return [] }
        return ids.compactMap(deviceInfo)
    }

    /// Solo los que tienen ENTRADA (para el paso "Entrada (timecode)").
    public static func inputs() -> [Device] { all().filter { $0.inputChannels > 0 } }
    /// Solo los que tienen SALIDA.
    public static func outputs() -> [Device] { all().filter { $0.outputChannels > 0 } }

    // MARK: - por dispositivo

    private static func deviceInfo(_ id: AudioDeviceID) -> Device? {
        guard let name = propertyString(id, kAudioObjectPropertyName),
              let uid = propertyString(id, kAudioDevicePropertyDeviceUID) else { return nil }
        let inCh = channelCount(id, scope: kAudioObjectPropertyScopeInput)
        let outCh = channelCount(id, scope: kAudioObjectPropertyScopeOutput)
        guard inCh > 0 || outCh > 0 else { return nil }
        return Device(id: id, name: name, uid: uid, inputChannels: inCh, outputChannels: outCh)
    }

    private static func propertyString(_ id: AudioDeviceID, _ selector: AudioObjectPropertySelector) -> String? {
        var addr = AudioObjectPropertyAddress(
            mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var size = UInt32(MemoryLayout<CFString?>.size)
        var value: CFString?
        let status = withUnsafeMutablePointer(to: &value) {
            AudioObjectGetPropertyData(id, &addr, 0, nil, &size, $0)
        }
        guard status == noErr, let value else { return nil }
        return value as String
    }

    /// Nº de canales de un lado (entrada/salida): suma de `mNumberChannels` de
    /// cada `AudioBuffer` en `kAudioDevicePropertyStreamConfiguration` para
    /// ese scope. Mismo cálculo que `device_channels` en el spike C.
    private static func channelCount(_ id: AudioDeviceID, scope: AudioObjectPropertyScope) -> Int {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration, mScope: scope,
            mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(id, &addr, 0, nil, &size) == noErr, size > 0 else { return 0 }
        let raw = UnsafeMutableRawPointer.allocate(byteCount: Int(size),
                                                    alignment: MemoryLayout<AudioBufferList>.alignment)
        defer { raw.deallocate() }
        guard AudioObjectGetPropertyData(id, &addr, 0, nil, &size, raw) == noErr else { return 0 }
        let list = UnsafeMutableAudioBufferListPointer(raw.assumingMemoryBound(to: AudioBufferList.self))
        return list.reduce(0) { $0 + Int($1.mNumberChannels) }
    }
}
