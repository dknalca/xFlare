// SPDX-License-Identifier: GPL-3.0-only
//
// XFCapture — CAPA 1. Fuentes de entrada: timecode, MIDI, teclado, replay.
// Binarizacion del fader con el cut-in calibrado. No hace analisis ni UI.
// Depende de XFClock, CXFTimecode, XFProfiles.
// Andamiaje (B0.1): sin logica todavia. Se implementa en el bloque B6.

/// Marcador del andamiaje del modulo. Se elimina al implementar B6.
public enum XFCapture {
    public static let scaffoldingVersion = 0
}
