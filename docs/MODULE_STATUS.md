# Estado de los modulos

Estados: `TODO` (no existe) · `WIP` (en desarrollo) · `SEALED` (terminado y
congelado, ver `ARCHITECTURE.md` seccion 6) · `BROKEN` (regresion detectada).

| Modulo | Capa | Estado | Sellado el | Tests | Notas |
|---|---|---|---|---|---|
| `CXFAudioCore` | 0 | WIP | — | 7 verdes | `xf_ring` SPSC lock-free hecho (B4.1). Callback CoreAudio / resampling / metronomo / puerta de latencia (B4.2-B4.5) bloqueados por hardware + Instruments |
| `XFPrimitives` | 0 | SEALED | 2026-09-01 | 4 verdes | apiVersion 1. `MotionSample` / `FaderSample` (value types compartidos capture↔analysis). ADR-033 |
| `CXFTimecode` | 0 | TODO | — | — | xwax vendorizado, no tocar |
| `XFClock` | 1 | SEALED | 2026-08-31 | 34 verdes | apiVersion 1. Tick/PPQ 480, Tempo, TimeSignature, HostClock, ClockMap, Transport. ADR-031 |
| `XFNotation` | 1 | SEALED | 2026-09-01 | 20 verdes | apiVersion 1. Modelo XFN + compose (port de xfn_core.py) + crop con tramo parcial + variantes offset/amplitude/mirror/swing/subdivision + ScoreEvents (== SCORING.md) + golden vs library-v0.1.json. ADR-032 |
| `XFProfiles` | 1 | SEALED | 2026-08-31 | 24 verdes | apiVersion 1. Parser INI propio (ADR-019), extends + herencia circular, validacion == xf_profile.py, autodeteccion con comodines, precedencia bundle/usuario |
| `XFCapture` | 1 | WIP | — | 11 verdes | Protocolos `MotionSource`/`FaderSource` (B6.1) + formato `.xfsession` y `Replay*Source` (B6.6). Fuentes de hardware/teclado y binarizacion (B6.2-B6.5) pendientes |
| `XFAnalysis` | 1 | WIP | — | 10 verdes | Emparejado de clicks, DTW de contorno, sigma/sesgo, amplitud, scoring por evento (== SCORING.md), 3 estrellas (ADR-025), diagnostico NL (ADR-018). Sin sellar: B8.5 necesita `.xfsession` reales, B8.4 umbrales por afinar |
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
