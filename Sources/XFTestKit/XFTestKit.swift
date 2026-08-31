// SPDX-License-Identifier: GPL-3.0-only
//
// XFTestKit — utilidades de test: fixtures, fuentes falsas, helpers de golden.
// NUNCA entra en el binario final. Depende de XFCapture, XFNotation.
// Andamiaje (B0.1): sin helpers todavia. Se van anadiendo segun cada modulo
// los necesite (primero en el bloque B3).

import Foundation

/// Marcador del andamiaje. Ademas expone la carpeta de fixtures empaquetada
/// como recurso, para que los tests localicen los .xfsession y los golden.
public enum XFTestKit {
    public static let scaffoldingVersion = 0

    /// URL de la carpeta `Fixtures/` copiada como recurso del bundle del modulo.
    public static var fixturesURL: URL? {
        Bundle.module.url(forResource: "Fixtures", withExtension: nil)
    }
}
