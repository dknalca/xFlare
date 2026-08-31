// SPDX-License-Identifier: GPL-3.0-only
//
// XFAnalysis — CAPA 1. DTW, emparejado de clicks, scoring, diagnostico.
// Funciones puras: sin hardware, sin UI, sin disco. Corre FUERA del hilo de
// audio. Depende de XFNotation, XFClock.
// Andamiaje (B0.1): sin logica todavia. Se implementa en el bloque B8.

/// Marcador del andamiaje del modulo. Se elimina al implementar B8.
public enum XFAnalysis {
    public static let scaffoldingVersion = 0
}
