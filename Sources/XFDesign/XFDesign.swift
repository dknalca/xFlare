// SPDX-License-Identifier: GPL-3.0-only
//
// XFDesign — CAPA 2. Tokens de diseno y componentes SwiftUI reutilizables
// (docs/UI_DESIGN.md seccion 2). Sin logica de negocio, sin dependencias.
//
// Estado: tokens (B7.1) y componentes base (B7.2). Deployment target macOS 11:
// solo APIs de SwiftUI disponibles ahi (nada de NavigationStack, @Observable,
// etc. — ver docs/PLATFORM_SUPPORT.md §4).

/// Espacio de nombres y version del contrato publico de XFDesign.
public enum XFDesign {
    public static let apiVersion = 1
}
