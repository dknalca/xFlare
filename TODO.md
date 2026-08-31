# TODO — xFlare

> El orden **es** la decision. Se trabaja de arriba abajo, un bloque cada vez,
> una tarea cada vez. Lo de abajo del todo son ideas, no compromisos.
> Fuente de verdad legible por maquina: `data/backlog.json`. Ver estado: `make status`.
>
> Este es el backlog **tactico** (que tarea toca ahora). El **porque**, los
> criterios de aceptacion de fase y el alcance del MVP estan en `PLAN.md`.
> Bloques B0-B12 = MVP (v1). Lo que hay debajo de FUTURIBLES son iteraciones
> posteriores (ver `PLAN.md` seccion "Iteraciones post-v1").

Leyenda: `[ ]` pendiente · `[~]` en curso · `[x]` hecho · **SELLAR** = congelar el modulo

## Por que este orden

1. **B0 primero** porque sin `make verify` el sellado de modulos es una promesa vacia.
2. **B1 antes que nada de producto.** Contiene los dos riesgos que pueden matar el
   proyecto: la latencia de 10 ms y la captura del crossfader (ADR-021). Dias de
   prototipo desechable frente a meses de codigo encima de una suposicion.
3. **B2, B3 y B5b (reloj, notacion, perfiles) antes que el audio definitivo** porque
   son puros, se sellan rapido y te ensenan el ritmo del proceso con algo facil.
4. La UI (**B11**) va casi al final a proposito. Es lo que mas apetece y lo que mas
   tiempo se come; con el motor sin terminar, se rehace tres veces.

---

# AHORA

## B0 — Andamiaje

*Que exista el esqueleto y que `make verify` signifique algo.*

- [x] **B0.1** Package.swift con los 13 targets vacios y sus targets de test
      - Criterio: `swift build` y `swift test` pasan con 13 targets vacios (12 modulos + XFTestKit); el grafo de dependencias es el de ARCHITECTURE.md seccion 2
      - Hecho: `swift build` OK (13 targets + 12 de test + ejecutable `xFlare` compilan y enlazan; GRDB 6.29.3; verificado tambien con swift.org 5.8.1). Grafo = ARCHITECTURE §2. `swift test` **verde**: 12 tests, 0 fallos, con Xcode 14.2 / Swift 5.7.2 y tambien via `TOOLCHAINS=swift`. El crash de `libXCTestSwiftSupport` (ADR-029) se resolvio el 2026-08-31 completando el primer arranque de Xcode 14.2 (componentes de XCTest de la plataforma macOS). Existe un **ejecutable de andamiaje `xFlare`** (`make run` / `swift run xFlare`): abre ventana y pinta el Home maquetado, inerte.
- [x] **B0.2** Makefile: verify, test, seal, status, golden-update
      - Criterio: `make verify` corre y sale 0
      - Hecho: targets verify/build/test/test-advisory/seal/status/lint/profiles-check/golden-update/universal/archs/clean/toolchain-check. `verify` = build+lint+profiles-check+test-advisory; sale 0. `test` real y `seal` son estrictos y ahora pasan (ADR-029 resuelto el 2026-08-31). `test-advisory` se mantiene en `verify` como red por si otra maquina entra sin los componentes de Xcode.
- [x] **B0.3** LICENSE oficial + cabeceras en fuentes propias
      - Criterio: LICENSE descargado de gnu.org; cabecera en todo .swift/.c propio
      - Hecho: `LICENSE` = `gpl-3.0.txt` de gnu.org (674 líneas). El proyecto es **GPL-3.0-only** (xwax 1.8+ es GPLv3, ADR-030). Cabecera `SPDX-License-Identifier: GPL-3.0-only` en los 32 ficheros propios (.swift/.c/.h + `Package.swift` + `tools/*.py`). xwax vendorizado va intacto sin SPDX nuestro. README acredita xwax.
- [x] **B0.4** tools/xf_status.py operativo sobre data/backlog.json
      - Criterio: `make status` imprime hecho / en curso / siguiente
      - Hecho: `make status` lee `data/backlog.json`, imprime barra de progreso, EN CURSO y SIGUIENTES con criterios. Funciona.
- [x] **B0.5** Fijar Xcode 14.2 en el MacBook Pro 2015 con Monterey
      - Criterio: `swift --version` da 5.7.2; `swift build` funciona desde terminal
      - Hecho: Xcode 14.2 (14C18) y Swift 5.7.2 presentes; `swift build` y `swift test` OK desde terminal. Toolchain swift.org 5.8.1 instalada en ~/Library/Developer/Toolchains (compila todo, GRDB incluido) como red. El bloqueo de `swift test` (ADR-029) se cerro el 2026-08-31 al completar el primer arranque de Xcode 14.2; no hizo falta Xcode 14.1.
- [x] **B0.6** Compilacion universal x86_64 + arm64 desde el primer dia
      - Criterio: `lipo -archs` muestra las dos arquitecturas; no dejarlo para el final
      - Hecho: `swift build -c release --arch arm64 --arch x86_64` (Xcode 14.2) compila los 13 targets + GRDB para ambas arqs. `make universal`/`make archs` → objetos de modulo fat (`lipo -archs XFApp.o` = `x86_64 arm64`). El gate del ejecutable notarizado es B12.0.
- [x] **B0.7** Comprobar que xwax compila para arm64 (intrinsecos SSE en lut.c/timecoder.c) `CXFTimecode`
      - Criterio: si hay SSE, condicionarlo por arquitectura sin tocar la logica
      - Hecho: xwax 1.10 **no** usa intrínsecos SSE ni `-msse`. `swift build --arch arm64 --arch x86_64` compila `timecoder.c` y `lut.c` en ambas arqs sin condicionar nada. 2 warnings `-Wshorten-64-to-32` de xwax (no se tocan). Ver `docs/TIMECODE.md`.
- [x] **B0.8** Goldens con redondeo a 4 decimales y tolerancia 1e-9 (ADR-028)
      - Criterio: un golden generado en x86_64 pasa en arm64; definirlo ANTES de escribir el primer golden
      - Hecho: `Sources/XFTestKit/GoldenComparison.swift` con `Golden.round4`, `approxEqual` (tol 1e-9) y `firstMismatch`. Compila. Sus tests se escriben en B3 (donde se usan de verdad); `swift test` ya ejecuta (ADR-029 resuelto). Politica ya documentada en ADR-028 / TESTING.md / ARCHITECTURES.md.
- [~] **B0.9** CI en GitHub Actions: macos-13 Intel, macos-14 arm64 y trabajo universal
      - Criterio: .github/workflows/ci.yml en verde; `lipo -archs` muestra las dos
      - Estado: yaml revisado y actualizado (job universal usa `make universal`; guard de diff en `data/` tras `xfn_build`; nota de que `swift test` SI corre en runners Ventura+). **Verde pendiente de repo**: git aplazado por el autor. Se activa al crear el repo.

## B1 — Spike de latencia

*Validar barato el riesgo que puede matar el proyecto.*

- [~] **B1.1** Prototipo desechable: CoreAudio passthrough a 64 frames `CXFAudioCore`
      - Criterio: suena sin cortes 5 min
      - Estado: spike escrito en `spike/b1-latency/` (fuera de Package.swift, desechable). `passthrough.c` + `build.sh`, compila universal (x86_64+arm64). Una sola AudioUnit HAL dúplex sobre el mismo dispositivo, passthrough dentro del callback sin ring buffer (el ring buffer es B4). Cuenta overloads (listener `kAudioDeviceProcessorOverload`), render errors y jitter entre callbacks; imprime PASS/FAIL. Smoke test OK en `Built-in Output`: fija 64 frames, 0 overloads, gap 1,2–1,7 ms. **Falta la corrida real de 5 min con la Rane 72** (esta máquina no tiene dispositivo dúplex): `./passthrough --in-out "Rane" --frames 64 --seconds 300`, y anotar el resultado en `docs/TIMECODE.md` §4.1.
- [~] **B1.2** Medir round-trip real por loopback en TU hardware `CXFAudioCore`
      - Criterio: numero medido y anotado en docs/TIMECODE.md
      - Estado: herramienta escrita: `tools/measure_latency.py` (+ `tools/requirements.txt` con numpy/sounddevice). Reproduce un chirp corto por la salida y graba la entrada a la vez (`sd.playrec`), saca el desfase por correlacion cruzada via FFT (solo numpy), repite N veces e imprime min/mediana/media/max + jitter + veredicto frente a la puerta de 10 ms + linea lista para pegar en `docs/TIMECODE.md` §4.2. `--list`, `--device`, `--fs`, `--frames`, `--reps`. Sintaxis verificada. **Falta correrlo**: necesita el venv de `tools/` y un loopback fisico (cable salida→entrada, o el retorno USB del master).
- [ ] **B1.3** Decision documentada
      - Criterio: si ≤10 ms: seguir. Si no: ADR con el plan B (buffer mayor, otra interfaz, o revisar el objetivo) ANTES de escribir nada mas
      - Estado: bloqueada por los numeros de B1.2 (no hay dato que decidir todavia). `measure_latency.py` ya imprime el veredicto (DENTRO / FUERA de la puerta) para que solo haya que trasladarlo aqui.
- [~] **B1.4** Validar la captura del crossfader por tono piloto (ADR-021) `CXFAudioCore`
      - Criterio: detectar apertura/cierre del crossfader de tu mesa con menos de 5 ms de jitter; si falla, ADR con el plan C ANTES de seguir
      - Estado: spike escrito en `spike/b1-pilot-fader/` (desechable): `pilot_fader.c` + `build.sh`, compila universal, 0 warnings con `-Werror`. Genera el piloto de 19,5 kHz a −40 dBFS en la salida (tabla precalculada), analiza la entrada con **Goertzel** de un bin por hop de 64 muestras, histeresis de dos umbrales, y encola cada flanco con su instante en un ring SPSC lock-free. Modos `--selfcheck` (calibra umbrales con un cable, sin mesa) y deteccion (imprime flancos + desv. tipica de los intervalos vs el criterio de 5 ms). **Falta correrlo con la Rane 72.**
- [ ] **B1.5** Medir la latencia en LAS DOS maquinas y rellenar la tabla `CXFAudioCore`
      - Criterio: PLATFORM_SUPPORT.md seccion 7 con numeros reales, no estimaciones
      - Estado: misma herramienta que B1.2 (`tools/measure_latency.py`). Bloqueada por hardware: hay que correrla en el MacBook Pro 2015 y en la maquina de referencia. La tabla vacia ya esta en `PLATFORM_SUPPORT.md` §7 y en `docs/TIMECODE.md` §4.2.
- [~] **B1.6** Buffer adaptativo 64 -> 128 frames al detectar overloads (ADR-024) `CXFAudioCore`
      - Criterio: el Intel de 2015 aguanta 5 min sin cortes
      - Estado: logica escrita en el spike B1.1: flag `--adaptive`. Cuando se acumulan ≥3 overloads, el hilo main (no el RT) para la unit, sube el buffer del dispositivo a 128, reinicia contadores y arranca de nuevo; lo registra y el resumen distingue "PASS" de "PASS CON RESERVA" (solo aguanta a 128). **Falta la corrida real de 5 min en el Intel de 2015.**
- [ ] **B1.7** Verificar driver de audio de la mesa en Monterey
      - Criterio: la Rane 72 (MK1) enumera sus canales USB en Monterey
      - Estado: bloqueada por hardware. Herramienta lista: `spike/b1-latency/passthrough --list` (y el de pilot) enumeran cada dispositivo con sus canales in/out, sample rate y buffer. Basta enchufar la mesa y mirar que la Rane 72 aparece con sus canales USB.


---

# SIGUIENTE

## B2 — XFClock

*El reloj musical. Puro, pequeno, se sella rapido.*

- [ ] **B2.1** Conversiones tick / ms / hostTime con PPQ 480 `XFClock`
      - Criterio: tests de ida y vuelta sin perdida en 10.000 valores
- [ ] **B2.2** Transporte: play, stop, loop, cuenta atras de N compases `XFClock`
      - Criterio: tests de estado y de limites
- [ ] **B2.3** ClockMap: mapear una captura a ticks `XFClock`
      - Criterio: test con desfase y con tempo distinto
- [ ] **B2.4** **SELLAR XFClock** `XFClock`
      - Criterio: cumple las 5 condiciones de ARCHITECTURE.md seccion 6

## B3 — XFNotation

*El modelo XFN en Swift, validado contra la referencia Python.*

- [ ] **B3.1** Modelos Codable: Scratch, Exercise, Level, primitivas `XFNotation`
      - Criterio: decodifican data/*.json sin perdida; validan contra data/schema/*.json
- [ ] **B3.2** Portar el compositor mano x fader de xfn_core.py a Swift `XFNotation`
- [ ] **B3.3** Golden: la libreria compilada en Swift es identica a library-v0.1.json `XFNotation`
      - Criterio: diff vacio byte a byte sobre los 25 scratches
- [ ] **B3.4** Fases con tramo parcial de curva (u0/u1) y funcion de recorte `XFNotation`
      - Criterio: recortar por mitad de un movimiento conserva la curva exacta, no la aproxima con rectas
- [ ] **B3.5** Transformaciones de variante: offset, amplitude, mirror, subdivision, swing `XFNotation`
      - Criterio: golden contra las variantes generadas por tools/xfn_core.py
- [ ] **B3.6** Calculo de eventos evaluables y maxScore por variante `XFNotation`
      - Criterio: 2-Click Flare base = 3.600; su div16 = 4.800
- [ ] **B3.7** **SELLAR XFNotation** `XFNotation`

## B4 — CXFAudioCore

*El motor de audio en serio, esta vez para quedarse.*

- [ ] **B4.1** Ring buffer SPSC lock-free en C `CXFAudioCore`
      - Criterio: tests al 100%, incluido productor/consumidor concurrente
- [ ] **B4.2** Callback CoreAudio RT-safe, 64 frames, con thread_policy_set Y workgroup de audio `CXFAudioCore`
      - Criterio: 0 malloc/locks verificado con Instruments; el hilo se une al workgroup del dispositivo (obligatorio en Apple Silicon)
- [ ] **B4.3** Reproductor de sample con resampling por velocidad y direccion `CXFAudioCore`
      - Criterio: scratch audible sin clicks ni aliasing
- [ ] **B4.4** Metronomo mezclado en la salida principal (ADR-007) `CXFAudioCore`
- [ ] **B4.5** **PUERTA DE CALIDAD: ≤10 ms, 0 overloads en 5 min** `CXFAudioCore`
      - Criterio: medido y documentado en docs/TIMECODE.md
- [ ] **B4.6** **SELLAR CXFAudioCore** `CXFAudioCore`

## B5 — CXFTimecode

*Leer el vinilo.*

- [x] **B5.1** Vendorizar xwax INTACTO en vendor/xwax con sus cabeceras `CXFTimecode`
      - Criterio: compila sin modificar timecoder.c ni lut.c
      - Hecho: xwax **1.10** (GPL-3.0, ADR-030) en `Sources/CXFTimecode/vendor/xwax/`: `timecoder.{c,h}`, `lut.{c,h}`, `debug.h`, `pitch.h`, intactos. `Package.swift` añade `vendor/xwax` al headerSearchPath. SwiftPM compila `timecoder.c` y `lut.c` sin tocarlos, en x86_64 y arm64. Ver `docs/TIMECODE.md`.
- [ ] **B5.2** Wrapper xf_timecode en modo relativo (ADR-005) `CXFTimecode`
- [ ] **B5.3** Hamster / reverse desde el dia 1 `CXFTimecode`
      - Criterio: test con senal invertida
- [ ] **B5.4** Confianza de senal y recuperacion de dropout `CXFTimecode`
      - Criterio: no se cuelga al levantar la aguja
- [ ] **B5.5** **SELLAR CXFTimecode** `CXFTimecode`

## B5b — XFProfiles

*Perfiles .conf por modelo de mesa. Puro parseo, se sella rapido.*

- [ ] **B5b.1** Parser INI propio, sin dependencias (ADR-019) `XFProfiles`
      - Criterio: carga los 6 perfiles de profiles/ sin perdida
- [ ] **B5b.2** Resolucion de extends con deteccion de herencia circular `XFProfiles`
      - Criterio: pioneer-djm-s9 resuelve heredando de la s11; un ciclo da error claro
- [ ] **B5b.3** Validacion equivalente a tools/xf_profile.py `XFProfiles`
      - Criterio: mismos errores que el validador Python sobre los mismos ficheros
- [ ] **B5b.4** Autodeteccion por nombre de puerto MIDI y dispositivo de audio `XFProfiles`
      - Criterio: comodines * funcionan; si hay empate, no elige, pregunta
- [ ] **B5b.5** Carga desde el bundle y desde la carpeta del usuario, con precedencia `XFProfiles`
      - Criterio: segun DEVICE_PROFILES.md seccion 5
- [ ] **B5b.6** **SELLAR XFProfiles** `XFProfiles`


---

# DESPUES

## B6 — XFCapture

*Abstraer la entrada. Aqui se desbloquea el desarrollo sin mesa.*

- [ ] **B6.1** Protocolos MotionSource y FaderSource `XFCapture`
- [ ] **B6.2** KeyboardMotionSource y KeyboardFaderSource (modo sin mesa) `XFCapture`
      - Criterio: se puede hacer un baby scratch con el teclado
- [ ] **B6.3** TimecodeMotionSource sobre CXFTimecode `XFCapture`
- [ ] **B6.4** MidiFaderSource (CoreMIDI) + fallback por envolvente de audio `XFCapture`
      - Criterio: funciona con Rane 72 (MK1); si no emite MIDI, cae al fallback solo
- [ ] **B6.4b** AudioReturnFaderSource: tono piloto y deteccion (ADR-021) `XFCapture`
      - Criterio: funciona con el perfil rane-seventy-two
- [ ] **B6.5** Binarizacion del fader con cut-in calibrado e histeresis (ADR-017) `XFCapture`
      - Criterio: 0 eventos fantasma en 1 min de fader quieto
- [ ] **B6.6** Formato .xfsession: grabar y reproducir + ReplaySource `XFCapture`
      - Criterio: una sesion grabada se reproduce bit a bit igual
- [ ] **B6.7** **SELLAR XFCapture** `XFCapture`

## B7 — XFDesign + XFRender

*Que se vea, y que se vea bien.*

- [ ] **B7.1** Tokens de diseno de UI_DESIGN.md seccion 2 `XFDesign`
- [ ] **B7.2** Componentes base: tarjeta, boton, stepper de BPM, badge de acierto `XFDesign`
- [ ] **B7.2b** Render sincronizado al refresco real, 60 fps garantizados en Intel (ADR-024) `XFRender`
      - Criterio: 60 fps estables en el MacBook Pro 2015 con la autopista completa
- [ ] **B7.3** Escena SpriteKit de la autopista, sincronizada al reloj de AUDIO `XFRender`
      - Criterio: sin deriva tras 10 min; 120 fps en ProMotion
- [ ] **B7.4** Capa fantasma + capa usuario + tenido por tolerancia `XFRender`
- [ ] **B7.5** Scope circular del plato (Lissajous) `XFRender`
- [ ] **B7.6** Golden tests de render en SVG `XFRender`
      - Criterio: los 25 scratches contra Fixtures/golden/
- [ ] **B7.7** **SELLAR XFDesign y XFRender** `XFDesign,XFRender`

## B8 — XFAnalysis

*El cerebro. Funciones puras, cero hardware.*

- [ ] **B8.1** Emparejado de clicks objetivo/usuario y desfase con signo `XFAnalysis`
- [ ] **B8.2** DTW de contorno de tono, afinacion relativa (ADR-005) `XFAnalysis`
- [ ] **B8.3** Consistencia (sigma) y amplitud de recorrido `XFAnalysis`
- [ ] **B8.4** Generador de diagnosticos en lenguaje natural (ADR-018) `XFAnalysis`
      - Criterio: distingue sesgo sistematico de dispersion y lo dice distinto
- [ ] **B8.5** Tests de replay: good / late / sloppy por patron de nivel 1-4 `XFAnalysis`
      - Criterio: segun docs/TESTING.md
- [ ] **B8.6** Puntuacion por evento y total sobre maxScore `XFAnalysis`
      - Criterio: docs/SCORING.md seccion 1
- [ ] **B8.7** Tres estrellas por criterios ortogonales (ADR-025) `XFAnalysis`
      - Criterio: un 88% con un fallo da 1 estrella, no 2
- [ ] **B8.8** **SELLAR XFAnalysis** `XFAnalysis`

## B9 — XFEngine

*La sesion de gimnasio.*

- [ ] **B9.1** Maquina de estados: calentamiento, series, descanso, boss, resultados `XFEngine`
- [ ] **B9.2** Escalera de BPM adaptativa (2 fallos baja, 3 aciertos sube) `XFEngine`
- [ ] **B9.3** Desbloqueo por compases consecutivos, no por media `XFEngine`
- [ ] **B9.4** **SELLAR XFEngine** `XFEngine`

## B10 — XFPersistence

*Que el progreso sobreviva a cerrar la app.*

- [ ] **B10.1** Esquema GRDB y migraciones `XFPersistence`
- [ ] **B10.2** Historico de tomas, progreso y desbloqueos `XFPersistence`
- [ ] **B10.3** Repeticion espaciada (1, 3, 7, 21 dias) `XFPersistence`
- [ ] **B10.4** Perfiles de calibracion por dispositivo `XFPersistence`
- [ ] **B10.6** Tabla de intentos con eventScores y ruta al .xfsession `XFPersistence`
      - Criterio: data/schema/attempt.schema.json
- [ ] **B10.7** Progreso agregado: intentos, mejor, media de 5, mejor BPM con 3★, sesgo medio `XFPersistence`
      - Criterio: docs/SCORING.md seccion 3
- [ ] **B10.8** Estado de dominado y desbloqueo de variantes `XFPersistence`
      - Criterio: 3★ base + 2★ en tres variantes
- [ ] **B10.9** **SELLAR XFPersistence** `XFPersistence`

## B11 — XFApp

*Las pantallas.*

- [ ] **B11.1** Asistente de calibracion de 4 pasos `XFApp`
      - Criterio: un usuario nuevo llega a tocar sin ayuda externa
- [ ] **B11.2** Home: mapa de la matriz, racha, continuar `XFApp`
      - Nota: ya existe una **maqueta inerte** en `Sources/xFlare/HomeScaffoldView.swift`
        (ejecutable `xFlare`, `make run`). Sirve de referencia visual; aquí se hace la de verdad en XFApp y se borra la maqueta.
- [ ] **B11.3** Pantalla de practica (la autopista) `XFApp`
- [ ] **B11.4** Pantalla de resultados con diagnostico `XFApp`
- [ ] **B11.5** Modo libre con grabacion de los ultimos 30 s `XFApp`
- [ ] **B11.6** Navegador de la libreria `XFApp`
- [ ] **B11.7** Ajustes `XFApp`
- [ ] **B11.8** Accesibilidad: VoiceOver, alto contraste, teclado `XFApp`
      - Criterio: segun UI_DESIGN.md seccion 4
- [ ] **B11.9** Pantalla Mi mesa: lista de perfiles, insignias y prueba en vivo `XFApp`
      - Criterio: UI_DESIGN.md 3.8
- [ ] **B11.10** Asistente de mapeo MIDI/HID con monitor en crudo `XFApp`
      - Criterio: UI_DESIGN.md 3.9; si no llega MIDI en 5 s, propone audio_return
- [ ] **B11.11** Exportar perfil y flujo de aportacion `XFApp`
      - Criterio: genera un .conf valido segun tools/xf_profile.py
- [ ] **B11.12** Permiso de microfono con texto honesto y pantalla de ayuda si se deniega `XFApp`
      - Criterio: si el usuario dice que no, la app explica que hacer
- [ ] **B11.13** Resultados con estrellas y puntuacion sobre el maximo `XFApp`
      - Criterio: las estrellas apagadas dicen que falta para conseguirlas
- [ ] **B11.14** Pantalla de progreso por ejercicio y variante `XFApp`
      - Criterio: UI_DESIGN.md 3.4b
- [ ] **B11.15** Selector de variantes con estado de bloqueo `XFApp`
      - Criterio: muestra la condicion de desbloqueo, no solo el candado
- [ ] **B11.16** Detectar Rosetta (sysctl.proc_translated) y avisar en calibracion `XFApp`
      - Criterio: si esta traducido, la app lo dice y ofrece la version universal

## B12 — Distribucion

*Que lo pueda usar alguien que no seas tu.*

- [ ] **B12.0** Verificar binario universal y pasar la matriz de pruebas en las dos maquinas
      - Criterio: PLATFORM_SUPPORT.md seccion 9 completa
- [ ] **B12.1** Firma y notarizacion
- [ ] **B12.2** DMG
- [ ] **B12.3** Formula de Homebrew
- [ ] **B12.4** README publico, capturas, video de 30 s
- [ ] **B12.5** 5 DJs probandolo y sus notas
      - Criterio: el examen de verdad


---

# FUTURIBLES

## FUT — Futuribles

*No tocar hasta que la v1 este en manos de gente.*

- [ ] **F.0** Calentamiento adaptativo con deteccion de oxidacion (ADR-027)
      - Criterio: docs/WARMUP.md; el esquema de BD ya lo soporta desde la v1
- [ ] **F.0b** Variantes avanzadas: encadenado, densidad creciente, rampa de tempo, un solo lado `XFNotation`
      - Criterio: docs/VARIANTS.md seccion 4
- [ ] **F.1** Dos platos: juggling, chasing, notacion de doble carril
- [ ] **F.2** Pads y sampler; scratch sobre pads
- [ ] **F.3** Importar tus propios samples con deteccion del punto cero
- [ ] **F.4** Exportar la toma como video vertical para compartir
      - Criterio: el bucle de crecimiento mas barato que existe
- [ ] **F.5** Transcribir un scratch desde audio o video a XFN
      - Criterio: la funcion asesina: apuntas a un video y te saca la notacion
- [ ] **F.6** Rutinas y lecciones creadas por usuarios
- [ ] **F.7** Retos diarios
- [ ] **F.8** Mas mesas: Pioneer S9/S11, Ecler, Omnitronic
- [ ] **F.9** Port a Linux y Windows
      - Criterio: xwax ya es multiplataforma; lo caro es la UI
- [ ] **F.10** Modo profesor: dos usuarios, comparativa lado a lado
- [ ] **F.11** Repositorio comunitario de perfiles con actualizacion desde la app
      - Criterio: solo cuando haya suficientes perfiles verificados como para que merezca la pena

---

## Reglas de uso

- No se empieza un bloque sin cerrar el anterior.
- Una tarea no esta hecha hasta que `make verify` esta en verde.
- Las tareas **SELLAR** son el momento en que el modulo deja de poder romperse.
- Se desarrolla y se prueba en el MacBook Pro Intel de 2015. Es la maquina de referencia.
- El binario es universal desde B0.6. arm64 se cubre con CI, no con hardware.
- Si aparece trabajo nuevo, va a FUTURIBLES por defecto.
