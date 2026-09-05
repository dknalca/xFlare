// SPDX-License-Identifier: GPL-3.0-only
//
// XFCapture — CAPA 1. Fuentes de entrada: timecode, MIDI, teclado, replay.
// Binarizacion del fader con el cut-in calibrado. No hace analisis ni UI.
// Depende de XFPrimitives, XFClock, CXFTimecode, XFProfiles.
//
// SEALED (2026-09-05). Confirmado con hardware real (Rane 72): timecode
// (B5.5) y crossfader por MIDI (ADR-021 corregida, F.61). Los respaldos
// (audio_return, HID) siguen sin confirmar con hardware real -- ver README.md.

/// Espacio de nombres y version del contrato publico de XFCapture.
public enum XFCapture {
    public static let apiVersion = 1
}
