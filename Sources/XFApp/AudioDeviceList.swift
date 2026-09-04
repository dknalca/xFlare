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

    /// El dispositivo de SALIDA elegido en Ajustes (`uid` no vacío y presente
    /// en `candidates`), o el de salida por defecto del sistema si `uid` está
    /// vacío o ya no existe (mismo criterio que usa el motor,
    /// `xf_engine_device_by_uid`, para que "lo que se calibra" sea "lo que
    /// realmente se usa").
    public static func resolvedOutput(uid: String, in candidates: [Device]) -> Device? {
        if !uid.isEmpty, let d = candidates.first(where: { $0.uid == uid }) { return d }
        return defaultDevice(selector: kAudioHardwarePropertyDefaultOutputDevice, in: candidates)
    }
    /// Igual que `resolvedOutput` pero de ENTRADA.
    public static func resolvedInput(uid: String, in candidates: [Device]) -> Device? {
        if !uid.isEmpty, let d = candidates.first(where: { $0.uid == uid }) { return d }
        return defaultDevice(selector: kAudioHardwarePropertyDefaultInputDevice, in: candidates)
    }

    private static func defaultDevice(selector: AudioObjectPropertySelector, in candidates: [Device]) -> Device? {
        var addr = AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal,
                                               mElement: kAudioObjectPropertyElementMain)
        var id = AudioDeviceID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &id) == noErr,
              id != kAudioObjectUnknown else { return nil }
        return candidates.first(where: { $0.id == id })
    }

    // MARK: - parejas estéreo (como el selector de entrada/salida de Ableton)

    /// Un PAR estéreo de canales dentro de un dispositivo: `first` es el
    /// primero (1-based; el segundo es `first + 1`). Es lo que se guarda en
    /// `AppSettings.outputChannel`/`inputChannel` y lo que arranca el motor
    /// (`EngineHandle.start`/`startOutput`, `xf_engine_start*`).
    public struct ChannelPair: Identifiable, Equatable, Sendable {
        public let first: Int
        /// "3-4 · Analog 2" si la mesa nombra los canales, si no solo "3-4".
        public let label: String
        public var id: Int { first }
    }

    /// Las parejas estéreo del lado `scope` del dispositivo `id` — canales
    /// (1,2), (3,4), (5,6)…, tantas como quepan en `totalChannels`. Sin
    /// esto, elegir un canal suelto no tiene sentido: el timecode y el
    /// audio del motor son siempre estéreo.
    public static func stereoPairs(for id: AudioDeviceID, scope: AudioObjectPropertyScope,
                                    totalChannels: Int) -> [ChannelPair] {
        guard totalChannels >= 2 else { return [] }
        var out: [ChannelPair] = []
        var first = 1
        while first + 1 <= totalChannels {
            let label = pairLabel(first: first,
                                   nameL: channelName(id, scope: scope, channel: first),
                                   nameR: channelName(id, scope: scope, channel: first + 1))
            out.append(ChannelPair(first: first, label: label))
            first += 2
        }
        return out
    }

    /// Parejas estéreo de SALIDA de `device`. Envuelve `stereoPairs` con el
    /// scope correcto para que quien dibuja la UI (`SettingsView`) no tenga
    /// que importar CoreAudio.
    public static func outputChannelPairs(for device: Device) -> [ChannelPair] {
        stereoPairs(for: device.id, scope: kAudioObjectPropertyScopeOutput, totalChannels: device.outputChannels)
    }
    /// Igual que `outputChannelPairs` pero de ENTRADA.
    public static func inputChannelPairs(for device: Device) -> [ChannelPair] {
        stereoPairs(for: device.id, scope: kAudioObjectPropertyScopeInput, totalChannels: device.inputChannels)
    }

    /// El nombre que el propio dispositivo da a un canal (1-based) de un
    /// lado, o `nil` si no lo declara. Muchas interfaces multicanal (la
    /// Rane 72: 14 in / 10 out) sí lo hacen — es lo único fiable para saber
    /// qué es cada canal sin adivinar (B5.5/B1.2, 2026-09-04: el timecode
    /// real estaba en "Analog 1", no en el canal que la mesa llama "Deck 1").
    public static func channelName(_ id: AudioDeviceID, scope: AudioObjectPropertyScope,
                                    channel: Int) -> String? {
        propertyString(id, kAudioObjectPropertyElementName, scope: scope,
                        element: AudioObjectPropertyElement(channel))
    }

    /// "Analog 1 Left" + "Analog 1 Right" -> "1-2 · Analog 1". Si los nombres
    /// no encajan ese patrón pero son iguales, se usan tal cual. Si no hay
    /// nombres o no coinciden, solo el rango de canales.
    /// `internal` (no `private`) a propósito: es la única parte de todo esto
    /// que es lógica pura, sin CoreAudio de por medio, y merece test directo
    /// (`@testable import`) sin depender de qué hardware tenga la máquina.
    static func pairLabel(first: Int, nameL: String?, nameR: String?) -> String {
        let range = "\(first)-\(first + 1)"
        guard let nameL, let nameR else { return range }
        if nameL.hasSuffix(" Left"), nameR.hasSuffix(" Right") {
            let baseL = String(nameL.dropLast(" Left".count))
            let baseR = String(nameR.dropLast(" Right".count))
            if !baseL.isEmpty, baseL == baseR { return "\(range) · \(baseL)" }
        }
        if !nameL.isEmpty, nameL == nameR { return "\(range) · \(nameL)" }
        return range
    }

    // MARK: - por dispositivo

    private static func deviceInfo(_ id: AudioDeviceID) -> Device? {
        guard let name = propertyString(id, kAudioObjectPropertyName),
              let uid = propertyString(id, kAudioDevicePropertyDeviceUID) else { return nil }
        let inCh = channelCount(id, scope: kAudioObjectPropertyScopeInput)
        let outCh = channelCount(id, scope: kAudioObjectPropertyScopeOutput)
        guard inCh > 0 || outCh > 0 else { return nil }
        return Device(id: id, name: name, uid: uid, inputChannels: inCh, outputChannels: outCh)
    }

    private static func propertyString(_ id: AudioDeviceID, _ selector: AudioObjectPropertySelector,
                                        scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal,
                                        element: AudioObjectPropertyElement = kAudioObjectPropertyElementMain
    ) -> String? {
        var addr = AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: element)
        guard AudioObjectHasProperty(id, &addr) else { return nil }
        var size = UInt32(MemoryLayout<CFString?>.size)
        var value: CFString?
        let status = withUnsafeMutablePointer(to: &value) {
            AudioObjectGetPropertyData(id, &addr, 0, nil, &size, $0)
        }
        guard status == noErr, let value else { return nil }
        let s = value as String
        return s.isEmpty ? nil : s
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
