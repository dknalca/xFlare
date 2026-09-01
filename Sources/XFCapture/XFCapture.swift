// SPDX-License-Identifier: GPL-3.0-only
//
// XFCapture — CAPA 1. Fuentes de entrada: timecode, MIDI, teclado, replay.
// Binarizacion del fader con el cut-in calibrado. No hace analisis ni UI.
// Depende de XFPrimitives, XFClock, CXFTimecode, XFProfiles.
//
// Estado: protocolos de frontera (B6.1) y formato `.xfsession` + fuentes de
// replay (B6.6) hechos. Las fuentes de hardware (MIDI, timecode, retorno de
// audio) y el modo teclado llegan cuando haya mesa delante.

/// Espacio de nombres y version del contrato publico de XFCapture.
public enum XFCapture {
    public static let apiVersion = 1
}
