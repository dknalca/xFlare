// SPDX-License-Identifier: GPL-3.0-only

/// El estado del permiso de micrófono y el texto honesto que lo acompaña
/// (`docs/UI_DESIGN.md` §3.12, `CLAUDE.md` addendum v0.4:
/// `NSMicrophoneUsageDescription` es obligatorio).
public enum MicPermission: Sendable, Equatable {
    case notDetermined
    case granted
    case denied
    case restricted

    /// Por qué la app pide el micrófono. Sin eufemismos.
    public static let rationale =
        "xFlare escucha el vinilo de timecode por la entrada de audio. macOS trata "
        + "esa entrada como \"micrófono\", así que hay que dar permiso. No se graba "
        + "nada que no sea tu propia práctica, y todo se queda en tu Mac."

    /// `true` si aún se puede pedir el permiso con el diálogo del sistema.
    public var canRequest: Bool { self == .notDetermined }

    /// `true` si la app puede oír el vinilo.
    public var canCapture: Bool { self == .granted }

    /// Pasos para arreglarlo cuando está denegado (la app no puede reabrir el
    /// diálogo del sistema).
    public var helpSteps: [String] {
        switch self {
        case .granted, .notDetermined:
            return []
        case .denied:
            return [
                "Abre Ajustes del Sistema › Privacidad y seguridad › Micrófono.",
                "Activa el interruptor de xFlare.",
                "Vuelve a xFlare (puede que tengas que reiniciarla).",
            ]
        case .restricted:
            return [
                "El micrófono está bloqueado por un perfil de configuración o control parental.",
                "Sin acceso a la entrada de audio, xFlare no puede leer el timecode.",
            ]
        }
    }
}
