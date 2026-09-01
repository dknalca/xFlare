// SPDX-License-Identifier: GPL-3.0-only
//
// XFAnalysis — CAPA 1. Emparejado de clicks, contorno de tono (DTW), sigma,
// scoring por evento, estrellas y diagnostico en lenguaje natural.
//
// Funciones PURAS: reciben un `Take` (muestras ya capturadas + `ClockMap`) y un
// `Scratch` objetivo, y devuelven un `Report`. Sin hardware, sin UI, sin disco,
// fuera del hilo de audio. Un `Report` se calcula igual venga la entrada de la
// mesa o de un `.xfsession` -> el scoring se desarrolla y se testea sin mesa.
//
// Depende de XFPrimitives, XFNotation, XFClock.

/// Espacio de nombres y version del contrato publico de XFAnalysis.
public enum XFAnalysis {
    public static let apiVersion = 1
}
