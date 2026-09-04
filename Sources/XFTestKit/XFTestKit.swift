// SPDX-License-Identifier: GPL-3.0-only
//
// XFTestKit — utilidades de test. NUNCA entra en el binario final.
//
// Contenido:
//  - `Golden`            comparación de goldens tolerante a la arquitectura (ADR-028).
//  - `Signals`           señales sintéticas: seno, silencio, timecode de cuadratura.
//  - `FakeMotionSource`  fuentes de `XFCapture` de mentira (sin hardware ni ficheros),
//    `FakeFaderSource`   con script o valor fijo y conteo de start()/stop().
//  - `RepoFiles`         localiza ficheros del repo (`data/`, `Fixtures/`) desde un test.
//  - `Fixtures/`         recursos empaquetados (goldens, `.xfsession`), vía `fixturesURL`.
//
// Depende de XFCapture, XFNotation, XFPrimitives.

import Foundation

public enum XFTestKit {
    /// Marcador histórico del andamiaje (B0.1). Se mantiene en 0 por
    /// compatibilidad con el smoke test de `XFEngineTests` (módulo sellado).
    public static let scaffoldingVersion = 0

    /// URL de la carpeta `Fixtures/` copiada como recurso del bundle del módulo.
    public static var fixturesURL: URL? {
        Bundle.module.url(forResource: "Fixtures", withExtension: nil)
    }
}
