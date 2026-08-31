# Estado de los modulos

Estados: `TODO` (no existe) · `WIP` (en desarrollo) · `SEALED` (terminado y
congelado, ver `ARCHITECTURE.md` seccion 6) · `BROKEN` (regresion detectada).

| Modulo | Capa | Estado | Sellado el | Tests | Notas |
|---|---|---|---|---|---|
| `CXFAudioCore` | 0 | TODO | — | — | |
| `CXFTimecode` | 0 | TODO | — | — | xwax vendorizado, no tocar |
| `XFClock` | 1 | TODO | — | — | |
| `XFNotation` | 1 | TODO | — | — | Ya existe la spec y los datos |
| `XFProfiles` | 1 | TODO | — | — | Perfiles .conf de mesa |
| `XFCapture` | 1 | TODO | — | — | |
| `XFAnalysis` | 1 | TODO | — | — | |
| `XFPersistence` | 1 | TODO | — | — | |
| `XFEngine` | 1 | TODO | — | — | |
| `XFDesign` | 2 | TODO | — | — | |
| `XFRender` | 2 | TODO | — | — | |
| `XFTestKit` | — | TODO | — | — | |
| `XFApp` | 3 | TODO | — | — | |

## Registro de re-sellados

Cada vez que un modulo SEALED se modifica, una linea aqui con el ADR que lo
justifica. Si esta tabla crece rapido, el diseno de modulos esta mal.

| Fecha | Modulo | ADR | Motivo |
|---|---|---|---|
| — | — | — | — |
