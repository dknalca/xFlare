// SPDX-License-Identifier: GPL-3.0-only
//
// XFRender — CAPA 2. Escena SpriteKit: autopista, scope Lissajous, capa
// fantasma. Dibuja lo que le dicen y ya. No lee hardware ni base de datos.
// Se sincroniza al reloj de AUDIO, nunca al frame. Depende de XFDesign, XFNotation.
//
// Estado: autopista (B7.3) — `HighwayLayout` (geometria pura, testeable) +
// `HighwayScene` / `HighwayView` (SpriteKit, delgadas). Falta capa de usuario y
// tenido por tolerancia (B7.4), scope Lissajous (B7.5) y golden SVG (B7.6).

/// Espacio de nombres y version del contrato publico de XFRender.
public enum XFRender {
    public static let apiVersion = 1
}
