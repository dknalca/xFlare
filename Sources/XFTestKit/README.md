# XFTestKit

Utilidades **solo para tests**. No es un módulo sellable ni entra en el binario
de la app; está en el grafo (`Package.swift`) para que los `*Tests` puedan
importarlo.

Depende de `XFCapture`, `XFNotation`, `XFPrimitives`.

## Qué hay

| Pieza | Para qué |
|---|---|
| `Golden` | Comparar goldens numéricos entre `x86_64` y `arm64` sin falsos rojos: `round4` (redondeo a 4 decimales antes de serializar) + `approxEqual` / `firstMismatch` con tolerancia `1e-9`. Regla ADR-028. |
| `Signals` | Señales sintéticas deterministas: `sine`, `silence` (PCM mono float) y `quadratureTimecode` (vinilo de timecode falso, estéreo int16 — `carrierHz` fija la velocidad, `secondaryPhaseDeg` el sentido). |
| `FakeMotionSource` / `FakeFaderSource` | Implementaciones de mentira de los protocolos de `XFCapture`: modo *script* (una muestra por `latest()`) o *valor fijo*, con conteo de `start()`/`stop()` y `startError` para simular un fallo de arranque. |
| `RepoFiles` | `root()` / `url(_:)` / `data(_:)` / `text(_:)` para leer ficheros del repo (`data/`, `Fixtures/`, goldens) desde un test, subiendo desde `#filePath` hasta `Package.swift`. |
| `Fixtures/` | Recursos empaquetados con el módulo (`.xfsession` de replay, goldens). Se localizan con `XFTestKit.fixturesURL`. |

## Convenciones

- `Golden.round4` **siempre** antes de escribir un valor de referencia.
- Nada de comparar texto de golden crudo: pasa por `Golden`.
- Las fuentes falsas cubren los tests que no necesitan la mesa; el hardware real
  sigue siendo la puerta de `B5.5` / `B6.7`.
