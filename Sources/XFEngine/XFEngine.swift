// SPDX-License-Identifier: GPL-3.0-only
//
// XFEngine — CAPA 1. Maquina de estados de la sesion de gimnasio. El unico
// modulo que orquesta a los demas de la capa 1. No dibuja.
// Depende de XFNotation, XFCapture, XFAnalysis, XFPersistence, CXFAudioCore.
//
// Estado: B9.1 hecho — `SessionMachine` encadena las fases de la sesion
// (calentamiento, series, descanso, boss, resultados). Falta la escalera de BPM
// adaptativa (B9.2) y el desbloqueo por compases seguidos (B9.3).

/// Espacio de nombres y version del contrato publico de XFEngine.
public enum XFEngine {
    public static let apiVersion = 1
}
