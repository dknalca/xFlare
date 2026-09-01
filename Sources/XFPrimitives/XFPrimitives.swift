// SPDX-License-Identifier: GPL-3.0-only
//
// XFPrimitives — CAPA 0. El vocabulario compartido de muestras de entrada:
// `MotionSample` (el disco) y `FaderSample` (el crossfader). Son value types
// puros, `Sendable`, sin logica.
//
// Existe para romper una dependencia de capa: `XFCapture` PRODUCE estas muestras
// y `XFAnalysis` las CONSUME (dentro de `Take`), pero `XFAnalysis` no puede
// importar `XFCapture` (regla de capas de ARCHITECTURE.md §2). Ambos importan
// esto, que esta debajo de los dos. Ver ADR-033.
//
// Nota: "capa 0" aqui es posicion en el grafo (el fondo), no codigo de tiempo
// real. El hilo de audio es C (`CXFAudioCore`); esto es Swift y nunca corre
// dentro del callback.

/// Espacio de nombres y version del contrato publico de XFPrimitives.
public enum XFPrimitives {
    public static let apiVersion = 1
}
