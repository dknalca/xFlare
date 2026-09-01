# Estado de los modulos

Estados: `TODO` (no existe) · `WIP` (en desarrollo) · `SEALED` (terminado y
congelado, ver `ARCHITECTURE.md` seccion 6) · `BROKEN` (regresion detectada).

| Modulo | Capa | Estado | Sellado el | Tests | Notas |
|---|---|---|---|---|---|
| `CXFAudioCore` | 0 | WIP | — | 7 verdes | `xf_ring` SPSC lock-free hecho (B4.1). Callback CoreAudio / resampling / metronomo / puerta de latencia (B4.2-B4.5) bloqueados por hardware + Instruments |
| `XFPrimitives` | 0 | SEALED | 2026-09-01 | 4 verdes | apiVersion 1. `MotionSample` / `FaderSample` (value types compartidos capture↔analysis). ADR-033 |
| `CXFTimecode` | 0 | WIP | — | 7 verdes | xwax 1.10 vendorizado intacto (B5.1) + wrapper `xf_timecoder` en modo relativo (B5.2), hamster/reverse (B5.3), confianza + dropout (B5.4). Tests con señal de cuadratura sintética. Falta pasar un vinilo real para sellar (B5.5) |
| `XFClock` | 1 | SEALED | 2026-08-31 | 34 verdes | apiVersion 1. Tick/PPQ 480, Tempo, TimeSignature, HostClock, ClockMap, Transport. ADR-031 |
| `XFNotation` | 1 | SEALED | 2026-09-01 | 20 verdes | apiVersion 1. Modelo XFN + compose (port de xfn_core.py) + crop con tramo parcial + variantes offset/amplitude/mirror/swing/subdivision + ScoreEvents (== SCORING.md) + golden vs library-v0.1.json. ADR-032 |
| `XFProfiles` | 1 | SEALED | 2026-08-31 | 24 verdes | apiVersion 1. Parser INI propio (ADR-019), extends + herencia circular, validacion == xf_profile.py, autodeteccion con comodines, precedencia bundle/usuario |
| `XFCapture` | 1 | WIP | — | 41 verdes | Protocolos (B6.1), teclado (B6.2), `TimecodeMotionSource` sobre `CXFTimecode` (B6.3), `FaderBinarizer` (B6.5), `.xfsession` + `Replay*Source` (B6.6), decodificacion HID (`HIDCrossfaderConfig`/`HIDFaderSource`). Falta los conectores CoreMIDI/IOHIDManager/audio-return (B6.4/B6.4b) para sellar |
| `XFAnalysis` | 1 | WIP | — | 10 verdes | Emparejado de clicks, DTW de contorno, sigma/sesgo, amplitud, scoring por evento (== SCORING.md), 3 estrellas (ADR-025), diagnostico NL (ADR-018). Sin sellar: B8.5 necesita `.xfsession` reales, B8.4 umbrales por afinar |
| `XFPersistence` | 1 | SEALED | 2026-09-01 | 44 verdes | apiVersion 1. `XFDatabase` (puerta unica, GRDB 6.x, migracion `v1` con 10 tablas). Records + metodos por concern: histrico de tomas + eventScores (B10.2/B10.6), progreso agregado (B10.7, == SCORING.md §3), dominado + desbloqueo de variantes (B10.8), repeticion espaciada 1/3/7/21 (B10.3), calibracion por dispositivo (B10.4). Reglas de producto dentro, catalogo fuera. ADR-035 |
| `XFEngine` | 1 | SEALED | 2026-09-01 | 38 verdes | apiVersion 1. Facade `Session` (B9.4, ADR-034) cableando `SessionMachine` (fases), `BPMLadder` (tempo adaptativo: 3 aprobados suben, 2 fallos bajan) y `UnlockRule`/`UnlockTracker` (desbloqueo por N compases buenos seguidos, no por media). Todo struct valor que avanza por eventos como `Transport`. Una serie se aprueba por streak de compases limpios, no por media (ADR-034) |
| `XFDesign` | 2 | SEALED | 2026-09-01 | 7 verdes | apiVersion 1. Tokens (color, espaciado, tipografía, HitLevel) + componentes base (XFCard, XFButtonStyle, BPMStepper, HitBadge). macOS 11. ADR-036 |
| `XFRender` | 2 | SEALED | 2026-09-01 | 34 verdes | apiVersion 1. `HighwayLayout` (autopista: fantasma + capa de usuario teñida por `HitLevel` + cabeza de lectura, loop con el patron, anti-deriva `frame(T)==frame(T+L)`). `ScopeLayout` (scope circular, Lissajous reconstruido de `position`/`confidence`). `HighwaySVG` (golden SVG de los 25). Escenas/vistas SpriteKit+SwiftUI delgadas, sincronizadas al reloj de AUDIO. fps en la maquina pendiente y aditivo (B7.2b). ADR-036 |
| `XFTestKit` | — | TODO | — | — | |
| `XFApp` | 3 | TODO | — | — | |

## Registro de re-sellados

Cada vez que un modulo SEALED se modifica, una linea aqui con el ADR que lo
justifica. Si esta tabla crece rapido, el diseno de modulos esta mal.

| Fecha | Modulo | ADR | Motivo |
|---|---|---|---|
| — | — | — | — |
