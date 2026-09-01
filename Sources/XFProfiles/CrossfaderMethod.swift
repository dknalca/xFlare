// SPDX-License-Identifier: GPL-3.0-only

/// Como se captura la posicion del crossfader. Los valores son los del `.conf`
/// (`crossfader.method`) y determinan que otras claves son obligatorias.
public enum CrossfaderMethod: String, Equatable, Sendable {
    /// La mesa emite la posicion por MIDI CC.
    case midi
    /// Tono piloto sobre el retorno del master por USB (ADR-021). El metodo por
    /// defecto para mesas de battle (Rane 72, DJM-S11).
    case audioReturn = "audio_return"
    /// La mesa habla HID (p. ej. DJM-S11 con Serato). No implementado aun.
    case hid
    /// Sin captura de fader (modo teclado / sin mesa).
    case none
}
