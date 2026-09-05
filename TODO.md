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
      - Hecho: `swift build -c release --arch arm64 --arch x86_64` (Xcode 14.2) compila los 13 targets + GRDB para ambas arqs. `make universal`/`make archs` → objetos de modulo fat (`lipo -archs XFApp.o` = `x86_64 arm64`). El gate del ejecutable notarizado es B12b (ADR-037); B12a.2 revalida el universal.
- [x] **B0.7** Comprobar que xwax compila para arm64 (intrinsecos SSE en lut.c/timecoder.c) `CXFTimecode`
      - Criterio: si hay SSE, condicionarlo por arquitectura sin tocar la logica
      - Hecho: xwax 1.10 **no** usa intrínsecos SSE ni `-msse`. `swift build --arch arm64 --arch x86_64` compila `timecoder.c` y `lut.c` en ambas arqs sin condicionar nada. 2 warnings `-Wshorten-64-to-32` de xwax (no se tocan). Ver `docs/TIMECODE.md`.
- [x] **B0.8** Goldens con redondeo a 4 decimales y tolerancia 1e-9 (ADR-028)
      - Criterio: un golden generado en x86_64 pasa en arm64; definirlo ANTES de escribir el primer golden
      - Hecho: `Sources/XFTestKit/GoldenComparison.swift` con `Golden.round4`, `approxEqual` (tol 1e-9) y `firstMismatch`. Compila. Sus tests se escriben en B3 (donde se usan de verdad); `swift test` ya ejecuta (ADR-029 resuelto). Politica ya documentada en ADR-028 / TESTING.md / ARCHITECTURES.md.
- [x] **B0.9** CI en GitHub Actions: arm64 + trabajo universal
      - Criterio: .github/workflows/ci.yml en verde; `lipo -archs` muestra las dos
      - Hecho (2026-09-01): repo `dknalca/xFlare` **público**. Se retiró el job `macos-13` (Intel/Ventura): no es el OS objetivo (el target es Monterey 12.7, sin runner en GitHub) y no cogía runner. CI = **2 jobs en `macos-14`**: `test-arm64` (`swift test` 143 tests + `xf_profile.py --all` + guard de `data/`) y `universal` (`make universal` → `lipo -archs` = `x86_64 arm64`). El x86_64/Monterey lo cubre la máquina de referencia con `make verify`. Run `33478377340` (commit `9056fcf`): **completed / success**, ambos jobs verdes.

## B1 — Spike de latencia

*Validar barato el riesgo que puede matar el proyecto.*

> **El día que conectes el hardware:** `docs/HW_BRINGUP.md` tiene la secuencia
> completa (B1.1→B1.7, B4.5, B5.5, B6.7) — comando, número a leer, dónde se
> anota y la puerta de cada paso. Los tres spikes compilan a 2026-09-02.

- [~] **B1.1** Prototipo desechable: CoreAudio passthrough a 64 frames `CXFAudioCore`
      - Criterio: suena sin cortes 5 min
      - Estado: spike escrito en `spike/b1-latency/` (fuera de Package.swift, desechable). `passthrough.c` + `build.sh`, compila universal (x86_64+arm64). Una sola AudioUnit HAL dúplex sobre el mismo dispositivo, passthrough dentro del callback sin ring buffer (el ring buffer es B4). Cuenta overloads (listener `kAudioDeviceProcessorOverload`), render errors y jitter entre callbacks; imprime PASS/FAIL. Smoke test OK en `Built-in Output`: fija 64 frames, 0 overloads, gap 1,2–1,7 ms.
      - **(2026-09-04) Rane 72 conectada por USB** — enumera dúplex (14 in / 10 out, 48 kHz, ver B1.7). **Falta la corrida real de 5 min**: `./passthrough --in-out "Seventy-Two" --frames 64 --seconds 300`, y anotar el resultado en `docs/TIMECODE.md` §4.1. Necesita a alguien escuchando los 5 min (limpio o con cortes).
- [x] **B1.2** Medir round-trip real por loopback en TU hardware `CXFAudioCore`
      - Criterio: numero medido y anotado en docs/TIMECODE.md
      - Estado: herramienta escrita: `tools/measure_latency.py` (+ `tools/requirements.txt` con numpy/sounddevice). Reproduce un chirp corto por la salida y graba la entrada a la vez (`sd.playrec`), saca el desfase por correlacion cruzada via FFT (solo numpy), repite N veces e imprime min/mediana/media/max + jitter + veredicto frente a la puerta de 10 ms + linea lista para pegar en `docs/TIMECODE.md` §4.2. `--list`, `--device`, `--fs`, `--frames`, `--reps`. **Gano `--out-ch`/`--in-ch`** (2026-09-04): sin esto cogia el canal 1 de cada lado a ciegas, que en la Rane 72 (14 in/10 out) no es el que lleva loopback.
      - **Resuelto (2026-09-04, ADR-074):** la Rane 72 no tiene un jack de Master Out por USB; el retorno USB interno (Deck1→Mix, Deck2→Mix, Deck2→Deck2) daba **23.3-23.5 ms** consistentes, pero eso mide ida-y-vuelta por DOS tramos USB, no el camino real de xFlare. El autor confirmó que en uso real **todo el audio va por USB, sin cable en ningun punto** (como Serato): una pierna de entrada (vinilo→mesa→USB in) y una de salida independiente (app→USB out→mesa→altavoz), que nunca vuelve a entrar al ordenador. Se descarta medir con cable fisico (ya no aplica) y se adopta la **suma de latencias declaradas por CoreAudio** (`AudioDeviceLatency`, F.48/F.63) como el numero oficial: **in 10,00 ms + out 4,35 ms = 14,35 ms** a 64 frames en el MacBook 2015. Detalle en `docs/TIMECODE.md` §4.2.
- [x] **B1.3** Decision documentada
      - Criterio: si ≤10 ms: seguir. Si no: ADR con el plan B (buffer mayor, otra interfaz, o revisar el objetivo) ANTES de escribir nada mas
      - **Hecho (2026-09-04, ADR-074):** con 14,35 ms (declarados, in+out) en el MacBook 2015 a 64 frames, dentro de la puerta de ≤15 ms del Intel 2015 (ADR-024) aunque por encima del objetivo de 10 ms de la maquina de referencia — **decision: seguir**, sin plan B. Falta repetir en la maquina de referencia (B1.5) cuando haya una segunda Mac.
- [x] **B1.4** Validar la captura del crossfader — resultado: **MIDI, no tono piloto** (corrige ADR-021) `CXFAudioCore` `XFCapture`
      - Criterio original: detectar apertura/cierre del crossfader de tu mesa con menos de 5 ms de jitter; si falla, ADR con el plan C ANTES de seguir
      - Estado: spike de tono piloto escrito en `spike/b1-pilot-fader/` (desechable), sigue compilando, queda como fallback si algún día hace falta.
      - **Hecho (2026-09-03):** antes de correr el spike de piloto se comprobó por CoreMIDI si el crossfader manda algo directamente (pregunta del autor: "¿miramos si el crossfader emite MIDI?"). Captura aislada de 5 min moviendo *solo* el crossfader, confirmada en vivo por el autor: **15313 de 15317 mensajes fueron CC8/canal16**, sostenidos exactamente con el movimiento (los 4 restantes, un roce accidental al fader de canal). El MAG FOUR **sí** manda su posición por MIDI — la premisa de ADR-021 era incorrecta para la Rane 72. **ADR-021 corregida y `profiles/rane-seventy-two.conf` actualizado a `method = midi` (cc=8, canal=16)** como método primario; `audio_return` queda documentado como respaldo. La infraestructura para consumirlo (`MidiCrossfaderConfig`/`MidiFaderSource`/`MidiFaderConnector`, `XFCapture`) ya existía y está SEALED. Pendiente (no bloquea B1.4, se resuelve en el asistente de calibración): extremos exactos del barrido y `midi.invert`. El spike de tono piloto ya no hace falta correrlo con la Rane 72 salvo como respaldo.
- [~] **B1.5** Medir la latencia en LAS DOS maquinas y rellenar la tabla `CXFAudioCore`
      - Criterio: PLATFORM_SUPPORT.md seccion 7 con numeros reales, no estimaciones
      - Estado (2026-09-04, ADR-074): metodo = suma de latencias declaradas por CoreAudio, no `measure_latency.py` (ver B1.2). MacBook Pro 2015 **hecho**: 14,35 ms a 64 frames (`PLATFORM_SUPPORT.md` §7). Falta: la fila a 128 frames y la maquina de referencia (bloqueada — no hay segunda Mac todavia).
- [~] **B1.6** Buffer adaptativo 64 -> 128 frames al detectar overloads (ADR-024) `CXFAudioCore`
      - Criterio: el Intel de 2015 aguanta 5 min sin cortes
      - Estado: logica escrita en el spike B1.1: flag `--adaptive`. Cuando se acumulan ≥3 overloads, el hilo main (no el RT) para la unit, sube el buffer del dispositivo a 128, reinicia contadores y arranca de nuevo; lo registra y el resumen distingue "PASS" de "PASS CON RESERVA" (solo aguanta a 128). **Falta la corrida real de 5 min en el Intel de 2015.**
- [x] **B1.7** Verificar driver de audio de la mesa en Monterey
      - Criterio: la Rane 72 (MK1) enumera sus canales USB en Monterey
      - **Hecho (2026-09-04):** `spike/b1-latency/passthrough --list` con la
        Rane 72 conectada por USB:
        ```
        Rane Seventy-Two Audio   14 in  10 out  48000 Hz  buf 512
        ```
        **Dúplex confirmado** (in>0 y out>0) y ya a **48 000 Hz** — no hace
        falta tocar Audio MIDI Setup (paso 1 del runbook). Driver de Monterey
        OK. Siguiente: Paso 2 de `docs/HW_BRINGUP.md` (B1.1/B1.6 — passthrough
        5 min a 64 frames), que necesita a alguien escuchando.


---

# SIGUIENTE

## B2 — XFClock

*El reloj musical. Puro, pequeno, se sella rapido.*

- [x] **B2.1** Conversiones tick / ms / hostTime con PPQ 480 `XFClock`
      - Criterio: tests de ida y vuelta sin perdida en 10.000 valores
      - Hecho: `Tempo` (tick↔ms↔s) y `ClockMap` (tick↔hostTime, ancla + tempo). Ida y vuelta exacta verificada con 10.000 valores × 6 tempos (ms) y 10.000 × 4 tempos × 2 timebases Intel/Apple Silicon (hostTime). Contrato de redondeo en ADR-031.
- [x] **B2.2** Transporte: play, stop, loop, cuenta atras de N compases `XFClock`
      - Criterio: tests de estado y de limites
      - Hecho: `Transport` (struct valor, sin hilo: lo avanza el driver de audio con `advance(by:)`). Estados stopped/countIn/playing, cuenta atras como position negativa que sube a 0, loop con envoltura por `%` (varias vueltas por bloque). 16 tests de estado y limites (overshoot de la cuenta atras, loop con inicio desplazado, advance en stopped, etc.).
- [x] **B2.3** ClockMap: mapear una captura a ticks `XFClock`
      - Criterio: test con desfase y con tempo distinto
      - Hecho: `ClockMap` con ancla `(hostTime ↔ tick)` + `Tempo` + `HostClock`. Tests con desfase de ancla, con tempo distinto (doble tempo → doble ticks), saturacion a 0 hacia atras del origen, y las dos timebases.
- [x] **B2.4** **SELLAR XFClock** `XFClock`
      - Criterio: cumple las 5 condiciones de ARCHITECTURE.md seccion 6
      - Hecho: `make seal M=XFClock` en verde. `Sources/XFClock/README.md` con API publica + ejemplo. Todo lo no-publico es `private`. `docs/MODULE_STATUS.md` → SEALED 2026-08-31, 34 tests. ADR-031 registrada. `apiVersion = 1`.

## B3 — XFNotation

*El modelo XFN en Swift, validado contra la referencia Python.*

- [x] **B3.1** Modelos Codable: Scratch, Exercise, Level, primitivas `XFNotation`
      - Criterio: decodifican data/*.json sin perdida; validan contra data/schema/*.json
      - Hecho: `HandPattern`, `FaderPattern` (con decode manual de las reglas `[frac, state]`), `PrimitiveSet`, `CatalogEntry`, `Scratch`, `RecordPhase`, `FaderEvent`, `ScratchLibrary`. Decodifican `data/primitives/*.json`, `tools/catalog.json` y `data/scratches/library-v0.1.json`. Tests: 5.
- [x] **B3.2** Portar el compositor mano x fader de xfn_core.py a Swift `XFNotation`
      - Hecho: `Composer.compose(...)` porta `compose()` literal (round medio-a-par, orden estable del fader, dedup de estados, cierre del bucle). `Division.unitTicks` porta `div_to_ticks`.
- [x] **B3.3** Golden: la libreria compilada en Swift es identica a library-v0.1.json `XFNotation`
      - Criterio: diff vacio byte a byte sobre los 25 scratches
      - Hecho: `GoldenLibraryTests` compone la libreria con `ScratchLibrary.build` y la compara con `library-v0.1.json` **campo a campo** (enteros/enums exactos, dobles con `round4`+tol 1e-9). El "byte a byte" de este criterio choca con **ADR-028** (prohibe byte-a-byte de floats); se resuelve en **ADR-032**. Los 25 scratches coinciden.
- [x] **B3.4** Fases con tramo parcial de curva (u0/u1) y funcion de recorte `XFNotation`
      - Criterio: recortar por mitad de un movimiento conserva la curva exacta, no la aproxima con rectas
      - Hecho: `RecordPhase` lleva `u0/u1/pFrom/pTo`; `Scratch.cropped(from:to:)` porta `crop()`; `PositionSampler.position` usa el tramo parcial. Test: la posicion del scratch recortado coincide con la del entero en todo el solape.
- [x] **B3.5** Transformaciones de variante: offset, amplitude, mirror, subdivision, swing `XFNotation`
      - Criterio: golden contra las variantes generadas por tools/xfn_core.py
      - Hecho: `offset`, `amplitude`, `mirror`, `swing` portadas con golden contra `xfn_core.py`. **`subdivision`** añadida (`Composer.composeWithSubdivision`: recompone con otra `division` ajustando ciclos para conservar la longitud musical → el 2C Flare pasa de 4 ciclos a 8, misma longitud, doble de clicks). **`dropout`** queda fuera de XFNotation: no transforma el patron (decide que compases puntuan) → es `XFEngine`. Decision del autor 2026-09-01 (ADR-032).
- [x] **B3.6** Calculo de eventos evaluables y maxScore por variante `XFNotation`
      - Criterio: 2-Click Flare base = 3.600; su div16 = 4.800
      - Hecho: criterio unificado con `docs/SCORING.md` (decision del autor 2026-09-01): `pitch` = uno por **semicorchea** (`ppq/4`). 2C Flare base = 16+16+4 = 36 = **3600** ✓. `subdivision(1/16)` = 32+16+8 = 56 = **5600** (la formula es uniforme; SCORING.md y `scoring.json` actualizados — el "4800" era incoherente con su propia formula). ADR-032.
- [x] **B3.7** **SELLAR XFNotation** `XFNotation`
      - Hecho: `make seal M=XFNotation` en verde. `Sources/XFNotation/README.md` con API + ejemplo. Todo lo no-publico es `private`/`internal`. `docs/MODULE_STATUS.md` → SEALED 2026-09-01, 20 tests. `apiVersion = 1`. ADR-032.

## B4 — CXFAudioCore

*El motor de audio en serio, esta vez para quedarse.*

- [x] **B4.1** Ring buffer SPSC lock-free en C `CXFAudioCore`
      - Criterio: tests al 100%, incluido productor/consumidor concurrente
      - Hecho: `xf_ring` (`include/xf_ring.h` + `xf_ring.c`). Un productor / un consumidor, buffer aportado por el llamante (sin malloc), capacidad potencia de 2. `head`/`tail` contadores de 64 bits que solo suben; atomicidad con builtins `__atomic_*` de Clang (RELEASE/ACQUIRE) — **sin `<stdatomic.h>`** en el header (no es module-safe; rompia `import CXFAudioCore`). Se añadio `include/module.modulemap` explicito. 6 tests: orden, no-pisado, vuelta al final del buffer, reset, y estres 1 MiB por un ring de 1 KiB con productor en otro hilo y verificacion byte a byte.
- [ ] **B4.2** Callback CoreAudio RT-safe, 64 frames, con thread_policy_set Y workgroup de audio `CXFAudioCore`
      - Criterio: 0 malloc/locks verificado con Instruments; el hilo se une al workgroup del dispositivo (obligatorio en Apple Silicon)
      - Bloqueado: necesita hardware + Instruments (Audio System Trace). El spike `spike/b1-latency/passthrough.c` ya tiene la plumberia CoreAudio a 64 frames; B4.2 es la version definitiva con ring buffer y prioridad RT. El spike `spike/b4-audio-sandbox/` valida ademas el reparto Swift (UI) + C (callback) + atomicas en la maquina de referencia (Monterey Intel), 2026-09-01: suena y responde en tiempo real.
- [x] **B4.3** Reproductor de sample con resampling por velocidad y direccion `CXFAudioCore`
      - Criterio: scratch audible sin clicks ni aliasing
      - Hecho (2026-09-01): `xf_player` (C, opaco). Cabezal fraccionario sobre un sample mono, leido con **sinc enventanado** (32 taps, Blackman-Harris, 512 fases) cuyo corte baja al subir la velocidad -> antialiasing de verdad. Tabla precalculada en `create` (NO RT-SAFE); `render` no reserva nada (regla §7). Suavizado de velocidad (`glide_ms`, 5 ms por defecto) contra clicks; el cabezal se satura a los extremos. Solo resamplea: corte de fader / metronomo / mezcla van aguas abajo (B4.2/B4.4). 12 tests que **miden** el espectro (Goertzel): v=1 transparente < 0,5 dB, v=2 duplica el pitch, **20 kHz a 2x -> salida casi en silencio en vez de plegarse a 8 kHz**, reverso, parada, ganancia DC 1, sin discontinuidad entre bloques. La confirmacion a oido queda para el hardware.
- [x] **B4.4** Metronomo mezclado en la salida principal (ADR-007) `CXFAudioCore`
      - Hecho (2026-09-01): `xf_metronome` (C, opaco). No lleva el tiempo: `xf_metronome_render(out, nframes, tick_at_start, bpm)` **suma** la claqueta a `out` (mono), disparando un click al cruzar cada negra; el primer tiempo del compas va acentuado (1600 Hz vs 1000 Hz). Click = seno con ataque de 1,5 ms y caida exponencial (~60 ms), sin reservas (regla §7). Con ticks negativos suena tambien -> sale gratis la claqueta de la cuenta atras. `set_enabled` es el unico control (atomico); al reactivar no suelta rafaga (deja morir el click en curso, no acumula). `resync(tick)` para arranque/salto sin re-disparar el tiempo en curso; un salto que cambia el numero de tiempo (loop hacia atras) si dispara. 10 tests: 1 click/negra y espaciado, acento del 1er tiempo (Goertzel 1600 vs 1000), silencio si desactivado, mezcla que SUMA (no pisa el preset), cuenta atras, etc. La integracion en el callback es B4.2.
- [ ] **B4.5** **PUERTA DE CALIDAD: ≤10 ms, 0 overloads en 5 min** `CXFAudioCore`
      - Criterio: medido y documentado en docs/TIMECODE.md
      - Bloqueado: medicion en hardware (misma que B1.5).
- [ ] **B4.6** **SELLAR CXFAudioCore** `CXFAudioCore`
      - Bloqueado por B4.2-B4.5.

## B5 — CXFTimecode

*Leer el vinilo.*

- [x] **B5.1** Vendorizar xwax INTACTO en vendor/xwax con sus cabeceras `CXFTimecode`
      - Criterio: compila sin modificar timecoder.c ni lut.c
      - Hecho: xwax **1.10** (GPL-3.0, ADR-030) en `Sources/CXFTimecode/vendor/xwax/`: `timecoder.{c,h}`, `lut.{c,h}`, `debug.h`, `pitch.h`, intactos. `Package.swift` añade `vendor/xwax` al headerSearchPath. SwiftPM compila `timecoder.c` y `lut.c` sin tocarlos, en x86_64 y arm64. Ver `docs/TIMECODE.md`.
- [x] **B5.2** Wrapper xf_timecode en modo relativo (ADR-005) `CXFTimecode`
      - Hecho: `xf_timecoder` opaco sobre `struct timecoder` de xwax. `create(def_name, sample_rate)` / `submit(pcm16 estereo)` / `velocity()` (con signo, del filtro alfa-beta `pitch_current` — no hace falta enganchar el bitstream) / `position()` (relativa, integral) / `confidence()` / `forwards()`. Header público SIN `timecoder.h` (module-safe, como `xf_ring.h`). Test: la velocidad sigue la portadora (1000 Hz → ~1.0×, 1500 → ~1.5×).
- [x] **B5.3** Hamster / reverse desde el dia 1 `CXFTimecode`
      - Criterio: test con senal invertida
      - Hecho: señal de cuadratura invertida → dirección opuesta (velocidad de signo contrario, `forwards` flip). `set_reversed(true)` intercambia los canales antes de decodificar → invierte el signo. 2 tests.
- [x] **B5.4** Confianza de senal y recuperacion de dropout `CXFTimecode`
      - Criterio: no se cuelga al levantar la aguja
      - Hecho: con señal, `confidence()` > 0,5; con silencio, cae < 0,2 y la velocidad decae hacia 0 — **sin colgarse**. Ruido blanco no engancha ni dispara la velocidad. `submit` con 0 frames no revienta. `confidence` = RMS de entrada recortado, o 1.0 si xwax engancha el bitstream.
- [x] **B5.5** **SELLAR CXFTimecode** `CXFTimecode`
      - Criterio original: pasar un vinilo de timecode real y comprobar enganche, escala de velocidad y dropout con la aguja de verdad.
      - **Hecho (2026-09-04):** `spike/b5-timecode/tcprobe --def serato_2a` con la Rane 72 + vinilo Serato CV02 real. El canal que asumía el perfil (`timecode.deck1.ch = 3,4`) no enganchaba, ni ningún otro de los 7 pares posibles — se probaron todos. El medidor de la propia mesa sí se movía con el plato, así que la señal llegaba a la Rane pero no dábamos con el canal USB. Se resolvió consultando los **nombres de canal que la propia Rane 72 reporta por CoreAudio** (`kAudioObjectPropertyElementName`): `1-2 Analog 1` `3-4 Analog 2` `5-6 Mix` `7-8 Deck 1` `9-10 Deck 2` `11-12 Session In` `13-14 Mic`. Contraintuitivo: el canal literalmente etiquetado **"Deck 1" (7-8) no llevaba la señal real** (solo un pico aislado de confianza); la señal real estaba en **"Analog 1" (1-2)**, confirmado también de forma independiente en Ableton Live. Con el canal correcto: 60s a 33⅓ estable → `vel` media 0.9999 (min 0.9967, max 1.0033), `conf` sostenida 0.92-1.00, engancho bitstream SI. Scratch: `vel` cambia de signo y `dir` pasa a REV en sincronía, sin perder confianza. Dropout: al levantar la aguja, `conf` decae suavemente 1.00→0.00 en ~1,5s y `vel`→0, `position` se congela sin corromperse ni colgar. `drops` = 0, `render_err` = 0 en las tres corridas. `profiles/rane-seventy-two.conf` corregido (`timecode.deck1.ch = 1,2`; `deck2.ch`/`return.ch` quedan como hipótesis por el mismo patrón, sin verificar). `spike/b5-timecode/tcprobe` ganó `--ch N` para elegir el par de canales sin recompilar (útil para cualquier mesa futura). Detalle completo en `docs/TIMECODE.md` §3. `make seal M=CXFTimecode` hecho, README actualizado, `MODULE_STATUS.md` → SEALED.

## B5b — XFProfiles

*Perfiles .conf por modelo de mesa. Puro parseo, se sella rapido.*

- [x] **B5b.1** Parser INI propio, sin dependencias (ADR-019) `XFProfiles`
      - Criterio: carga los 6 perfiles de profiles/ sin perdida
      - Hecho: `INIDocument(text:)` — secciones, claves con punto, comentarios `#`/`;`, claves sensibles a mayusculas, delimitador `=` o `:`, conserva orden. Los 6 ficheros parsean.
- [x] **B5b.2** Resolucion de extends con deteccion de herencia circular `XFProfiles`
      - Criterio: pioneer-djm-s9 resuelve heredando de la s11; un ciclo da error claro
      - Hecho: `ProfileResolver.resolve(id:in:)` porta `resolve()`. djm-s9 hereda method/canales/quirks de la s11. Ciclo -> `circularInheritance(chain:)`; ancestro inexistente -> `unknownAncestor`.
- [x] **B5b.3** Validacion equivalente a tools/xf_profile.py `XFProfiles`
      - Criterio: mismos errores que el validador Python sobre los mismos ficheros
      - Hecho: `ProfileValidator.validate(...)` porta `check()`: claves obligatorias, booleanos, `method` valido + claves segun metodo, cut_in en 0..1 y left<right, id en minusculas, aviso SIN VERIFICAR. Los 6 perfiles dan el mismo resultado que `xf_profile.py --all` (todos OK, aviso en los no verificados).
- [x] **B5b.4** Autodeteccion por nombre de puerto MIDI y dispositivo de audio `XFProfiles`
      - Criterio: comodines * funcionan; si hay empate, no elige, pregunta
      - Hecho: `GlobMatch` (solo `*`, sin distinguir caso) + `ProfileStore.autodetect(...)` -> `.unique` / `.ambiguous` / `.none`. En empate devuelve `.ambiguous`, no elige.
- [x] **B5b.5** Carga desde el bundle y desde la carpeta del usuario, con precedencia `XFProfiles`
      - Criterio: segun DEVICE_PROFILES.md seccion 5
      - Hecho: `ProfileStore(bundled:user:)` — el usuario pisa al bundle por id; cada `Entry` sabe su origen. Resuelve `extends` y tipa en una 2a pasada.
- [x] **B5b.6** **SELLAR XFProfiles** `XFProfiles`
      - Hecho: `make seal M=XFProfiles` en verde. `Sources/XFProfiles/README.md` con API + ejemplo. Todo lo no-publico es `private`. `docs/MODULE_STATUS.md` -> SEALED 2026-08-31, 24 tests. `apiVersion = 1`.


---

# DESPUES

## B6 — XFCapture

*Abstraer la entrada. Aqui se desbloquea el desarrollo sin mesa.*

> **Módulo nuevo `XFPrimitives` (capa 0, ADR-033):** `MotionSample` / `FaderSample`
> movidos aquí para que `XFAnalysis` los consuma sin importar `XFCapture`.
> **SEALED 2026-09-01**, 4 tests.

- [x] **B6.1** Protocolos MotionSource y FaderSource `XFCapture`
      - Hecho: `MotionSource` / `FaderSource` (`AnyObject`, `start()/stop()/latest()`, `isConnected`), importan `XFPrimitives`. Test con una fuente falsa conformando el protocolo.
- [x] **B6.2** KeyboardMotionSource y KeyboardFaderSource (modo sin mesa) `XFCapture`
      - Criterio: se puede hacer un baby scratch con el teclado
      - Hecho: `KeyboardMotionSource` — física sencilla (flecha pulsada → velocidad tiende a ±speed con `accel`; al soltar → tiende a 0; ambas se cancelan), la posición integra la velocidad, avanza con `advance(toHostTime:)` (reloj de audio, determinista). `KeyboardFaderSource` — momentáneo (tecla pulsada = cortado, suelta = abierto). 8 tests incl. una **ida-y-vuelta de baby scratch** que vuelve al origen. La verificación interactiva final va con la UI del modo sin mesa (B11).
- [x] **B6.3** TimecodeMotionSource sobre CXFTimecode `XFCapture`
      - Hecho (2026-09-01): `TimecodeMotionSource` — envuelve un `xf_timecoder` (B5.2) y lo alimenta **fuera del hilo de audio** (CLAUDE.md §7: el callback C mete el PCM en el ring, un consumidor normal lo drena y llama a `submit(pcm:frames:hostTime:)`). Sella cada muestra con el `hostTime` del bloque que la capturó (dominio CoreAudio), como `Keyboard`/`Replay*Source`. `Config` con `format` de xwax, `sampleRate` y `hamster` (ADR-008); `start()` lanza `StartError.decoderCreationFailed` si xwax no crea el decoder; `resetPosition()` para alinear disco y autopista al empezar. Validado con **señal de cuadratura sintética** (mismo enfoque que B5.2–B5.4); el vinilo real sigue siendo el gate de B5.5. 9 tests.
- [x] **B6.4** MidiFaderSource (CoreMIDI) + fallback por envolvente de audio `XFCapture`
      - Criterio: funciona con Rane 72 (MK1); si no emite MIDI, cae al fallback solo
      - Hecho (2026-09-01): parte testeable + conectores.
        · `MidiCrossfaderConfig` (canal/CC/min/max/invert desde `DeviceProfile.crossfader`) + `MidiFaderSource` (`ingest(status:data1:data2:hostTime:)`, filtra por CC y canal, normaliza, binariza; `messages(from:)` trocea el flujo respetando running status, SysEx y bytes de tiempo real — lo usa el conector).
        · `AudioEnvelopeFaderSource`: fallback de ultimo recurso (RMS del retorno -> `FaderBinarizer`, sin tono piloto), `calibrate(openLevel:)`.
        · `MidiFaderConnector` (CoreMIDI clasico: `MIDIClientCreate` + `MIDIInputPortCreateWithBlock`, anda el `MIDIPacketList`) y `HIDFaderConnector` (`IOHIDManager`: matching por vendor/product, `IOHIDDeviceRegisterInputReportCallback`). **Sin tests: necesitan el dispositivo real**; la decodificacion si esta probada.
        22 tests (12 MIDI + 5 envolvente + los HID de antes). `docs/DEVICE_PROFILES.md` §3 documenta las claves `hid.*`; los perfiles rane-72 y djm-s11 llevan el bloque HID comentado.
      - **(2026-09-03)** Confirmado con la Rane 72 real: el crossfader SÍ manda CC8/canal16 (ver B1.4, corrige ADR-021). `profiles/rane-seventy-two.conf` ya declara `method = midi`. Falta la corrida con `MidiFaderConnector` real (hoy solo probado con `ingest(bytes:)` sintético) para B6.7.
- [x] **B6.4b** AudioReturnFaderSource: tono piloto y deteccion (ADR-021) `XFCapture`
      - Criterio: funciona con el perfil rane-seventy-two
      - Hecho (2026-09-01): `AudioReturnFaderSource` conforma `FaderSource`. `submit(pcm:frames:hostTime:)` (PCM estereo del retorno del master, se drena del ring buffer como `TimecodeMotionSource`) corre un **Goertzel** de un bin (19,5 kHz, hop de 64 muestras, bin entero: 26), normaliza contra el nivel de piloto con el fader abierto (auto-max con fuga lenta + `calibrate(openLevel:)`), y pasa el valor continuo al `FaderBinarizer` de B6.5 (cut-in + histeresis, ADR-017) que resuelve `isOpen`. Devuelve los flancos por hop. Guarda muestras sueltas entre submits; `pilotLevel` para un medidor. 9 tests con **piloto sintetico** modulado en amplitud (como `--selfcheck` del spike): detecta apertura/cierre, 0 eventos fantasma en 1 s de fader quieto con ruido, hamster, calibracion, hostTime por hop. Falta la corrida con la Rane 72.
- [x] **B6.5** Binarizacion del fader con cut-in calibrado e histeresis (ADR-017) `XFCapture`
      - Criterio: 0 eventos fantasma en 1 min de fader quieto
      - Hecho: `FaderBinarizer` — disparador de Schmitt alrededor de `cutIn` con banda `hysteresis`; flag `hamster` para reverse (ADR-008). `binarize([(hostTime,value)]) -> [FaderSample]`, conserva estado entre llamadas. Test: 60.000 lecturas con ruido ±0,03 y banda 0,08 → **0 transiciones**.
- [x] **B6.6** Formato .xfsession: grabar y reproducir + ReplaySource `XFCapture`
      - Criterio: una sesion grabada se reproduce bit a bit igual
      - Hecho: `XFSession` (JSON Lines: cabecera de calibración + muestras). Los floats se guardan como **cadena** (`"\(x)"`) para ida y vuelta exacta — el `JSONEncoder` de esta toolchain no re-parsea el mismo bit en un `Double` (problema de ADR-028). `ReplayMotionSource` / `ReplayFaderSource` conforman los protocolos y avanzan con `seek(toHostTime:)` (reloj de audio, determinista). Ida y vuelta value-equal + re-encode estable. `clockMap` reconstruye el `ClockMap` de la toma. 15 tests.
- [x] **B6.7** **SELLAR XFCapture** `XFCapture`
      - Bloqueaba B6.3 (timecode) — cerrado con vinilo real en B5.5 — y B6.4/B6.4b
        (conectores CoreMIDI/IOHIDManager/audio). Al revisar el bloqueador real
        (2026-09-05): el crossfader por MIDI **ya está confirmado con la Rane 72
        real** (ADR-021 corregida, F.61) — pero no a través de `MidiFaderConnector`
        (el conector dedicado que se planeó al principio), sino de
        `MidiMonitorConnector` (genérico, un cliente CoreMIDI para toda la sesión),
        que reparte a `MidiFaderSource` Y a `MidiCommandSource` a la vez. Comprobado
        que `MidiFaderConnector` **nunca se instanciaba en la app** (`grep` sin
        resultados fuera de su propio fichero) — quedó como código muerto de antes
        de F.61, con comentarios en `MidiFaderSource`/`PracticeCommandMidi` que
        seguían apuntando a él. Se borra `MidiFaderConnector.swift` y se corrigen
        los comentarios (apuntan a `MidiMonitorConnector`, el que de verdad corre).
        `audio_return` (`AudioReturnFaderSource`) y HID (`HIDFaderConnector`) quedan
        como **respaldos documentados sin confirmar con hardware real** (ADR-021):
        no bloquean sellar el método primario, que sí está validado extremo a
        extremo.
      - **Hecho (2026-09-05):** `Sources/XFCapture/README.md` nuevo,
        `docs/MODULE_STATUS.md` → SEALED. `make seal M=XFCapture`: 90 tests,
        verde. Sellado con las mismas condiciones que otros módulos (CXFTimecode,
        XFPersistence…): el método/camino primario validado con hardware real,
        los respaldos documentados como pendientes sin bloquear.

## B7 — XFDesign + XFRender

*Que se vea, y que se vea bien.*

- [x] **B7.1** Tokens de diseno de UI_DESIGN.md seccion 2 `XFDesign`
      - Hecho: `XFColor` (paleta de §2, `Color(hex:)`), `XFSpacing` (4/8/12/16/24/32/48), `XFRadius` (10/16/24), `XFStroke`, `XFFont` (title/body/mono — `design: .monospaced` para cifras a ancho fijo, sin `monospacedDigit()` que es macOS 12), `HitLevel` (escala de acierto: color **+ forma** por daltonismo, `init(absOffsetMs:)` con las ventanas de SCORING.md).
- [x] **B7.2** Componentes base: tarjeta, boton, stepper de BPM, badge de acierto `XFDesign`
      - Hecho: `XFCard` (superficie + radio 16 + borde 1px, `raised` para modales), `XFButtonStyle` (.filled/.bordered, radio 10, easeOut 180 ms), `BPMStepper` (`‹ 80 BPM ›`, número monoespaciado, respeta `range`), `HitBadge` + `HitShape` (dibuja círculo lleno/círculo/rombo/triángulo/cruz según el nivel). 7 tests: valores de token, clasificación de `HitLevel`, formas distintas, los componentes se construyen. macOS 11.
- [x] **B7.2b** Render sincronizado al refresco real, 60 fps garantizados en Intel (ADR-024) `XFRender`
      - Criterio: 60 fps estables en el MacBook Pro 2015 con la autopista completa
      - Hecho (2026-09-03): **medido en el propio MBP 2015 Intel**: la práctica
        completa (autopista + fantasma + traza + rejilla + tira de instrumental +
        rail del sample, todo en `PracticeScene`) va a **60 fps · peor 17,8 ms ·
        0 saltos de vsync / 120** en régimen estable. El único pico es el arranque
        (decodificar audio + rasterizar las ondas), ~59 fps un par de segundos.
      - `FrameRateMeter` (XFApp, puro, 6 tests): media de fps, peor fotograma y
        "saltos de vsync" = fotogramas > 1,5 periodos (a 60 → > 25 ms; el jitter
        de borde no cuenta). Overlay en la esquina de la autopista con el ajuste
        **"Mostrar FPS"** (`AppSettings.showFPS`, rojo si baja del objetivo −5).
      - `ScreenRefresh.fps(for:)` lee el refresco real del panel (modo del display
        + `CVDisplayLink`) y `PracticeSceneView` fija `preferredFramesPerSecond`
        a 60 / 120 según el hardware, en vez del 120 fijo anterior (ADR-024).
      - Sin tocar XFRender (sellado): `HighwayLayout` sigue siendo la geometría;
        todo esto vive en `PracticeScene`/`PracticeSceneView` (XFApp).
- [x] **B7.3** Escena SpriteKit de la autopista, sincronizada al reloj de AUDIO `XFRender`
      - Criterio: sin deriva tras 10 min; 120 fps en ProMotion
      - Hecho (2026-09-01): `HighwayLayout` — geometria **pura** (sin SpriteKit, testeable): dado un `Scratch` + el tick de AUDIO actual + `HighwayGeometry`, produce `HighwayFrame` (polilinea de la curva del disco, marcas ○/● de fader sobre la curva, tramos del carril de fader, X de la cabeza de lectura al 30%). El patron hace loop con el modulo. `HighwayScene` (SKScene delgada, reutiliza nodos, 0 reservas por fotograma) y `HighwayView` (`NSViewRepresentable` sobre `SKView`) leen el tick en `update(_:)`, que SpriteKit llama al **refresco real**: el QUE se dibuja sale del reloj de audio, no de un contador propio. 11 tests, foco anti-deriva: `frame(T) == frame(T+L)` bit a bit tras 300 loops, cada click cae en `playheadX + t·pxPerTick` exacto, fotograma determinista. **Pendiente en la maquina**: los 120 fps de ProMotion (necesita un Mac Apple Silicon, R8) y el conteo real de fotogramas; se comprueba con la app corriendo (relacionado con B7.2b).
- [x] **B7.4** Capa fantasma + capa usuario + tenido por tolerancia `XFRender`
      - Hecho (2026-09-01): `HighwayLayout.frame(...)` gana `userTrace: [TracePoint]` y `clickHits: [ClickHit]`. `TracePoint` (tick absoluto de sesion + posicion + `HitLevel?`) → la curva del usuario se dibuja en el **mismo eje** que el fantasma (misma `positionRange`) y se parte en `TintedPolyline` por nivel de acierto; `nil`/`.perfect` = acento, el resto se tiñe con `HitLevel.color` (`docs/UI_DESIGN.md` §3.3). Los tramos comparten el punto de corte (sin hueco). `ClickHit` (patternTick + offsetMs) → `TintedMark` sobre la curva del patron en la copia mas cercana a "ahora", clasificado con `HitLevel(absOffsetMs:)`. `XFRender` no juzga: `XFAnalysis` rellena los niveles. `HighwayScene`/`HighwayView` pintan las dos capas nuevas (nodos reutilizados). 8 tests. XFRender importa XFDesign (ya era dependencia).
- [x] **B7.5** Scope circular del plato (Lissajous) `XFRender`
      - Hecho (2026-09-01): `ScopeLayout` (puro) convierte lecturas del plato (`ScopeReading`: `position`/`velocity`/`confidence`) en `ScopeFigure`. Lissajous reconstruido: el angulo sale de la **fase acumulada** (`position * 2π`, las portadoras crudas viven en la capa RT), el radio del punto de la **confianza** — señal limpia → punto sobre la circunferencia; aguja sucia → se hunde al centro y `isDegraded`. El **rastro** (un punto por lectura, que aporta el llamante) dibuja el arco: sentido = direccion, separacion = velocidad. `ScopeScene`/`ScopeView` (SpriteKit/SwiftUI delgadas) pintan aro + linea radial + rastro + punto, en acento o rojo si degradado. 10 tests.
- [x] **B7.6** Golden tests de render en SVG `XFRender`
      - Criterio: los 25 scratches contra Fixtures/golden/
      - Hecho (2026-09-01): `HighwaySVG.document(frame:geometry:)` serializa un `HighwayFrame` a SVG **determinista** (coordenadas a 4 decimales, locale C, sin `-0` — politica ADR-028; eje Y volteado). `GoldenHighwayTests` dibuja los 25 scratches de la libreria (encuadre fijo, `atTick: 0`) y compara contra `Fixtures/golden/highway/<id>.svg`; con `XF_GOLDEN_UPDATE=1` (via `make golden-update`) los regenera. 25 goldens commiteados. + 4 tests de estructura/determinismo del serializador.
- [x] **B7.7** **SELLAR XFDesign y XFRender** `XFDesign,XFRender`
      - Iterado (2026-09-01, feedback): **crujidos = clipping** -> soft-clip en la salida del
        motor (transparente hasta 0,7, rodilla `tanh`), nunca recorte duro. **Medidor de
        nivel** a la derecha en la practica (`xf_engine_output_peak`, "CLIP" si pasa de 1,0).
        **Volumen por ejercicio**: sliders Sample/Instru en la practica ->
        `xf_engine_set_scratch_gain`/`_set_instrumental_gain`, persistidos en `AppSettings`.
        **Libreria plana** (sin agrupar por nivel). `make app` copia `data/`+`profiles/` a
        `Contents/Resources/` y firma ad-hoc (B12a).
      - Re-sellado (2026-09-01, **ADR-040**): la sombra de la autopista se parte donde
        el fader esta cerrado (mute = hueco, notacion TTM; el corte lo marcan los
        circulos). Aditivo: `HighwayFrame.discSegments` (con default), pintado en
        `HighwayScene`/`HighwaySVG`; 25 goldens regenerados. 4 tests nuevos, los 41
        anteriores intactos. XFRender: 45.
      - Re-sellado (2026-09-01, **ADR-038**): rejilla de negras/compas en la autopista.
        Aditivo (`HighwayGeometry.beatsPerBar`, `HighwayFrame.beatLines`/`barLines` con
        default; pintado en `HighwayScene`/`HighwaySVG`; 25 goldens regenerados). Los 34
        tests sellados intactos + 7 nuevos (`HighwayGridTests`, foco en la invariancia
        `frame(T)==frame(T+L)`). `apiVersion` sigue 1. XFRender: 41 verdes.
      - Hecho (2026-09-01): `make seal M=XFDesign` (7 tests) y `make seal M=XFRender` (34 tests) en verde. `Sources/XFRender/README.md` escrito; `Sources/XFDesign/README.md` actualizado a SEALED. `Package.swift` excluye el README de XFRender. `docs/MODULE_STATUS.md` → ambos SEALED 2026-09-01, `apiVersion = 1`. **ADR-036** (layout puro + escena delgada, sincronizacion al reloj de AUDIO, golden SVG, Lissajous reconstruido). **B7.2b cerrado (2026-09-03)** en XFApp (overlay `FrameRateMeter` + `ScreenRefresh`), sin tocar XFRender: 60 fps estables medidos en el MBP 2015.

## B8 — XFAnalysis

*El cerebro. Funciones puras, cero hardware.*

> **Prerequisito hecho:** módulo `XFPrimitives` (capa 0, ADR-033) con
> `MotionSample`/`FaderSample`, SEALED. `XFAnalysis` depende de él, no de `XFCapture`.

- [x] **B8.1** Emparejado de clicks objetivo/usuario y desfase con signo `XFAnalysis`
      - Hecho: `ClickMatcher` — cierres del patrón (en hostTime vía `ClockMap`) vs cierres del usuario (transiciones a `!isOpen`), emparejado al más cercano dentro de ±150 ms, `offsetMs` con signo (+ = tarde). `ClickOffset` por evento.
- [x] **B8.2** DTW de contorno de tono, afinacion relativa (ADR-005) `XFAnalysis`
      - Hecho: `DTW.normalizedDistance` (banda de Sakoe-Chiba). `PitchAnalyzer` toma la velocidad objetivo (derivada de la curva) y la del usuario en cada semicorchea, **normaliza cada contorno por su máximo** (relativo, no absoluto) y compara. `pitchDistance` en el Report + puntos locales por checkpoint.
- [x] **B8.3** Consistencia (sigma) y amplitud de recorrido `XFAnalysis`
      - Hecho: σ y sesgo = desviación típica y media de los `offsetMs`. `AmplitudeAnalyzer`: recorrido de cada trazo `fwd` normalizado al rango del propio usuario vs el del patrón (ADR-005).
- [x] **B8.4** Generador de diagnosticos en lenguaje natural (ADR-018) `XFAnalysis`
      - Criterio: distingue sesgo sistematico de dispersion y lo dice distinto
      - Hecho: `Diagnoser` — clicks perdidos, luego **sesgo** (`|media| ≥ 12 ms` y σ baja → "llegas X ms tarde, adelanta el click") vs **dispersión** (`σ ≥ 18 ms` → "es que no llegas siempre igual, metrónomo"), amplitud, contorno. Umbrales provisionales (se afinan con tomas reales). **Siempre ≥ 1 frase** (2026-09-03): una toma limpia de un patrón sin clicks (baby) daba lista vacía y la pantalla de resultados se quedaba muda; ahora sale un resumen sobrio de lo que sí está bien (ADR-018, sin confeti). `DiagnoserTests` con 6 casos directos.
- [~] **B8.5** Tests de replay: good / late / sloppy por patron de nivel 1-4 `XFAnalysis`
      - Criterio: segun docs/TESTING.md
      - Estado: **versión sintética completa** (`ReplayScoringTests` + `SyntheticTake` generan el `Take` desde el patrón). La batería good/late/sloppy corre ahora contra **un patrón representativo de cada nivel 1-4** (forward-cut L1, transformer-2 L2, flare-1c L3, flare-2c L4), no solo el flare: good → ≥0.85 y 3★, late(+35 ms) → sesgo (no dispersión), sloppy(±45 ms) → dispersión + peor puntuación con margen, clicks perdidos contados. Invariante fija: good ≫ sloppy en cada patrón. **+ `GoldenReplayScoringTests` (2026-09-03):** congela el `Report` numérico exacto de las 12 tomas en `Fixtures/golden/analysis/` (redondeo a 4 decimales + tolerancia 1e-9, ADR-028); `make golden-update` para regenerar. Un cambio del scorer que mueva una puntuación salta en el diff. **Falta** (bloquea el cierre y B8.8): `.xfsession` grabados **reales** con hardware — `<patrón>__good/late/sloppy` — y afinar los umbrales de B8.4 contra ellos; la tabla golden se regenera entonces contra las tomas reales.
- [x] **B8.6** Puntuacion por evento y total sobre maxScore `XFAnalysis`
      - Criterio: docs/SCORING.md seccion 1
      - Hecho: `DefaultScorer` suma clicks + pitch + amplitud; `maxScore` de `XFNotation.ScoreEvents`; `accuracy = score/maxScore`. Tablas en `ScoringConstants` (copia del contrato de `scoring.json`).
- [x] **B8.7** Tres estrellas por criterios ortogonales (ADR-025) `XFAnalysis`
      - Criterio: un 88% con un fallo da 1 estrella, no 2
      - Hecho: `Stars` — ★ ≥70 % y al final · ★★ ≥85 % **y cero eventos a 0** · ★★★ ≥95 %, σ ≤ 15 ms y al BPM objetivo. `starReasons` dice qué falta. Test: 88 % + 1 evento a 0 → 1★.
- [ ] **B8.8** **SELLAR XFAnalysis** `XFAnalysis`
      - Bloqueado por B8.5 (tomas reales) y el afinado de umbrales de B8.4 contra ellas. El resto del módulo está hecho, 10 tests en verde.

## B9 — XFEngine

*La sesion de gimnasio.*

- [x] **B9.1** Maquina de estados: calentamiento, series, descanso, boss, resultados `XFEngine`
      - Hecho (2026-09-01): `SessionMachine` (struct valor, como `Transport`: sin hilo, avanza por eventos). Fases `SessionPhase` = `warmup → series(i) → rest(afterSeries:i) → … → boss → results` (`docs/CURRICULUM.md` §3); el descanso solo va entre series, la ultima entra directa al boss. Eventos `beginSeries()/completeSeries(passed:)/endRest()/completeBoss()/reset()`; llamados fuera de fase son no-op (como `Transport.advance` parado). `SessionConfig` (seriesCount 3, barsPerSeries 4). `isScored` (series+boss puntuan; warmup/rest/results no). `completeSeries` **registra** el resultado en `seriesOutcomes` pero no lo interpreta: la escalera de BPM es B9.2, el desbloqueo por compases seguidos B9.3. 8 tests.
- [x] **B9.2** Escalera de BPM adaptativa (2 fallos baja, 3 aciertos sube) `XFEngine`
      - Hecho (2026-09-01): `BPMLadder` (struct valor). `rungs` ascendentes (de `bpmLadder` de `data/curriculum/exercises.json`, p. ej. `[60,70,80,90,100]`) + `startBPM`. `record(passed:) -> Step` (`.hold`/`.up`/`.down`): 3 aprobados seguidos suben un escalon, 2 fallos seguidos bajan; un aprobado corta la racha de fallos y viceversa. Clamp en techo y suelo, y el contador se reinicia al disparar (no queda "armado"). Constantes `passesToStepUp=3`/`failsToStepDown=2` fijas por currículo. 11 tests. Sin cablear a `SessionMachine` todavia: el driver llamara a `ladder.record` junto a `machine.completeSeries`.
- [x] **B9.3** Desbloqueo por compases consecutivos, no por media `XFEngine`
      - Hecho (2026-09-01): `UnlockRule` (umbral `accuracy` 0..1 + `consecutiveBars` + `minBPM` opcional) cubre las dos formas de `data/curriculum/`: `pass` de ejercicio (sin BPM) y `unlock` de nivel (con BPM). `UnlockTracker` (struct valor): `record(barAccuracy:bpm:) -> Bool` cuenta compases buenos **seguidos**; un solo compas por debajo del umbral (o del `minBPM`) pone `currentStreak` a 0 — no se hace media (misma filosofia que ADR-025). `isUnlocked` se queda pegado al conseguir la racha; `bestStreak` recuerda lo mas cerca que se estuvo; `barsRemaining` para "te faltan N". `reset()` para nuevo intento. 10 tests. Sin cablear a `SessionMachine` (lo hara el driver/facade).
- [x] **B9.4** **SELLAR XFEngine** `XFEngine`
      - Hecho (2026-09-01): antes de sellar se añadio el facade **`Session`** (decision del autor + ADR-034): cablea `SessionMachine` + `BPMLadder` + `UnlockTracker` y es la unica puerta del modulo (`beginSeries`/`recordBar(accuracy:)`/`endRest`/`recordBoss(accuracy:)`/`reset`, con `summary` al final). **Una serie se aprueba si TODOS sus compases llegan al umbral** (streak, no media — ADR-034, coherente con ADR-025); el `minBPM` solo cuenta para el desbloqueo. `BPMLadder` gano un `reset()`. `make seal M=XFEngine` en verde, `Sources/XFEngine/README.md` con API + ejemplo, `docs/MODULE_STATUS.md` → SEALED 2026-09-01, 38 tests, `apiVersion = 1`. ADR-034 registrada.

## B10 — XFPersistence

*Que el progreso sobreviva a cerrar la app.*

- [x] **B10.1** Esquema GRDB y migraciones `XFPersistence`
      - Hecho (2026-09-01): `XFDatabase` (abre el SQLite con `DatabaseQueue`, `foreignKeysEnabled`, aplica el migrador; `inMemory()` para tests; `isUpToDate()`). `Schema.migrator` con la migracion **`v1`** que crea las 10 tablas del bloque B10: `practiceSession`, `attempt` (== `data/schema/attempt.schema.json`, con `countsForStars` por defecto true — ADR-027) + `attemptEvent` (`eventScores`, `ON DELETE CASCADE`), `exerciseProgress` (== `docs/SCORING.md` §3, PK compuesta), `variantUnlock`, `exerciseMastery` (dominado/oxidado), `reviewSchedule` (repeticion espaciada 1/3/7/21 via `stage`+`dueAt`), `deviceCalibration`, `practiceDay` (racha), `setting`. Regla: una migracion publicada no se toca; los cambios van en `v2`+. El codigo de consulta tipado es B10.2+. 10 tests (tablas, columnas de attempt, FK exigida, cascada, SET NULL, idempotencia). `GRDB` añadido al target de tests.
- [x] **B10.2** Historico de tomas, progreso y desbloqueos `XFPersistence`
      - Hecho (2026-09-01): records GRDB `PracticeSession`, `Attempt` (== `data/schema/attempt.schema.json`, `Mode` como enum), `AttemptEvent`, `VariantUnlock`. `XFDatabase+Attempts`: `saveSession`, `saveAttempt(_:events:)` (guarda intento + `eventScores` en una transaccion, reemplaza los eventos al reguardar), `attempt(id:)`, `events(ofAttempt:)`, `attempts(exerciseId:variantId:limit:)` y `attempts(exerciseId:limit:)` (histrico, del mas reciente al mas antiguo). `XFDatabase+Unlocks`: `markVariantUnlocked` (idempotente, no pisa la fecha), `isVariantUnlocked`, `unlockedVariants`. El progreso agregado es B10.7, la derivacion de dominado/desbloqueo es B10.8. 12 tests.
- [x] **B10.3** Repeticion espaciada (1, 3, 7, 21 dias) `XFPersistence`
      - Hecho (2026-09-01): record `ReviewItem` (`stage` 0..3 → `intervalDays [1,3,7,21]`, `dueAt`, `lastReviewedAt`). `XFDatabase.scheduleReview(...:masteredAt:)` programa el primer repaso a +1 dia (idempotente). `recordReviewOutcome(...:passed:at:)`: aprobar sube un escalon (tope 21 d), fallar vuelve al 0; crea la fila al vuelo si no existe. `dueReviews(asOf:)` devuelve lo vencido ordenado por `dueAt`. "Dia" = 86.400 s exactos (determinista, sin zona horaria). 6 tests.
- [x] **B10.4** Perfiles de calibracion por dispositivo `XFPersistence`
      - Hecho (2026-09-01): record `DeviceCalibration` (`deviceKey` = UID de audio o nombre de puerto MIDI; `profileId` de `XFProfiles`; `faderCutIn`, `faderHysteresis`, `hamster`, `latencyMs`, `updatedAt`). `XFDatabase.saveCalibration` (upsert por `deviceKey`), `calibration(deviceKey:)`, `allCalibrations()` (para "Mi mesa", por fecha desc), `deleteCalibration(deviceKey:)`. 5 tests.
- [x] **B10.6** Tabla de intentos con eventScores y ruta al .xfsession `XFPersistence`
      - Criterio: data/schema/attempt.schema.json
      - Hecho (2026-09-01): junto con B10.2. La tabla `attempt` cubre todas las `properties` del schema (test `testColumnasDeAttemptCoincidenConElSchema` en B10.1); `sessionFile` guarda la ruta al `.xfsession` crudo; `eventScores` son filas de `AttemptEvent` (tipo/`t`/`points`/`offsetMs`), guardadas y ledas con `saveAttempt(_:events:)` / `events(ofAttempt:)`, borrado en cascada. Round-trip verificado con todos los campos llenos y con los opcionales a `nil`, y con los 5 modos.
- [x] **B10.7** Progreso agregado: intentos, mejor, media de 5, mejor BPM con 3★, sesgo medio `XFPersistence`
      - Criterio: docs/SCORING.md seccion 3
      - Hecho (2026-09-01): record `ExerciseProgress` (fila derivada por (ejercicio, variante)) + `ProgressSummary` (progreso + media de 5 + linea de 20). `XFDatabase.recomputeProgress(exerciseId:variantId:)` recalcula desde `attempt`: intentos, mejor score + su fecha, ultima + su fecha, estrellas (MAX, no baja — SCORING.md §2), `bestBpmWith3Stars`, `meanBiasMs`, `totalPracticeMs`. Solo cuentan los intentos con `countsForStars = 1` (ADR-027), salvo el tiempo total que suma todo. `progress(...)` y `progressSummary(...)` (media de los ultimos 5 y linea de los ultimos 20, del mas antiguo al mas reciente). 6 tests.
- [x] **B10.8** Estado de dominado y desbloqueo de variantes `XFPersistence`
      - Criterio: 3★ base + 2★ en tres variantes
      - Hecho (2026-09-01): record `ExerciseMastery` (`masteredAt`/`oxidizedAt`). `XFDatabase.refreshMastery(exerciseId:baseVariantId:at:)` mira las estrellas de las filas de `exerciseProgress`: dominado = `masteryBaseStars`(3) en base **y** `masteryVariantCount`(3) variantes con >= `masteryVariantStars`(2). `masteredAt` se fija la primera vez y no se borra; `setOxidized(...)` para las recaidas en calentamiento (ADR-027 / WARMUP.md §5). `isMastered`, `mastery`, `masteredExercises` (pool del calentamiento). Desbloqueo: `evaluateUnlocks(exerciseId:rules:at:)` toma `[VariantUnlockRule]` (que el llamante construye desde `variants.json`) y marca las que ya cumplen; una pasada, sin cascada. 5 tests.
- [x] **B10.9** **SELLAR XFPersistence** `XFPersistence`
      - Hecho (2026-09-01): `make seal M=XFPersistence` en verde. `Sources/XFPersistence/README.md` con API + ejemplo. `Schema` pasa a `internal` (la app solo necesita `XFDatabase`). `docs/MODULE_STATUS.md` → SEALED 2026-09-01, 44 tests, `apiVersion = 1`. ADR-035 registrada (esquema completo en `v1`, `XFDatabase` como puerta unica, reglas de producto dentro y catalogo fuera, "dia" = 86.400 s). `GRDB` añadido al target de tests en B10.1.

## B11 — XFApp

*Las pantallas.*

- [x] **B11.1** Asistente de calibracion de 4 pasos `XFApp`
      - **(2026-09-04, ADR-073, feedback con la Rane 72 recién conectada)**:
        "no me deja asignar nada" — el paso 1 (Audio) no recibía NINGUNA lista
        de dispositivos (`inputDevices`/`outputDevices` por defecto `[]`) y el
        modelo se reconstruía inline en cada render de `AppRootView`, perdiendo
        la selección. Arreglado: `AudioDeviceList` (nuevo) enumera dispositivos
        reales; `@StateObject` para el modelo. Los pasos 2-4 aún sin motor de
        captura (B4.2): muestran un aviso con qué usar mientras tanto (los
        spikes / `tools/measure_latency.py`) en vez de un control mudo.
      - Criterio: un usuario nuevo llega a tocar sin ayuda externa
      - Hecho (2026-09-01): `CalibrationWizardModel` (`ObservableObject`, testeable) — 4 pasos `CalibrationStep` (audio / latencia / timecode / fader, `docs/UI_DESIGN.md` §3.1). **No mide nada**: la capa de audio le reporta (`reportLatency`/`reportTimecode`/`reportFaderCut`) y el modelo decide cuando cada paso esta listo. `LatencyVerdict` (semaforo ≤10 verde / ≤15 ambar / >15 rojo con consejo — ADR-024); la latencia rojo **avisa pero no bloquea**. `result()` → `DeviceCalibration` para `XFPersistence`. Vistas SwiftUI (`CalibrationWizardView` + 4 paneles, macOS 11; el de timecode embebe `ScopeView`) — verificacion visual pendiente para cuando corra la app. 10 tests.
- [x] **B11.2** Home: mapa de la matriz, racha, continuar `XFApp`
      - Hecho (2026-09-01): `MatrixCell` (celda de la rejilla: locked/available/practiced(stars)/mastered, derivada del estado de la variante base) + `HomeSummary` (celdas por nivel, racha, minutos de hoy, "Continuar", masteredCount, minimo diario) + `PracticeStreak` (racha de dias consecutivos, puro: si hoy no hay practica pero ayer si, sigue viva; anteayer -> 0). `HomeView` SwiftUI reemplaza la maqueta de `Sources/xFlare/HomeScaffoldView.swift` (borrada en el ensamblaje). Los datos los arma XFApp desde XFPersistence/XFNotation (glue pendiente; XFPersistence esta SEALED, no se toca). 11 tests.
      - Nota: ya existe una **maqueta inerte** en `Sources/xFlare/HomeScaffoldView.swift`
        (ejecutable `xFlare`, `make run`). Sirve de referencia visual; aquí se hace la de verdad en XFApp y se borra la maqueta.
      - Anadido (2026-09-01): **miniatura TTM** en la celda. `TTMThumbnail` (curva
        del disco + tramos de fader cerrado sacados de los eventos exactos,
        normalizado al cuadrado unidad) + `TTMThumbnailView`. `HomeAssembler` la
        pone **solo en los 2 primeros scratches del Nivel 1** (prueba visual; si
        convence se extiende). 5 tests.
- [x] **B11.3** Pantalla de practica (la autopista) `XFApp`
      - Hecho (2026-09-01): `PracticeHUD` (puro) arma las dos barras de UI_DESIGN 3.3 desde la `Session`: nombre, fase (Calentamiento/Serie i/N/Descanso/Boss/Resultados), BPM, `%` (solo si la fase puntua y no hay cuenta atras), ultimos 5 clicks como `HitLevel`, una sola frase de feedback. `PracticeView` SwiftUI: Scope + HighwayView + barra fina + barra de feedback, `onExit` (Esc). 6 tests.
      - Anadido (2026-09-01): **practica rudimentaria jugable sin HW**. `PracticeSession` (reloj musical propio integrado a mano + plato de juguete con friccion; acumula la traza del usuario para `HighwayView`), `PlatterInputView` (`NSView`: trackpad = girar el plato, `A`/`D` = atras/adelante, Espacio = fader cerrado, flechas = BPM, Esc = salir), `LivePracticeView` (autopista + capa de entrada + barra de ayuda). `AppRootView` la usa en `.practice`. **Todavia sin scoring** (necesita el callback de audio con captura, B4.2): la sesion de verdad (series, cuenta atras, `XFEngine`+`XFAnalysis`) sigue pendiente. 10 tests de la fisica.
      - Anadido (2026-09-01, **ADR-039**): **audio en la practica**. Ruta solo-salida del motor (`xf_engine_start_output`), base instrumental como 2o `xf_player` en bucle a `bpm/native_bpm` (`080bpm_beat.wav`), scratch sonando con la velocidad del plato (`Ahh.wav`). `AudioAsset` decodifica con `AVAudioConverter`; `ContentLoader.url(_:)` para leer `Audio/` del repo. Corregido un SIGILL latente en `xf_engine_stop`. 15 tests (9 nucleo RT + 6 XFApp). El arranque real de CoreAudio no se testea (se verifica con la app).
      - Anadido (2026-09-01): mas feedback de la practica. **Tira de forma de onda** del sample de scratch (`WaveformEnvelope` puro + `WaveformStripView` estilo DVS: la onda se desplaza bajo una aguja fija siguiendo `xf_engine_scratch_playhead`, alineada a la cabeza de lectura de la autopista). `ex-l1-baby` arranca mas lento (`startBpm` 70->50, escalera 50..90).
      - Iterado (2026-09-01, feedback): **ruido de fondo** = zumbido de DC del `xf_player` parado -> puerta por velocidad (`xf_player_set_speed_gate`, 0,12 en el scratch). **Glitches** = dos integradores con escalas distintas -> ahora la velocidad al reproductor es la derivada EXACTA de la posicion normalizada; **se quita el `seekScratch` por fotograma** (carrera hilo normal↔RT = click periodico). **Rango util del sample 0,6** (`AudioAsset.scratchUsableFraction`). **Mute solo el scratch**: `xf_engine_set_scratch_gain` (rampa ~5 ms); el fader/Espacio no toca la instrumental ni el metronomo. **Headroom anti-clip**: base 0,5->0,3, master 0,85. **Arranca al tempo de la instrumental** (80). **BPM en saltos de 5**. **Buffer configurable** 64/128/256/512/1024 (`AppSettings.bufferOptions`, por defecto 512); ajustes ahora **persisten** en plist local (`UserDefaults`, tapa el hueco del accesor `setting`). **Nombre de usuario** en Ajustes. Plato **arranca en el centro** del recorrido + `scrollGain`/friccion afinados. **Miniatura TTM en todo el L1**, rehecha: curva partida donde el fader cierra + circulo por transicion, sin barra. **Onda**: aguja alineada a la cabeza de lectura (0,30), `visibleFraction` 0,9, no se apaga con el fader. Fader cerrado oscurece solo la traza del usuario (`.miss`). **`crab` L6->L4**. **Libreria**: fila se expande al pinchar con el grafico TTM + boton Practicar; agrupa por nivel de curriculo. `ex-l1-baby` 70->50 BPM.
      - Anadido (2026-09-01): **fix de legibilidad**. `AppRootView` fuerza `.preferredColorScheme(.dark)` + `.foregroundColor(XFColor.text)`: en un Mac en modo claro el texto sin color explicito salia casi negro sobre el fondo casi negro. XFDesign (SEALED) no se toca; la paleta ya era correcta.
      - Iterado (2026-09-01, **ADR-041 + ADR-042**): **mapeo 2/3** — el pico del patron cae en `2/3` del sample (`AudioAsset.scratchPatternTopFraction`), el plato recorre hasta el final; `HighwayGeometry.patternFill` deja el tercio de arriba libre y la traza que se pasa del pico se extrapola ahi (XFRender re-sellado). **Sonido: la velocidad manda**; el objetivo de posicion pasa a ser un **trim anti-deriva acotado** a ±1,5% de pitch dentro del player (`xf_player_set_target_playhead`) — arregla el crujido (era `set_playhead` a saltos) y el "laser" (era un one-pole rapido persiguiendo escalones de 60 Hz). **Buffer en caliente**: selector en el panel de pruebas que llama a `EngineHandle.restartOutput` (para/recrea/recarga el motor sin reiniciar la app); `bufferOptions` hasta 2048. **Volumenes NO se persisten** (a 0 en el plist = practica muda); `@State` de sesion a 0,5. **Boton de metronomo** en la barra superior. **Slider de sensibilidad del trackpad** (provisional). CXFAudioCore 54, XFApp 135, XFRender 46.
      - Iterado (2026-09-02, **ADR-048**): **una sola visualizacion**. `PracticeScene` (XFApp) pinta la autopista (via `HighwayLayout` publico, replicando el `render` de `HighwayScene`), la tira de la instrumental (banda superior, misma formula de X que la autopista) y el sample (rail **vertical** a la izquierda, giro 90º, aguja = `scratchProgress`) en el MISMO `update(_:)` → la rejilla de compas ya no puede desfasarse al perder un frame. `LivePracticeView` deja de usar `HighwayView`+`InstrumentalStripView`+`WaveformStripView`; se borran `InstrumentalStripView`/`WaveformStripView`/`WaveformScene`. **Curriculo:** fuera los trucos no basicos como ejercicio practicable (baby-16, lo/hi-flare, flare-2c-16): `data/curriculum/exercises.json` 25→21; la libreria de scratches no se toca. Las variaciones de los basicos van por variantes (escalera de subdivision).
      - Iterado (2026-09-03, feedback, **ADR-054..058**): **MIDI de comandos** — `PracticeCommandMidi` (XFCapture) decodifica nota/CC → comandos de practica; `AppModel` es dueño de `MidiCommandSource` y publica `PracticeCommandEvent`; `LivePracticeView` los enruta a lo mismo que el teclado; fila "MIDI · comandos" en Ajustes; seccion `[transport]` en `DEVICE_PROFILES.md` y bloque comentado en el `.conf` de la Rane 72. **Miniaturas TTM** — `TTMThumbnail` pasa a `[Segment]` (curva entera partida por fader); `TTMThumbnailView` pinta lleno = suena / **a rayas** = cortado, sin puntos; arregla `tear-flare-1c`/`crab` que se salian del cuadro; recuadro **"Como leer el grafico"** en Home. **Vídeo** — proporcion de la ventana (`onHighwaySize`) en vez de 9:16 estirado; la línea refleja los cortes de fader; ver F.4. **Ajustes** — reescrito sin `Form` (macOS 11 lo dejaba en blanco con `ForEach`): `ScrollView` + `XFCard` a mano. **Pantalla de carga** con una cita de `citas.md` mientras decodifica el audio.
      - Iterado (2026-09-03, feedback, **ADR-059**): **MIDI Learn**. `MidiMonitorConnector` (XFCapture, CoreMIDI genérico) escucha todas las fuentes mientras Ajustes está abierto; `MidiLearnModel` (XFApp) lleva el estado (comando seleccionado, armado, último visto). En la sección "MIDI · comandos": cada comando es un radio, un botón **"Aprender MIDI"** arma la escucha y el siguiente Note On / CC que llegue queda asignado (`MidiBinding.learned`). Se sigue pudiendo escribir a mano y hay un botón de limpiar por fila. 4 tests de `MidiLearnModel` + 1 de `MidiBinding.learned`.
- [x] **B11.4** Pantalla de resultados con diagnostico `XFApp`
      - Hecho (2026-09-01): junto con B11.13. `ResultsSummary` (puro) traduce lo que calculo `XFAnalysis` a texto: 3 filas de estrella (las apagadas con su condicion, sacada de `starReasons` por prefijo `★`/`★★`/`★★★` y sin el `Titulo:`, o la condicion por defecto si aun no toca), puntuacion `3.840 / 4.800` (millares con punto), `%`, badge Record, frases del coach en orden. `ResultsView` SwiftUI con las estrellas escalonadas. 6 tests.
- [x] **B11.5** Modo libre con grabacion de los ultimos 30 s `XFApp`
      - Hecho (2026-09-01): `FreeModeRecorder` (clase) — buffer rodante de `MotionSample`/`FaderSample`: al llegar una muestra tira las que caen fuera de la ventana de 30 s. No mira el reloj (el driver pasa cada muestra con su `hostTime`). `snapshot` para guardar como `.xfsession`, `durationSeconds`, `reset()`. 5 tests.
      - Nota (2026-09-02): `FreeModeView` (la maqueta SwiftUI) **borrada**; `.freeMode` ahora reutiliza `LivePracticeView` en modo **Freestyle** (nav "Freestyle"). `FreeModeRecorder` se queda: la ventana rodante de 30 s es un concepto distinto de "pulsa REC".
- [x] **B11.6** Navegador de la libreria `XFApp`
      - Hecho (2026-09-01): `LibraryEntry` (scratch + estado de bloqueo, `init(scratch:isUnlocked:)`) + `LibraryBrowser` (puro): `levels`/`families`, `filtered(query:level:family:onlyUnlocked:)` (busqueda por subcadena sin mayusculas ni acentos), `groupedByLevel(...)`. `LibraryView` SwiftUI con buscador y filtro de familia. 6 tests.
- [x] **B11.7** Ajustes `XFApp`
      - Hecho (2026-09-01): `AppSettings` (envoltorio tipado de la tabla clave/valor `setting`): hamster, metronomo, buffer 64/128, escala de tolerancia (0.5..2.0), alto contraste, reducir movimiento. `init(raw:)` tolera claves ausentes o ilegibles (caen al default) y recorta rangos; `.raw` para guardar. Todo local (CLAUDE.md 3). 5 tests.
      - Iterado (2026-09-03): `AppSettings` gana `lastScratchSamplePath` (F.3) y `midiCommandOverrides` (ADR-054). `SettingsView` **reescrito sin `Form`** (macOS 11 lo dejaba en blanco con `ForEach`, ADR-058): `ScrollView` + `VStack` + `XFCard` a mano, controles nativos. Nueva seccion "MIDI · comandos".
- [x] **B11.8** Accesibilidad: VoiceOver, alto contraste, teclado `XFApp`
      - Criterio: segun UI_DESIGN.md seccion 4
      - Hecho (2026-09-01): `A11y.Palette` (alto contraste: ghost al 60%, trazos mas gruesos — XFDesign esta sellado, esto va encima). `A11y.resultsDescription` (resumen de resultados para VoiceOver: N/3 estrellas, puntuacion sin leer la barra, mejor marca, que falta, diagnosticos) y `highwayLiveAnnouncement` (region en vivo con el resumen de compas). Atajos de teclado en `PracticeView` (flechas=BPM, Esc=salir) y `ResultsView` (R=otra vez). 4 tests.
- [x] **B11.9** Pantalla Mi mesa: lista de perfiles, insignias y prueba en vivo `XFApp`
      - **(2026-09-04, ADR-073)**: `onCalibrate` no estaba conectado — el botón
        "Calibrar" de cada fila no hacía NADA. Ahora navega a la pantalla de
        Calibración. `onTestLive` ("Probar") sigue sin conectar a propósito: no
        hay todavía una rutina de "prueba en vivo" real (necesita B4.2).
        `docs/UI_DESIGN.md` §3.8 describe una "Mi mesa" más rica (buscador,
        agrupar por fabricante, autodetección, duplicar/crear/importar) que la
        implementada — pendiente decidir cuánto construir de eso.
      - Criterio: UI_DESIGN.md 3.8
      - Hecho (2026-09-01): `MyTableRow` (perfil: fuente bundle/user, insignia verificado/sin verificar, si hay calibracion, latencia) + `MyTable` (`active`, `sorted` = activo primero, luego verificados, luego el resto; `verifiedCount`/`calibratedCount`). `MyTableView` SwiftUI con botones Probar / Calibrar / Usar. 3 tests.
- [x] **B11.10** Asistente de mapeo MIDI/HID con monitor en crudo `XFApp`
      - Criterio: UI_DESIGN.md 3.9; si no llega MIDI en 5 s, propone audio_return
      - Hecho (2026-09-01): `MidiMappingModel` (`ObservableObject`): monitor en crudo (`rawLog` capado a 200, lo mas reciente delante), MIDI Learn del crossfader (`learn(.crossfader)` -> captura el CC del siguiente Control Change), `shouldSuggestAudioReturn(now:)` (true si llevamos >= 5 s escuchando sin ningun mensaje MIDI, ADR-021). No mira el reloj: se le pasa `now`. `MidiMappingView` SwiftUI con la tarjeta de propuesta de `audio_return`. 6 tests.
- [x] **B11.11** Exportar perfil y flujo de aportacion `XFApp`
      - Criterio: genera un .conf valido segun tools/xf_profile.py
      - Hecho (2026-09-01): `ExportableProfile` (id que se limpia a minusculas sin espacios, method midi/audio_return/hid/none, cut-in, histeresis, claves por metodo) + `ProfileExporter` (`iniText` -> `.conf` INI, `validationErrors` que replica las reglas de `xf_profile.py`). `ProfileExportView` SwiftUI (previsualiza el .conf y los errores). 6 tests, **incluido uno end-to-end** que genera el .conf y lo pasa por `tools/xf_profile.py` de verdad -> exit 0.
- [x] **B11.12** Permiso de microfono con texto honesto y pantalla de ayuda si se deniega `XFApp`
      - Criterio: si el usuario dice que no, la app explica que hacer
      - Hecho (2026-09-01): `MicPermission` (enum: notDetermined/granted/denied/restricted) con `rationale` honesto ("el timecode entra como entrada de audio; macOS lo llama microfono"), `canRequest`/`canCapture`, y `helpSteps` con los pasos de Ajustes del Sistema cuando esta denegado. `MicPermissionView` SwiftUI. 3 tests.
- [x] **B11.13** Resultados con estrellas y puntuacion sobre el maximo `XFApp`
      - Criterio: las estrellas apagadas dicen que falta para conseguirlas
      - Hecho (2026-09-01): cubierto por `ResultsSummary`/`ResultsView` de B11.4 — `scoreText` sobre el maximo y `StarRow.condition` no nula en cada estrella apagada.
- [x] **B11.14** Pantalla de progreso por ejercicio y variante `XFApp`
      - Criterio: UI_DESIGN.md 3.4b
      - Hecho (2026-09-01): `ExerciseProgressDisplay.build(ProgressSummary)` formatea los campos de `docs/SCORING.md` §3: intentos, mejor + fecha, ultima, media de 5, estrellas, mejor BPM con 3★, sesgo medio **con signo** (+15 ms / −8 ms), tiempo total ("1 h 13 min"), y la linea de los ultimos 20. `ExerciseProgressView` SwiftUI con sparkline. 2 tests.
- [x] **B11.15** Selector de variantes con estado de bloqueo `XFApp`
      - Criterio: muestra la condicion de desbloqueo, no solo el candado
      - Hecho (2026-09-01): `VariantOption` con `Lock` = `.unlocked` / `.locked(condition:)`. `build(...)` toma la regla de `variants.json` (`requires: (variantId, stars)`) + las estrellas del usuario en esa variante y produce la condicion escrita ("★★ en Base"). `VariantPickerView` SwiftUI muestra "Necesitas ★★ en Base", no solo el candado. 1 test.
- [x] **B11.16** Detectar Rosetta (sysctl.proc_translated) y avisar en calibracion `XFApp`
      - Criterio: si esta traducido, la app lo dice y ofrece la version universal
      - Hecho (2026-09-01): `RosettaCheck.isTranslated` via `sysctlbyname("sysctl.proc_translated")` (con `translated(reader:)` inyectable para test: 1=traducido, 0=nativo, -1=no disponible). `calibrationWarning` da el texto ("corriendo bajo Rosetta... descarga la version universal") o `nil`. 2 tests.

## B12 — Distribucion

*Que lo pueda usar alguien que no seas tu.*

> **ADR-037 (2026-09-01):** la primera via es un **DMG sin notarizar por GitHub
> Releases**. El bloque se parte en **B12a** (eso, alcance minimo) y **B12b**
> (notarizacion + Homebrew, el plan final de CLAUDE.md §4, pospuesto sin fecha).

### B12a — DMG sin notarizar para GitHub Releases

- [x] **B12a.0** Empaquetar recursos en el bundle `XFApp`
      - `data/` y `profiles/` dejan de leerse del repo (`RepoContentLoader` via
        `#filePath`) y pasan a recursos del bundle. En la app: `BundleContentLoader`.
        `RepoContentLoader` queda solo para tests y `swift run`.
      - Criterio: la app arranca y monta el catalogo desde el `.app`, sin el repo delante.
      - Hecho (2026-09-01): parte de **codigo**. `BundleContentLoader` (en
        `ContentLoader.swift`) lee `data/`/`profiles/` de `Bundle.main.resourceURL`;
        `hasCatalog` sondea `data/scratches/library-v0.1.json`. El `@main` de `xFlare`
        elige: si el bundle trae el catalogo -> `BundleContentLoader`; si no
        (p. ej. `swift run`) -> `RepoContentLoader`. 4 tests (monta una carpeta con
        la forma de `Contents/Resources/` y comprueba que sirve el mismo catalogo
        que el repo; carpeta vacia -> `hasCatalog == false`).
      - **Hecho el copiado (2026-09-02):** `make app` monta `xFlare.app/Contents/
        {MacOS,Resources}` y hace `cp -R data profiles citas.md` a
        `Contents/Resources/`; `make dmg` lo empaqueta.
      - **Smoke test hecho (2026-09-03):** `xFlare.app` copiada a `/Applications`
        y lanzada desde ahí → arranca, monta el catálogo entero (6 niveles, 18
        trucos, matriz + leyenda) desde `Contents/Resources/` (`BundleContentLoader`
        gana sobre `RepoContentLoader`). Navegación OK.
      - **Fix de copyright (2026-09-03):** `make app REL=1` **ya NO empaqueta
        `Audio/`** (samples con copyright, `CLAUDE.md` §12). El DMG de Releases va
        sin sonido de fábrica; el usuario carga los suyos ("Cargar sample…").
      - **Segunda confirmación (2026-09-05):** `make app` + copiado a un directorio
        fuera del repo (no `/Applications`, un temporal) y lanzado desde ahí →
        arranca, sigue corriendo varios segundos sin errores en stdout ni en el
        log del sistema. El criterio de aceptación ("arranca y monta el catálogo
        sin el repo delante") ya estaba satisfecho desde el smoke test de
        2026-09-03; solo faltaba marcar la tarea — el flag se había quedado en
        `[~]` en `data/backlog.json` pese a que la nota ya decía "Smoke test
        hecho".
- [x] **B12a.1** `Info.plist` del `.app`
      - Hecho: `make app` escribe el `Info.plist` con `NSMicrophoneUsageDescription`
        ("xFlare necesita la entrada de audio para leer el vinilo de control"),
        `CFBundleIdentifier` (`app.xflare.xFlare`), `CFBundleShortVersionString`,
        `LSMinimumSystemVersion 11.0`, `NSHighResolutionCapable`, e icono
        (`icon/xflare.icns`, se genera de `xflare.svg` si falta).
- [ ] **B12a.2** Verificar binario universal `x86_64 + arm64` en las dos maquinas
      - Criterio: PLATFORM_SUPPORT.md seccion 9 completa. ADR-028 no se relaja.
      - **Esta maquina OK (2026-09-03):** `make universal` -> `Build succeeded`,
        `lipo -archs .build/apple/Products/Release/xFlare` = `x86_64 arm64`. El
        `.app` dentro de `make dmg REL=1` da `Mach-O universal (x86_64 arm64)`.
      - **Falta**: la corrida de `lipo` en la segunda maquina (si la hay). Si es
        Intel tambien, el slice `arm64` no lo prueba nadie en hardware -> decirlo
        en la nota de release (ya esta en el README).
- [x] **B12a.3** Firma ad-hoc (`codesign -s -`)
      - Hecho: `make app` hace `codesign --force --deep --sign - xFlare.app`;
        `make dmg` re-firma el `.dmg`. Verificado: `codesign -dv` da
        `flags=0x2(adhoc)`.
- [~] **B12a.4** Script de empaquetado + DMG plano con el `.app` dentro
      - Hecho (2026-09-02/03): `make dmg` — `hdiutil create ... -format UDZO`
        sobre un staging con `xFlare.app` + enlace a `/Applications`. Sin fondo
        ni layout (eso es B12b.2). **`make dmg REL=1`** empaqueta el binario
        RELEASE UNIVERSAL.
      - **Verificado (2026-09-03):** `xFlare-0.1-preview.dmg` (8,2 MB, UDZO).
        Montado: `xFlare.app` + symlink a `/Applications`; el `.app` de dentro
        da `lipo -archs` = `x86_64 arm64`, `codesign` = `flags=0x2(adhoc)`, y
        Resources = `citas.md data profiles xflare.icns` (**sin `Audio/`**).
      - **Falta (manual):** `gh release create` con un tag de versión (ver
        `docs/RELEASE.md` §3). No lo hace Claude: publica un artefacto público.
- [x] **B12a.5** Nota de release
      - Hecho (2026-09-03): `docs/RELEASE.md` — lista de comprobación pre-flight,
        cómo construir (`make universal` + `make dmg REL=1`), cómo publicar
        (`gh release create`), y la **plantilla del texto de la nota** con el
        rodeo de Gatekeeper (clic derecho → Abrir / `xattr -dr
        com.apple.quarantine`) y el enlace al tag exacto del fuente (GPL-3.0).
- [~] **B12a.6** README publico, capturas, video de 30 s
      - Hecho (2026-09-03): README con seccion **"Estado"** (que funciona ya /
        que falta para la v1), **"Probarlo"** (`swift run` / `make app` / `make
        dmg REL=1`, rodeo de Gatekeeper, nota de que el release va sin samples)
        y **"Capturas"** (4 PNG en `docs/screenshots/`: Home, practica, Ajustes,
        Mi mesa; 1500 px). Rango de ADR corregido (001–058).
      - **Falta:** un video de 30 s (Home → practica → grabar → exportar).
        Accion manual (grabar pantalla).
- [ ] **B12a.7** 5 DJs probandolo y sus notas
      - Criterio: el examen de verdad

### B12b — Notarizacion + Homebrew (pospuesto, sin fecha)

- [ ] **B12b.0** Cuenta de Apple Developer + `codesign` con identidad real
- [ ] **B12b.1** `notarytool` + `stapler` sobre el `.app` de B12a
- [ ] **B12b.2** DMG estilado (fondo, layout, enlace a /Applications)
- [ ] **B12b.3** Formula de Homebrew (tap + `sha256`)


---

# FUTURIBLES

## FUT — Futuribles

*No tocar hasta que la v1 este en manos de gente.*

- [x] **F.0** Calentamiento adaptativo con deteccion de oxidacion (ADR-027)
      - Criterio: docs/WARMUP.md; el esquema de BD ya lo soporta desde la v1
      - Iniciado (2026-09-03): **lógica hecha**. `WarmupPlanner` (XFApp, puro):
        `plan([Candidate], rng:)` escoge 4-6 ejercicios dominados ordenados por
        urgencia (peso alto: días desde repaso + caída absoluta respecto al
        techo; peso bajo: antigüedad del dominio), aplica **variedad de familia**
        (penaliza x0,45 por familia repetida al seleccionar) y asigna una
        variante desbloqueada al azar **≠ la del último calentamiento**.
        `WarmupOxidation.check(...)` → mensaje "El crab se te está cayendo: hoy
        78 %, tu media era 94 %…" cuando una toma de calentamiento baja de 2★.
        `AppModel.warmupPlan(now:rng:)` monta los `Candidate` de la BD
        (masteredExercises + progress + attempts + reviewItem + mastery +
        unlockedVariants) y `settleWarmupTake(...)` registra la toma
        (`mode:.warmup`, `countsForStars:false`), alimenta la repetición
        espaciada (`recordReviewOutcome`) y marca `setOxidized` si toca.
        12 tests (`WarmupPlannerTests`).
      - **Pantalla hecha (2026-09-03):** `WarmupView` — el plan de hoy (nº · truco
        · variante · motivo), un botón "Empezar calentamiento" y "Saltar" que
        vuelve a Home. Nav "Calentar" (icono `flame`).
        `AppModel.openWarmup()` genera el plan **sugerido**
        (`SystemRandomNumberGenerator`) y `WarmupAssembler.rows(...)` lo resuelve
        contra el catálogo.
      - **Plan editable (2026-09-03, feedback):** la sugerencia es el punto de
        partida. En `WarmupView` el usuario puede **borrar** una fila, **×2 / ÷2**
        el nº de frases de un ejercicio (acotado 2…32) y **"+"** añadir cualquier
        ejercicio de la librería (`AppModel.warmupLibrary: [WarmupPickable]`, sin
        filtrar por dominio; se puede repetir truco, cada `WarmupRow` lleva `id`
        propio — antes era `exerciseId/variantId`). `startWarmupSession(rows:)`
        recibe la lista YA editada. No se persiste: cada día parte de la sugerencia.
      - **Una sola sesión encadenada (2026-09-03, feedback):** el calentamiento
        ya no es una práctica por fila. `startWarmupSession(rows:)` monta
        `[WarmupStep]` (patrón + nombre + nº de frases) de la lista editada y abre
        la práctica en la primera. `PracticeSession.reload(scratch:)` cambia el
        patrón **en caliente** (sin parar el reloj ni recrear la sesión);
        `LivePracticeView` cuenta las frases de "repite conmigo" completadas
        (`.onChange(session.crPhase)`) y llama a `advanceWarmup()` al llegar a
        `phraseCount`, saltando al siguiente `WarmupStep`. La barra superior
        muestra "Calentamiento i/N". Al terminar el último, sale a Home.
      - **Rutina de arranque (2026-09-03, feedback):** si no hay historial (nada
        dominado), en vez de una pantalla vacía sale una rutina fija:
        **Forward Cut → Reverse Cut → Chirp → Transformer x2**, cada uno **8
        frases de 2 compases** (`WarmupPlanner.starterScratchOrder` +
        `WarmupAssembler.starterPlan`). El plan (`PlannedItem`) y la fila
        (`WarmupRow`) llevan `phraseBars`/`phraseCount`.
      - **Arranca en "repite conmigo" (2026-09-03):** "Empezar calentamiento"
        abre la práctica ya en call-response con `crBars` = `phraseBars`
        (`AppModel.startCallResponseBars` → `LivePracticeView.startInCallResponseBars`).
      - **Puntuar dentro del calentamiento (2026-09-03):** el botón "Puntuar
        (calentamiento)" enruta a `AppModel.scoreWarmupTake(...)` →
        `settleWarmupTake` (`mode:.warmup`, `countsForStars:false`, alimenta la
        repetición espaciada y marca `setOxidized` si baja de 2★). El resultado
        (estrellas · precisión · aviso de oxidación) se enseña en un panel dentro
        de la práctica, **sin navegar a `.results`**, para no cortar la tanda.
        `WarmupStep` lleva ahora `exerciseId`/`variantId` para registrar contra el
        ejercicio que toca. Con esto **F.0 queda cerrado**.
- [ ] **F.0b** Variantes avanzadas: encadenado, densidad creciente, rampa de tempo, un solo lado `XFNotation`
      - Criterio: docs/VARIANTS.md seccion 4
- [ ] **F.1** Dos platos: juggling, chasing, notacion de doble carril
- [ ] **F.2** Pads y sampler; scratch sobre pads
- [x] **F.3** Importar tus propios samples con deteccion del punto cero
      - Iniciado (2026-09-03, a peticion del autor pese a la regla de "no tocar
        futuribles hasta la v1"): nucleo hecho. `SampleTrim` (XFApp, puro):
        `detectStart`/`detectEnd` buscan el ataque por RMS (umbral −45 dBFS,
        ventana 5 ms), retroceden 8 ms para no morder el transitorio y cuadran
        a **cruce por cero** (sin click al scratchear). `trimmed(_:sampleRate:)`
        recorta cabeza y cola y devuelve el offset; deja el original si no hay
        recorte fiable. Boton **"Cargar sample…"** en el panel de práctica
        (`loadScratchSample` → decodifica con `AudioAsset.loadMono` → `SampleTrim`
        → `engine.loadSample` + cue 1 + rehace la onda del rail). 6 tests.
        El sample elegido **se recuerda** entre sesiones
        (`AppSettings.lastScratchSamplePath`, se recarga si el fichero sigue ahí).
      - **Completado (2026-09-03):**
        · **Biblioteca de samples**: `AppSettings.sampleLibrary` (rutas, tope 12,
          dedup) + menú en el panel "Mezcla" (asset por defecto · recordados ·
          "Cargar otro…"). Al cargar uno nuevo entra en la lista.
        · **Cue points A/B** por sesión: `PracticeSession.jumpTo(sampleFraction:)`
          (inverso de `normalizedPosition`); botones `+A`/`+B` fijan la posición
          del cabezal y saltan a ella; pulsación larga los borra.
        · **Detección de loop rítmico**: al cargar, `TempoAnalyzer.analyze`; si
          `isShortLoop`, avisa "loop ≈ 92 BPM · 2 compases" (solo informativo —
          el sample se scratchea igual, pero así sabes que quizá va como base).
- [x] **F.4** Exportar la toma como video para compartir
      - Criterio: el bucle de crecimiento mas barato que existe
      - Iniciado (2026-09-03): **vídeo hecho**.
        `TakeVideoExporter` (XFApp): `framePlan(...)` (los `currentTick` de cada
        fotograma) y `trace(from: XFSession)` (la línea grabada al dominio de
        ticks del patrón, **marcando los tramos con el fader cerrado**) son
        puros; `render(HighwayFrame → CGImage)` rasteriza con Core Graphics
        (rejilla, fantasma partido por fader, **tu línea** —teal y llena donde
        suena, gris y a rayas donde se corta—, marcas ○/●, phantom clicks);
        `export(...)` monta el mp4 H.264 con `AVAssetWriter` en segundo plano.
        Botón **"Vídeo…"** en el panel "Grabar línea". 12 tests, incluido un
        export real a fichero temporal verificado con `AVURLAsset` (pista de
        vídeo, tamaño y duración).
      - **Proporción de la ventana (2026-09-03, ADR-056):** antes forzaba
        1080×1920 (9:16) sobre un layout apaisado y todo salía estirado ~5×.
        `Options.width/height` pasan a opcionales; si faltan, la resolución se
        deriva de la geometría de la autopista (`Options.pixelSize(for:)`, lado
        mayor 1600, pares). `PracticeScene` reporta su tamaño real
        (`onHighwaySize`) y `LivePracticeView` lo usa: el vídeo sale con la
        proporción exacta de la ventana.
      - **Refleja los cortes (2026-09-03, ADR-057):** `trace(from:)` cruza el
        movimiento con el carril de fader grabado; los puntos con el fader
        cerrado van marcados y el rasterizado los pinta a rayas. Antes salía
        todo teal.
        **Barra de progreso hecha (2026-09-03):** `export(...)` gana un callback
        `progress: (Double) -> Void`; el botón "Vídeo…" muestra el % y una barra
        fina.
      - **Audio hecho (2026-09-03):** `TakeAudioRenderer` reproduce el `xf_engine`
        **offline** (el motor RT de verdad, sin CoreAudio) siguiendo la
        velocidad / posición / fader grabados — mismo DSP que la práctica.
        `export` escribe el vídeo mudo a un temporal, renderiza el audio a CAF y
        los combina en el mp4 con `AVMutableComposition` + `AVAssetExportSession`.
        `EngineHandle` expone `scratchPCMCopy()` / `instrumentalPCMCopy()` para
        alimentarlo.
      - **Revelado en vivo (2026-09-03):** cada fotograma solo pinta la traza
        **ya tocada** (`tick - 12 negras … tick`); antes se veía la línea entera
        desde el fotograma 1 y parecía "una foto que se desplaza".
      - **Opcional completado (2026-09-03):**
        · **Mezcla del vídeo = la del mixer**: `export(... mix:)` reenvía los
          volúmenes de sesión (`sampleVol`/`instruVol`) a `TakeAudioRenderer` en
          vez de las ganancias fijas. El vídeo suena como lo que oías.
        · **FPS y resolución en Ajustes**: `AppSettings.videoFps` (24/30/60) y
          `videoLongSide` (Rápida 1280 / Estándar 1600 / Alta 2400); sección
          "Vídeo" en Ajustes; `LivePracticeView` los pasa a `Options`.
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
- [x] **F.12** Librería de medios: instrumentales pre-analizadas + samples a botones MIDI (ADR-062)
      - Pedido por el autor (2026-09-03): reservar el nombre "Librería" para los
        **medios del usuario**, dejar las instrumentales pre-analizadas dentro de
        la app para que carguen al instante, y poder cambiar de sample con
        botones de la mesa en mitad de una sesión.
      - **Fase 1 — reestructura del menú (2026-09-03):** el navegador de scratches
        pasa a **Trucos** (`LibraryView` reescrito a `LazyVGrid` de tarjetas, cada
        una con su notación TTM a la derecha vía `TTMThumbnailView`). Nuevo menú
        **Librería** (`MediaLibraryView`, `Screen.mediaLibrary`) con pestañas
        **Instrumentales** / **Samples**; `AppSettings.instrumentalLibrary` (tope
        200). Añadir por `NSOpenPanel` o quitar con la ✕.
      - **Fase 2 — caché de pre-análisis (2026-09-03):** `InstrumentalAnalysisCache`
        (`ObservableObject`): al añadir una instrumental se analiza el tempo UNA
        vez en segundo plano (`qos: .utility`) y se cachea en
        `~/Library/Application Support/xFlare/instrumental-analysis.json`
        (`CachedAnalysis: Codable`, invalidado por tamaño/mtime del fichero y por
        la sample rate). En la práctica `loadInstrumental` lee del caché → carga
        instantánea. `TempoAnalyzer.Result: Codable`. La tarjeta muestra
        "analizando…" / "≈ N BPM · M compases". **Arrastrar y soltar** audios
        sobre las dos listas; añadir **una carpeta entera** con casilla
        "subcarpetas" (`FileManager.enumerator`); aviso `NSAlert` si entran ≥ 20
        pistas de golpe. 6 + 4 tests (`InstrumentalLoopTests`,
        `InstrumentalAnalysisCacheTests`).
      - **Fase 3 — samples a botones MIDI (2026-09-03):** `AppSettings.sampleSlots`
        (**siempre 4**, `""` = vacío). `PracticeCommand.sample1…sample4` (XFCapture,
        `command.sample_1`…`_4`); en la práctica `LivePracticeView.loadSlot(i)`
        hace `cue` + carga el fichero del slot. Sección **SLOTS MIDI** en la
        pestaña Samples (4× `Menu`). Y el **selector de instrumental de la
        práctica** pasa a ser un `Menu` que lista las instrumentales analizadas de
        la librería (carga al instante) + la base por defecto + "Cargar otra…".
        +2 tests (`AppSettings.sampleSlots` ida y vuelta, `PracticeCommand`
        sample1..4). 632 tests en verde.
- [x] **F.13** Fichero de configuración + pulido de la pantalla de práctica (ADR-063, ADR-064)
      - Feedback del autor (2026-09-03):
      - **Fichero de configuración (ADR-063):** `SettingsStore` guarda `AppSettings`
        como JSON legible/copiable en
        `~/Library/Application Support/xFlare/settings.json`, **atómico en cada
        cambio**. Antes solo `UserDefaults`, que `cfprefsd` vaciaba tarde y perdía
        cambios si la app se cerraba de golpe ("las canciones y la configuración
        no se guardan de una vez a otra"). `loadSettings` prefiere el fichero y
        migra el plist viejo. 2 tests.
      - **Reorg de la práctica (ADR-064):** columna izquierda `leftColumn` con todo
        lo del SAMPLE (selector, **4 slots MIDI** que asignan y disparan, cue A/B,
        meter, EQ, volúmenes). Zona inferior `bottomBar`: fila compacta (nombre +
        reiniciar/÷2/×2/◀/▶/TAP/BPM) que se despliega (`instrLibraryPanel`) a la
        lista de instrumentales analizadas de la Librería y se minimiza sola al
        cargar. `LivePracticeView` gana `onSampleSlotsChanged`.
      - **BPM con un decimal:** `PracticeSession.bpm` `Int`→`Double` (`setBPM`
        redondea a 0,1), `TapTempo.tap()` devuelve `Double?` (media de 4-8
        golpes), `PlatterInputView.onBPM`/`currentBPM`→`Double`; UI con `%.1f`,
        entrada con coma o punto. +2 tests.
      - **Tope del sample:** `AudioAsset.scratchMaxSeconds` (2 s) + `capScratch` —
        un fichero largo ya no barre minutos de audio con un gesto ("se va todo").
        +1 test.
      - **Números de rejilla:** `PracticeScene.gridLabels` (puro) — "compás.
        subdivisión" (1.1, 1.2…) sobre cada línea, arriba, discretos, siguen
        `gridShift`. +1 test.
      - 638 tests en verde.
- [x] **F.14** Pasada de optimización: menos coste por fotograma (ADR-065)
      - "Revisa todo el código y optimízalo para que vaya más ligero." Cambios
        **sin cambio de comportamiento** (638 tests igual, sin tocarlos):
      - `PracticeScene`: `SKLabelNode.text`/`isHidden` solo se escriben si
        cambian (cambiar el texto re-tesela el glifo); `gridLines`/`gridLabels`
        rellenan buffers reservados (0 `malloc`/frame); `renderUserTrace` trocea
        la traza en runs sin `[(Bool,[CGPoint])]` intermedios (pinta con
        move/addLine sobre índices).
      - `PracticeSession`: `traceBuffer.reserveCapacity(512)`; poda del prefijo
        caducado con `removeFirst(k)` en vez del predicado de `removeAll(where:)`.
      - `ClipMeterView` (nuevo): el sondeo a 20 Hz (pico de salida + corrección de
        deriva del metrónomo) sale de `LivePracticeView` a su propia vista con su
        propio timer; el `body` grande ya no se re-evalúa 20×/s salvo mientras se
        graba una línea.
      - `xf_player_render` (RT): la vuelta del bucle de la base cambia `fmod` por
        sumas/restas (`|v|` <<< `frames`; resultado idéntico), una llamada a libm
        menos por muestra.
- [x] **F.15** `XFTestKit`: fuentes falsas + señales sintéticas centralizadas (ADR-066)
      - El módulo existía desde B0.1 con solo `Golden` y un marcador. Ahora
        recoge lo reutilizable de test que no es de un módulo concreto:
      - **`Signals`** — `sine` / `silence` / `quadratureTimecode` (deterministas;
        misma fórmula que ya usaban los tests de timecode, hasta ahora duplicada
        *verbatim* en `CXFTimecodeTests` y `XFCaptureTests`).
      - **`FakeMotionSource` / `FakeFaderSource`** — implementaciones de mentira
        de los protocolos de `XFCapture` (script o valor fijo, conteo de
        `start()`/`stop()`, `startError`).
      - **`RepoFiles`** — `root()` / `url(_:)` / `data(_:)` / `text(_:)` subiendo
        desde `#filePath` hasta `Package.swift`.
      - `Golden` estrena tests propios. `XFTestKitTests` nuevo (18). 656 en verde.
      - Los `*Fixtures` de los módulos sellados **no** se migran (tests inmutables);
        los nuevos tests y el trabajo pendiente de B6.7 / B8.5 ya usan esto.
- [x] **F.16** Editor de instrumental: tempo/rejilla, cues y loops de una parte (ADR-067)
      - "Un mini editor donde ajustar la rejilla y el tempo antes de entrar en
        los ejercicios", "puntos Cue para practicar sobre partes", "hacer partes
        loops infinitos".
      - **RT** (`xf_player`): `loop_start`/`loop_end` — con loop activo el cabezal
        y la lectura sinc envuelven dentro de la región (bucle de una parte tan
        continuo como el del fichero entero). `xf_player_set_loop_region` (leída
        1×/bloque y saneada en el render). `xf_engine_set_instrumental_loop_region`
        + `xf_engine_seek_instrumental`. Por defecto = entero (sin cambio).
      - **Datos**: `InstrumentalEdit` (puro, `Codable`) + `InstrumentalEditStore`
        (JSON en `instrumental-edits.json`, por ruta) + `AppModel.instrumentalEdits`.
      - **Editor**: `InstrumentalEditorView` (`Screen.instrumentalEditor`, botón
        de ajustes en cada fila de la Librería). Reproduce de verdad (play/pausa,
        pinchar la onda, oír el loop de una región). Onda + rejilla con números
        arriba (SwiftUI, sin `Canvas`). BPM/TAP/÷2·×2/"fijar el 1 aquí"/compás;
        cues (añadir/renombrar/saltar/borrar); regiones (crear 4 compases,
        nudge, activar, borrar).
      - **En la práctica**: `loadInstrumental` usa el `InstrumentalEdit` si lo
        hay (BPM y "1" del editor mandan sobre la detección; la región activa se
        aplica con `setInstrumentalLoopRegion`).
      - Tests: `XFPlayerLoopTests` +4, `XFEngineInstrumentalTests` +2,
        `InstrumentalEditTests` +5. 667 en verde.
      - **Pendiente v2**: cues en la propia práctica (botones de salto);
        re-aplicar la región de loop tras ÷2/×2/reiniciar la base; regiones que
        crucen el "1".
- [x] **F.17** Pulido: panel derecho colapsable, números de rejilla arriba del todo, icono en oscuro
      - Feedback del autor (2026-09-04):
      - **Panel derecho colapsable**: `rightPanel` de `LivePracticeView` pasa a un
        **rail de iconos** (uno por sección: Repite conmigo / Grabar línea /
        Ajuste rápido); pulsar un icono despliega esa sección (`openRight`),
        vuelve a pulsarlo para colapsar. Arranca colapsado.
      - **Números de rejilla arriba del todo**: `PracticeScene.moveGridLabels`
        pinta los números de compás en `y = size.height - 1` (encima de la tira
        de la onda de la instrumental), `zPosition` 20.
      - **Icono legible en oscuro** (`icon/xflare.svg` + `.icns` regenerado): la
        placa de fondo era casi negra (#171B22→#0A0C0F) y sobre un escritorio
        oscuro solo flotaba el cap verde. Ahora #2C333E→#141920 + borde tenue;
        cap fantasma y marcas un poco más visibles.
- [x] **F.18** Fixes del editor + regresión de persistencia (ADR-063 corr., ADR-067 iter.)
      - Feedback del autor (2026-09-04):
      - **REGRESIÓN: la librería de instrumentales se vació.** `SettingsView`
        guardaba TODO el `AppSettings` en un `@State` sembrado una vez; en una
        visita posterior estaba viejo y el primer cambio lo subía entero,
        pisando `instrumentalLibrary`. Arreglo: re-sembrar el `@State` desde la
        copia entrante (`.onChange(of:)` + `.onAppear`). +
        `AppModel.recoverInstrumentalLibraryIfNeeded` (una vez, con flag
        `libraryRecovered`): recupera las instrumentales que se llegaron a
        analizar y siguen en disco.
      - **El Play del editor no sonaba** en frío: `startEngine` no arrancaba la
        salida — ahora `engine.startOutput()` (idempotente).
      - **Zoom de la onda** en el editor: `zoom` 1…64×, botones −/+, pan con
        arrastre (con zoom) y toque = saltar; la ventana sigue al cabezal al
        reproducir. Rejilla/cues/regiones/cabezal por la ventana visible.
      - **Regiones de loop con ÷2 / ×2**: `scaleLoop` dobla/mitad la duración
        (inicio fijo); la fila muestra "N s · M compases".
      - **Colores del logo** (`icon/xflare.svg`): pasada para que se distingan
        placa / ranura / marcas / cap fantasma / cap vivo / surco / brillo.
      - 667 en verde.
- [x] **F.19** Editor: re-render al zoom · Cues instrumental por MIDI · Ajustes MIDI por categorías
      - Feedback del autor (2026-09-04):
      - **La onda del editor se re-renderiza al hacer zoom** (`renderWindow`):
        dibuja SOLO el tramo visible del PCM a 2400 px en 2º plano, con gen
        counter para descartar resultados tardíos. Antes estiraba la imagen del
        fichero entero y se veía borroso.
      - **Cues de la instrumental por MIDI**: `PracticeCommand.instrCue1…4`
        (`command.instr_cue_1…4`). En la práctica `jumpInstrCue(i)` salta la base
        al Cue `i` del `InstrumentalEdit` y re-cuadra rejilla + metrónomo ahí
        (como "reiniciar la base" pero desde el cue). Botones también en la zona
        inferior; cues sembrados en `loadInstrumental` desde `edit?.cues`.
      - **Ajustes › MIDI por categorías**: `PracticeCommand.Category`
        (global / sample / instrumental); `SettingsView.midiTab` con cabecera por
        grupo.
      - Tests: `PracticeCommandMidiTests` +2. 669 en verde.
- [x] **F.20** Editor: cue exacto en el cabezal + cues arrastrables
      - Feedback del autor (2026-09-04):
      - La **línea** del marcador de cue iba centrada bajo su etiqueta (VStack) →
        se veía descuadrada. Ahora la línea se pinta en la X exacta de
        `atSeconds` y la etiqueta va a su derecha.
      - `addCue`/`addLoop` usan `exactHeadSeconds` (posición del cabezal leída
        directa del motor, no el `headFraction` a 30 Hz).
      - Cada cue se **arrastra con el ratón**: zona de agarre de 16 px con un
        `DragGesture` de prioridad alta que mueve `atSeconds` (mapeado por la
        ventana visible / zoom); al soltar se re-ordenan.
      - 669 en verde.
- [x] **F.21** Editor de samples: elegir inicio y duración (ADR-068)
      - "Los samples para que funcionen bien deben tener un máximo de tiempo. En
        el editor se debe poder escoger el inicio y que se ajuste el tiempo del
        sample a usar."
      - `SampleEdit` (puro, `Codable`: `startSeconds` + `lengthSeconds` acotado a
        `AudioAsset.scratchMaxSeconds`, mín. 50 ms; `frameRange(...)`) +
        `SampleEditStore` (`sample-edits.json`, por ruta) + `AppModel.sampleEdits`.
      - `SampleEditorView` (`Screen.sampleEditor`, botón de ajustes en cada fila
        de la pestaña Samples): onda con zoom (`renderWindow`), ventana de
        recorte con dos asas arrastrables (inicio/fin, arrastrar el interior
        mueve toda la ventana), `◀/▶` de inicio y duración, "usar todo", y
        **"Escuchar el recorte"** en bucle (`EngineHandle.previewLoop` con el
        reproductor de la base a velocidad natural).
      - En la práctica, `loadScratchSample` usa `pcm[SampleEdit.frameRange]` si
        lo hay, si no `SampleTrim` (F.3). `LivePracticeView` gana `sampleEdit`;
        `MediaLibraryView` gana `onEditSample`.
      - Tests: `SampleEditTests` (4). 673 en verde.
- [x] **F.22** Cues/loops de la instrumental: visibles en la práctica + navegación MIDI (ADR-069)
      - Feedback del autor (2026-09-04):
      - Editor de samples: **detección de transitorios** (`TransientDetector`,
        puro — envolvente de energía + flujo positivo + umbral adaptativo +
        separación mínima). Marcas amarillas en la onda; botones "◀ / al más
        cercano / ▶" ponen el inicio sobre un ataque; el `◀/▶` de Inicio baja a
        5 ms para el ajuste fino.
      - Los **cues y la región de loop** del editor de instrumental ya se **ven**
        en la práctica: sobre la tira superior (`PracticeScene` gana
        `instrumentalCues` [fracciones] y `instrumentalLoopRegion`; `LivePracticeView`
        guarda `instrDownbeatSec` para mapear coords del fichero a la tira rotada).
      - **Navegación**, por botones en la zona inferior y **mapeable a MIDI**
        (`PracticeCommand` +5): `instrCuePrev`/`instrCueNext` (cue relativo al
        cabezal, en círculo) y `loopJump`/`loopPrev`/`loopNext` (recorren las
        regiones del editor y las aplican en caliente con
        `EngineHandle.setInstrumentalLoopRegion`). Aritmética pura en
        `InstrumentalNav` (testeada).
      - Tests: `TransientDetectorTests` (5), `InstrumentalNavTests` (7),
        `PracticeCommandMidiTests` +1. 686 en verde.
      - Iteración (mismo día):
      - **El loop no sonaba**: la región solo se aplicaba al motor en la rama
        "instrumental editada". Ahora se aplica tras el cascade en cualquier
        rama y `seekInstrumental` deja la base dentro del loop (inicio = "1").
      - **Interruptor de loop** (`loopToggle`) en la fila "Loops" y en la fila
        compacta de la base; arranca encendido si el editor dejó una región
        activa (`applyLoopRegion(0)` / `applyLoopRegion(nil)`).
      - **Aviso al cargar otra base**: se mutea la actual y sale un cartel
        "Cargando N…"; `instrLoadGen` descarta la carga si ya empezó otra.
      - **Logo (ADR-070)**: subidas de tono las partes casi negras del icono;
        `XFWordmark` rediseñado como miniatura del icono (se fundían con el
        tema oscuro).
      - **Rail del sample alineado con el teal**: la onda del rail iba en
        `0…hh` y su inicio quedaba pegado al borde inferior, con un hueco
        hasta la traza en reposo. Ahora usa el mismo mapeo que `traceY`
        (`railY(fraction:)`): f=0 cae exacto en el reposo del teal. El sprite
        va en un crop; la aguja no se recorta.
- [x] **F.23** Descomposición mano / fader en la práctica (ADR-071)
      - Así se enseña un flare: separando las manos. Tres modos en
        `PracticeSession.AssistMode` — `both` (normal), `hand` (tú el disco, la
        máquina corta), `fader` (la máquina mueve el disco, tú cortas). La
        máquina lleva la capa que sueltas, muestreada de la misma curva del
        patrón que la escucha (`ghostPosition`/`ghostFaderOpen`).
      - Ortogonal al "repite conmigo": en `listen` la máquina lleva las dos
        (`machineDrivesDisc`/`machineDrivesFader = crPhase == .listen || …`).
      - UI: sección "Manos" en el rail derecho (también Freestyle), insignia
        ámbar en la barra superior mientras el modo no es `both`, comando MIDI
        `assist_cycle` (categoría global). `setFaderClosed` (input) se ignora si
        la máquina lleva el fader; rutas internas por `applyFaderClosed`.
      - Casi toda la fontanería ya estaba: el fantasma del call & response ya
        movía las dos capas.
      - Tests: `PracticeSessionTests` +7, `PracticeCommandMidiTests` +1. 693 en verde.

### FUT — del cuaderno de 20 ideas (2026-09-04)

*Cada una es una sugerencia razonada; el plan detallado de F.24–F.30 está en
el artefacto de specs de interfaz. Nada de esto se toca hasta que la v1 esté
en manos de gente.*

- [ ] **F.24** Cinturón de clicks: micro-timing en vivo bajo la autopista `XFApp`
      - Se puede YA (sin B4.2): clicks objetivo de `PositionSampler.faderState`,
        los tuyos de las transiciones de `PracticeSession.faderClosed`. Tipo puro
        `LiveClickBelt` + vista con `Timer` propio (como `ClipMeterView`).
- [ ] **F.25** El fantasma puede ser tu mejor toma (o una importada) `XFApp` + `XFPersistence` (lect.)
      - Referencia, no marca que batir (anti-gamificación). `loadPlayback` ya
        reproduce un `.xfsession`; falta un `ghostSource .curve` en
        `PracticeScene` y persistir el blob de la mejor toma (fichero suelto = sin ADR).
- [ ] **F.26** Zoom en la autopista `XFApp`
      - `⌘±`/pellizco escalan `HighwayGeometry.pixelsPerBeat` (XFRender no se
        toca); `gridLines`/`gridLabels` ganan `subdivTicks` para la rejilla adaptativa.
- [ ] **F.27** El scope Lissajous, cableado `XFApp`
      - `ScopeLayout`/`ScopeScene`/`ScopeView` están **sellados y sin usar** en
        XFRender desde septiembre. Es instanciarlos en la práctica y en "Mi mesa".
- [ ] **F.28** Histograma polar del compás (pantalla de resultados) `XFApp`
      - Ángulo = fase dentro del compás, radio = desvío ms. El dato ya está en
        `Report.clickOffsets` (`targetTick` + `offsetMs`). Vista CoreGraphics/SKScene.
- [ ] **F.29** Paleta de comandos (⌘K) `XFApp`
      - Overlay `ZStack` + `NSEvent.addLocalMonitorForEvents` + filtro por
        subsecuencia sobre las listas de `AppModel`. Sin dependencias nuevas.
- [ ] **F.30** "Cómo se toca esto", animado (ficha del truco) `XFApp` + `data/`
      - Reutiliza `PracticeScene` en modo demo lento; campo `coaching:[{atTick,text}]`
        en el JSON del truco. Convierte `docs/NOTATION.md` en algo que se ve.
- [ ] **F.31** Freestyle → patrón `XFApp` + `XFNotation` (lect.)
      - Cuantiza extremos de la curva y bordes del fader a la rejilla, genera el
        XFN, lo mete en la librería. Cierra el círculo crear↔entrenar.
- [ ] **F.32** Doctor de señal: chequeo pre-vuelo de 5 s `XFApp` + `CXFTimecode`
      - Lissajous, SNR, dropout del bitstream, deriva del cut-in; veredicto en
        cristiano. Convierte `docs/HW_BRINGUP.md` en función permanente. Necesita mesa.
- [ ] **F.33** Calibración automática del cut-in point `XFApp` + `XFCapture`
      - El `audio_return` mide dónde empieza a sonar el fader con un tono piloto.
        La tabla de calibración por dispositivo YA existe en `XFPersistence`. Necesita mesa.
- [ ] **F.34** Salida multicanal: el metrónomo al cue, la música al máster `CXFAudioCore`
      - Canales 1-2 máster, 3-4 cue. El clic deja de aparecer en la mezcla y en
        el vídeo exportado. Arregla el vídeo gratis.
- [ ] **F.35** Packs `.xfpack` `XFApp`
      - Instrumental + samples + patrones + los `*-edits.json`. Se comparte por
        AirDrop/USB. Comunidad sin servidor; resuelve el copyright de samples.
- [ ] **F.36** Reloj MIDI, de entrada y de salida `XFCapture` + `CXFAudioCore`
      - Seguir o mandar un reloj MIDI externo. Cero dependencias nuevas: CoreMIDI
        ya está y comparte dominio de reloj con CoreAudio.
- [ ] **F.37** Un solo reloj `XFApp` + `CXFAudioCore`
      - `PracticeSession` deja de integrar tiempo: lee el tick del motor 1×/frame.
        Se muere el `Timer` de pared y `setMetronomeDrift`. ADR de calado. La
        simplificación estructural más grande que le queda al proyecto.
- [ ] **F.38** El fantasma no cambia de forma: solo se desplaza `XFApp`
      - Construir la curva una vez (2 periodos) y mover el nodo en X. Mismo truco
        de ADR-065 llevado a lo caro. Presupuesto de frame en el MacBook 2015.
- [ ] **F.39** Dejar de rotar el PCM de la instrumental `XFApp` + `CXFAudioCore`
      - Poner el desfase del "1" en el reproductor (`xf_player_set_playhead` /
        `loop_start`) en vez de copiar el fichero entero (~57 MB) en cada carga.
        `instrDownbeatSec` y `loopFraction` desaparecen. La deuda ya muerde (F.22).
- [ ] **F.40** Pirámide de picos en disco (el `.asd` de xFlare) `XFApp`
      - Multi-resolución de picos calculada una vez, junto a
        `instrumental-analysis.json`. Zoom del editor instantáneo, sin re-tocar
        el PCM. Es lo que hacen Ableton y Serato.
- [ ] **F.41** SIMD en la convolución + denormales apagadas de raíz `CXFAudioCore`
      - 32 taps = 8 `simd_float4` con FMA (`simd/simd.h` compila igual en las dos
        arquitecturas). FTZ/DAZ una vez al arrancar el hilo, no un parche por caso.
- [ ] **F.42** Puntuar lo que se OYE: cut-in point + restar la latencia `XFAnalysis` + `XFProfiles` (lect.)
      - El click audible es el cruce del cut-in, no la posición del dedo; y hay
        que restar la latencia medida en B1 o todos salen "tarde" por igual. La
        única que, si falta, hace falso el resto del producto. Escribirla ANTES
        de la primera sesión con hardware.

### FUT — del cuaderno del tacto (2026-09-04)

*Sensibilidad y tacto del audio. `F.43` ya está hecha; el resto en cola.*

- [x] **F.43** Tacto — 1ª tanda: latencia del gesto + frenado del plato (ADR-072)
      - **F.03** `PlatterInputView` ignora la inercia del trackpad
        (`momentumPhase != []`); era inercia doble (empujón fantasma + fricción).
      - **F.01** `LivePracticeView.pushPlatterVelocity()` empuja la velocidad al
        motor **en el instante del evento**, no en el paso de 60 Hz de la sesión.
      - **F.04** `AppSettings.defaultBufferFrames` = 128 (antes 512): −16 ms.
        La subida automática al detectar overloads sigue siendo B1.6.
      - **F.08** `PracticeSession.decayPlatterVelocity` añade rozamiento seco de
        Coulomb (`coulombFriction`): el plato para **en firme**, no se arrastra.
      - Tests: `PracticeSessionTests` +1. 694 en verde.
- [x] **F.44** Tacto: modelo de posición en vez de impulso `XFApp` (ADR-072 iter.)
      - El trackpad pasa de impulso (`scrollBy`) a **control de posición**:
        `PracticeSession.scrub(pointsPerSecond:)` fija `velocity = Δx/Δt ·
        scrubGain · sensibilidad`. `PlatterInputView` distingue mano puesta
        (`event.phase` .began/.changed/.stationary → `onScrub`, saca Δx/Δt de
        `event.timestamp`) de mano fuera (.ended/.cancelled → `onScrubEnd`).
      - `coastPlatter` no aplica fricción mientras `scrubbing` (+ auto-soltado a
        los 80 ms). **Parar la mano sin levantarla → el plato se para en seco**,
        como sujetar el vinilo. La rueda de ratón sigue con `scrollBy`.
      - Tests: `PracticeSessionTests` +4. 698 en verde.
- [x] **F.45** Tacto: más cubos de ratio de resampling, techo > 8× `CXFAudioCore` (ADR-072 iter.)
      - `XF_PLAYER_RATIOS` de 7 cubos a ojo (techo 8×) a **24 log-espaciados de
        1× a 16×** (salto relativo constante, ~12,7 %). Quita el escalón de
        brillo al barrer la velocidad y el sobre-filtrado de un scribble/crab
        que se pasaba de 8×. Coste RT igual (misma búsqueda acotada); la tabla
        (~1,5 MB) se calcula una vez al crear el player.
      - Test: `testAliasingSuprimidoPorEncimaDelTechoAntiguoDe8x` (v=12). 699 en verde.
- [x] **F.46** Tacto: rampa de velocidad dentro del bloque de audio `CXFAudioCore` (ADR-072 iter.)
      - `xf_player_render` pasa de una velocidad objetivo CONSTANTE por bloque a
        `(target_velocity_start, target_velocity_end)` interpolados en **rampa
        lineal** muestra a muestra (`start == end` = igual que antes). Con
        buffers grandes ya no hay un escalón que perseguir en cada frontera.
      - `xf_engine` guarda `prev_target_velocity` (solo hilo RT) y arma la rampa
        en el reproductor de scratch; la base instrumental sigue a velocidad
        constante (no scratchea). Con F.01/F.44 el objetivo ya llega a ritmo de
        evento, así que la rampa interpola valores que representan la mano.
      - Coste RT: cero (un `double` más por muestra).
      - Tests: `XFPlayerTests` +2. 701 en verde.
- [x] **F.47** Tacto: puerta de velocidad con forma, no con rampa `CXFAudioCore` (ADR-072 iter.)
      - La puerta pasa de rampa lineal (esquina dura en `av=gate`, se notaba en
        cada inversión de sentido) a **taper de coseno alzado** (pendiente cero
        en los dos extremos).
      - Dentro de la zona de puerta (`av < gate`, no fuera) un **bloqueador de
        DC** de un polo (corte ~38 Hz) quita el zumbido del cabezal casi
        quieto; el umbral por defecto baja de 0,12 a **0,04**.
      - **Regresión atrapada por los tests antes de commitear**: la 1ª versión
        aplicaba el bloqueador SIEMPRE que la puerta estaba configurada
        (también a velocidad normal), borrando el grave/casi-DC de cualquier
        sample — lo delató `XFEngineRTTests.testSoftClipYPicoDeSalida`.
        Arreglado: solo actúa dentro de la zona de puerta.
      - Tests: `XFPlayerTests` +3. 704 en verde.
- [x] **F.48** Tacto: compensar la latencia que declara el dispositivo `XFApp`
      - Leer `kAudioDevicePropertyLatency` + safety offset. Alimenta F.50, F.54 y
        el término a restar al puntuar (mitad de F.42). Clave con mesa.
      - Hecho (2026-09-04): `AudioDeviceLatency.swift` (mismo patrón de
        consulta CoreAudio que `AudioDeviceList`, no en `CXFAudioCore` — esto
        no es RT, son consultas puntuales del hilo principal). `info(for:scope:)`
        lee `kAudioDevicePropertyLatency` + `kAudioDevicePropertySafetyOffset`
        por lado (entrada/salida) y `kAudioDevicePropertyBufferFrameSize` +
        `kAudioDevicePropertyNominalSampleRate` del dispositivo entero; suma
        todo a `totalFrames`/`totalMs`. `nil` si el dispositivo no responde
        (algunos virtuales no exponen estas claves). 5 tests hardware-agnósticos
        (mismo patrón que `AudioDeviceListTests`): con el micrófono integrado si
        hay uno, con un id inventado, con casos numéricos fijos. Este es solo el
        dato medido — cablearlo al HUD/Ajustes (F.50) y a la resta al puntuar
        queda para cuando toquen esas tareas.
- [ ] **F.49** Tacto: grabar el gesto a resolución de audio `XFApp` + `XFCapture`
      - Hoy `recordFrame` va a 60 Hz; la toma reproducida y el vídeo salen más
        suaves y lentos que el original. Con F.01/F.43 la velocidad ya llega a
        ritmo de evento: grabar eso.
- [ ] **F.50** Tacto/UI: el reparto de la latencia en pantalla `XFApp` + `CXFAudioCore`
      - Panel en Ajustes › Tacto + línea en el HUD. Los 4 tramos se miden sin
        hardware. Sin la medida, todo lo demás es fe.
- [ ] **F.51** Tacto/UI: osciloscopio de velocidad (pedida vs. real) `XFApp`
      - Dos trazos: el objetivo (escalera de 60 Hz) y `xf_player_velocity`. Es el
        instrumento que le falta al slider de glide.
- [ ] **F.52** Tacto/UI: curva de respuesta del trackpad editable `XFApp`
      - Zona muerta + gamma + techo, gráfica arrastrable con un punto en vivo.
        Un plato no es lineal para la mano.
- [ ] **F.53** Tacto/UI: Ajustes › Tacto con presets y A/B instantáneo `XFApp`
      - Los 4 sliders de Debug ascienden a pestaña propia; presets (Seco/Vinilo/
        Suelto) y un A/B que alterna sin soltar el gesto. Presets por mesa.
- [ ] **F.54** Tacto/UI: compensar la latencia en lo que se DIBUJA `XFApp`
      - Desplazar la traza por la latencia medida (F.50): que ver y oír cuenten
        la misma historia. Una resta en la X de `renderUserTrace`.
- [ ] **F.55** Tacto/UI: la puerta de velocidad, visible en el rail `XFApp`
      - Banda/aro que se enciende mientras `|v|` está bajo el umbral: saber si el
        silencio es tuyo o de la app.
- [ ] **F.56** Tacto/UI: medidor de tirón (cuánto corrige el ancla) `XFApp` + `CXFAudioCore`
      - El trim del ancla anti-deriva respecto a su tope. Si vive saturado, hay
        algo mal aguas arriba y hoy no se ve.
- [ ] **F.57** Tacto/UI: inspector de un solo gesto (con `P`) `XFApp` + `CXFAudioCore`
      - Congelas y examinas el último segundo con detalle de audio: posición,
        velocidad pedida/real, fader, amplitud. Un analizador lógico para un baby.
- [ ] **F.58** Tacto/UI: ficha del dispositivo de audio con sus números `XFApp` + `CXFAudioCore`
      - Al lado del desplegable de buffer: ms, latencia declarada, safety offset,
        overloads, sample rate. Aviso si el ajuste no es el recomendado.
- [ ] **F.59** Tacto/UI: calibración del gesto (la app propone tus ajustes) `XFApp`
      - "Haz ocho babies al metrónomo": mide tu gesto y propone glide/puerta/
        fricción/sensibilidad, comparables en A/B (F.53).
- [x] **F.60** Elegir la PAREJA de canales dentro de un dispositivo, como Ableton `CXFAudioCore` `XFApp`
      - Motivado directamente por B5.5/B1.2 (2026-09-04): con la Rane 72 real
        (14 in / 10 out) el canal 1 casi nunca era el que hacía falta — hubo
        que barrer los 7 pares posibles a mano. El motor (`xf_engine.c`) y el
        asistente de calibración siempre cogían los dos primeros de cada
        lado, sin forma de elegir.
      - Hecho (2026-09-04):
        · `CXFAudioCore`: `xf_engine_start`/`xf_engine_start_output` ganan
          `input_channel`/`output_channel` (1-based, `<= 0` = por defecto).
          Aplican `kAudioOutputUnitProperty_ChannelMap` al arrancar (NO en el
          callback RT — es preparación del dispositivo, una vez). Los dos
          mapas tienen semántica y tamaño DISTINTOS (no es simétrico):
          entrada = tamaño 2 (canales de la app), `chanMap[app] = dispositivo`;
          salida = tamaño = canales del DISPOSITIVO, `chanMap[dispositivo] = app`
          (`-1` = silencio ahí). Mismo patrón ya validado hoy en
          `spike/b5-timecode/tcprobe.c --ch`.
        · `AudioDeviceList` (XFApp): `ChannelPair` + `stereoPairs`/
          `outputChannelPairs`/`inputChannelPairs` + `channelName` (consulta
          `kAudioObjectPropertyElementName` por canal) + `pairLabel` (funde
          "Analog 1 Left"/"Analog 1 Right" → "1-2 · Analog 1"; sin nombres o
          si no encajan, solo el rango "3-4"). `pairLabel` es `internal` a
          propósito para testearla directo, sin hardware.
        · `AppSettings`: `outputDeviceUID`/`outputChannel`/`inputDeviceUID`/
          `inputChannel` (persistidos, mismo patrón clave/valor que el resto).
        · `EngineHandle`: `preferredOutputDeviceUID`/`preferredOutputChannel`/
          `preferredInput*` — `start()`/`startOutput()` sin argumentos los
          usan solos; un argumento explícito los pisa. `AppModel` los
          sincroniza desde `settings` al construir y en cada cambio
          (`applyAudioDevicePreferences`).
        · `SettingsView` › Hardware: selector de dispositivo de
          Salida/Entrada + selector de PAREJA estéreo debajo (solo si el
          dispositivo tiene más de un par), con los nombres reales cuando la
          mesa los da. Nota honesta: la entrada todavía no captura de verdad
          (falta B4.2), esto deja el canal listo para cuando exista.
      - 15 tests nuevos (5 `AudioDeviceLatencyTests` de F.48 + 5 `AudioDeviceListTests`
        de parejas + los de compilación). Cambia el canal en Ajustes,
        aplica al reiniciar la práctica (como el buffer).
      - Pendiente, no bloquea: el paso 1 del asistente de calibración sigue
        con el picker de dispositivo antiguo, sin parejas — es un stub sin
        motor real detrás (B4.2) y duplicar ahí el selector es prematuro
        hasta que el asistente haga algo de verdad.
- [x] **F.61** El crossfader por MIDI llega de verdad a la práctica, no solo al perfil `XFCapture` `XFApp`
      - Motivado por la pregunta directa del autor tras F.60: "¿está
        configurado en todos los sitios necesarios?" — la respuesta, al
        auditar, era **no**. El perfil (ADR-021) y la lógica de captura
        (`MidiFaderSource`, sellada, probada con bytes sintéticos) estaban
        bien, pero **nada en `XFApp` abría CoreMIDI de verdad durante la
        práctica** — ni para el crossfader ni para los comandos discretos
        (cue/freeze/samples…, ADR-054). El único sitio que escuchaba CoreMIDI
        real era "MIDI Learn" de Ajustes, y solo mientras esa pantalla está
        abierta. `AppModel.midiCommands`/`ingest` ya llevaba un comentario
        diciendo "el conector CoreMIDI alimenta esto" — aspiracional, nadie
        lo llamaba.
      - Hecho (2026-09-04):
        · `MidiFaderSource` (XFCapture): `onChange: ((FaderSample) -> Void)?`,
          dispara solo cuando `isOpen` CAMBIA (no en cada CC — el crossfader
          manda decenas de mensajes/segundo mientras se mueve).
        · `AppModel`: `midiMonitor` (`MidiMonitorConnector`, un cliente
          CoreMIDI **aparte** de `midiLearn`, para toda la sesión de
          práctica, no solo Ajustes). Su `onMessage` reparte cada mensaje a
          `midiCommands.ingest(...)` Y a `crossfaderSource?.ingest(...)` — un
          mismo mensaje real puede ser, a la vez, candidato a comando
          discreto y a crossfader; cada decodificador filtra lo que no es
          suyo. `openMidiMonitor()` (llamado desde `AppModel.boot()`, NO
          desde `init`: los tests que construyen `AppModel` a mano no tocan
          CoreMIDI) abre el cliente real.
        · `rebuildCrossfaderSource()`: si el perfil activo tiene
          `crossfader.method = midi`, construye `MidiCrossfaderConfig(from:)`
          + `FaderBinarizer` — el `cutIn`/`hysteresis`/`hamster` salen de la
          **calibración guardada** (`XFPersistence.DeviceCalibration`) si
          existe, si no del `cut_in.left`/`hysteresis`/`reverse_default` del
          perfil como arranque razonable (no un número inventado aquí). Se
          reconstruye en el `didSet` de `activeProfileId`.
        · El cambio de estado del crossfader se reenvía como
          `practiceCommandEvents.send(.faderClosed(!isOpen))` — el MISMO
          evento que ya escucha `LivePracticeView.handleCommand`, cero
          cableado nuevo en la vista de práctica.
      - 7 tests nuevos: 2 en `MidiFaderSourceTests` (`onChange` dispara solo
        al cruzar el umbral, no con mensajes que ignora) + 5 en
        `AppModelMidiCrossfaderTests` (nuevo fichero: abre/cierra de verdad,
        no repite dentro de la histéresis, un perfil sin `method = midi`
        ignora los mismos bytes, cambiar de perfil desconecta el anterior, un
        mismo mensaje puede ser comando discreto Y crossfader). Todo
        verificable sin la mesa delante — se llama a
        `model.midiMonitor.onMessage?(status, data1, data2)` directo, sin
        abrir CoreMIDI real.
      - Pendiente, no bloquea: sin `DeviceCalibration` guardada (lo normal
        hoy, el asistente no cablea ese paso, B4.2) el `cutIn` es el del
        perfil sin calibrar — hay que verificar con la mesa delante que el
        umbral real (0,05) tiene sentido para el barrido de CC de la Rane 72
        (B1.4 dejó pendiente los extremos exactos).
- [x] **F.62** El scope de Calibración (paso 3, Timecode) lee el vinilo de verdad `XFApp`
      - Motivado por petición directa del autor: "quiero que se muestre el
        Scope View de la entrada de DVS... cómo el software está recibiendo
        y leyendo la señal de código de tiempo". El componente visual
        (`ScopeView`/`ScopeReading`/`ScopeFigure`, "el espejo del plato",
        `docs/UI_DESIGN.md` §3.3) ya existía en `XFRender`, sellado — se
        pintaba vacío porque nada le daba datos reales (mismo hueco B4.2 de
        siempre: el motor solo se había arrancado "solo salida" en toda la
        app, nunca capturando entrada de verdad).
      - Hecho (2026-09-04):
        · `AppModel.startTimecodeCapture()`: para el motor, lo reabre CON
          entrada (`engine.start()`, usa `EngineHandle.preferred*` de F.60 —
          canal elegido en Ajustes › Hardware), crea un `TimecodeMotionSource`
          (formato fijo `serato_2a`, el único validado contra hardware real
          en B5.5) y arranca un `Timer` a 30 Hz que drena
          `engine.drainInput()` → `submit(...)` → acumula `[ScopeReading]`
          (rastro acotado a ~8 s) y llama a `onTimecodeSample`.
        · `AppModel.stopTimecodeCapture()`: para todo y devuelve el motor a
          modo "solo salida" (listo para la próxima práctica). Idempotente.
        · `AppRootView`: al entrar en `.calibration`, cablea
          `model.onTimecodeSample` a `calibrationModel.reportTimecode(...)`
          (el mismo modelo que ya dibuja el asistente — `AppModel` no conoce
          `CalibrationWizardModel`, ADR-073) y llama a
          `startTimecodeCapture()`; al SALIR (con un flag `capturingTimecode`
          para no reiniciar el motor en cada cambio de pantalla sin motivo),
          `stopTimecodeCapture()`. `scopeReadings: { model.scopeReadings }`
          pasa a `CalibrationWizardView`.
        · `CalibrationStep.pendingNote` para `.timecode` pasa a `nil` (ya lee
          datos reales); nota corta en la UI avisando que hoy solo hay
          definición Serato 2ª ed.
      - 4 tests nuevos (`AppModelTimecodeCaptureTests`): sin motor no revienta
        ni deja lecturas, parar sin haber arrancado es no-op seguro,
        arrancar/parar repetido no revienta, `onTimecodeSample` no se llama
        sin motor. El comportamiento CON motor real (captura de verdad,
        drenaje, decode) no tiene test — como `xf_engine_start` y
        `MidiFaderConnector`, necesita hardware delante.
      - Pendiente, no bloquea: solo formato Serato 2ª ed. (sin selector de
        vinilo por perfil/UI); "detección automática de hamster" (el spec
        original de UI_DESIGN.md §3.1) sigue siendo manual — el toggle existe
        pero nada lo auto-sugiere todavía, solo la dirección (adelante/atrás)
        se detecta de verdad.
- [x] **F.63** Paso "Latencia" del asistente: declarada por el driver, no medida por loopback `XFApp`
      - Motivado por el autor tras ver el paso: "no le veo sentido, igual hay
        que eliminarlo". El diseño original (round-trip real por cable) tenía
        un problema real que F.62 dejó claro el mismo día: muchas mesas de
        batalla (la Rane 72 entre ellas) no tienen una forma clara de
        puentear salida y entrada — pedirle un cable a cualquier usuario en
        un asistente es mucha fricción para un dato que además ni siquiera
        sería el que el usuario realmente oye (B1.2 lo dejó documentado: un
        loopback mide DOS tramos USB, no el tramo único de salida).
      - Se ofrecieron 3 opciones (quitar el paso, dejarlo opcional, o
        sustituirlo por la latencia DECLARADA sin cable) — el autor eligió
        sustituirlo, reutilizando F.48 (`AudioDeviceLatency`, construido el
        mismo día) en vez de tirar el paso entero.
      - Hecho (2026-09-04):
        · `CalibrationWizardModel`: `measuredLatencyMs`/`reportLatency(roundTripMs:)`
          → `latencyMs`/`reportLatency(ms:)` (el nombre viejo afirmaba una
          medida que ya no se hace; deshonesto dejarlo).
        · `AudioDeviceList`: `resolvedOutput(uid:in:)`/`resolvedInput(uid:in:)`
          — el dispositivo elegido en Ajustes si existe, si no el de sistema
          por defecto (mismo criterio que usa el motor,
          `xf_engine_device_by_uid`).
        · `AudioDeviceLatency`: `outputInfo(for:)`/`inputInfo(for:)`,
          envoltorios fino sobre `info(for:scope:)` para no obligar a
          `AppRootView` a importar CoreAudio.
        · `AppRootView`: al entrar en `.calibration`, resuelve salida (+
          entrada si hay) y llama a `calibrationModel.reportLatency(ms:)` —
          automático, sin botón. `LatencyCalibrationStep` pierde el botón
          "Medir" y el aviso de "conecta un cable"; muestra el número y una
          nota corta de qué es (declarada, no medida).
        · `CalibrationStep`: instrucción y `pendingNote` del paso actualizados
          (ya no pide loopback ni remite a `measure_latency.py`).
      - 5 tests nuevos (`resolvedOutput`/`resolvedInput` con uid vacío/real/
        inventado, `outputInfo`/`inputInfo` coinciden con `info(for:scope:)`
        directo) + el test de latencia existente renombrado
        (`testLatenciaNoBloqueaPeroPideElDato`).
      - `tools/measure_latency.py` (medida real por loopback) no se toca —
        sigue viva como herramienta de desarrollo en `docs/HW_BRINGUP.md`
        paso 3, fuera de la UI de usuario final.
- [x] **F.64** El paso 1 (Audio) del asistente elegía dispositivo en una copia que no iba a ningún sitio `XFApp`
      - Motivado por el autor con la Rane 72 real conectada: "se queda
        atascado en latencia. No puedo seleccionar qué entrada estéreo tengo
        el timecode. No veo el Scope View." Las tres eran la misma causa.
        `AudioCalibrationStep` (paso 1) tenía Pickers de Entrada/Salida
        ligados a `CalibrationWizardModel.inputDeviceName`/`outputDeviceName`
        — una copia LOCAL a la vista que nunca llegaba a `AppSettings`. El
        motor (`EngineHandle.preferred*`, F.60) y el cálculo de latencia
        declarada (F.63) seguían leyendo `model.settings.outputDeviceUID`/
        `inputDeviceUID`, que solo se tocan desde Ajustes › Hardware — y ESE
        cálculo se hacía UNA vez, al entrar en la pantalla, sin recalcularse
        nunca. Si el dispositivo por defecto del sistema en ese instante no
        era la Rane 72 (lo normal: nadie pone su mesa de batalla como
        dispositivo por defecto de macOS), `latencyMs` se quedaba en `nil`
        para siempre → "Siguiente" deshabilitado para siempre → nunca se
        llegaba al paso 3, de ahí el Scope vacío. Y aunque se llegara, no
        había forma de elegir el PAR estéreo del timecode dentro de un
        dispositivo multicanal (F.60 solo lo exponía en Ajustes, no aquí) —
        con 14 canales de entrada en la Rane 72, adivinar no vale (B5.5).
      - Hecho (2026-09-04):
        · `CalibrationWizardModel`: `inputChannelFirst`/`outputChannelFirst`
          (`Int?`, primer canal 1-based del par elegido).
        · `AudioDeviceList.resolvedChannel(current:in:)` (nuevo, lógica
          pura): mantiene la elección si sigue siendo válida, si no cae al
          primer par — mismo patrón que `pairLabel`, testeable sin hardware.
        · `AudioCalibrationStep`: recibe `[AudioDeviceList.Device]` en vez de
          `[String]`; añade el selector de par estéreo (como en Ajustes)
          para entrada Y salida cuando el dispositivo tiene más de un par.
        · `AppRootView.applyCalibrationSelection()` (nuevo): al entrar en
          Calibración precarga el paso 1 con lo ya resuelto (Ajustes o
          sistema por defecto), y CUALQUIER cambio del usuario en dispositivo
          o canal (`.onChange` sobre los 4 campos) vuelca a
          `model.settings`, recalcula la latencia declarada Y reinicia la
          captura de timecode si el scope ya estaba activo — con guarda
          contra reescrituras/reinicios redundantes (comparando contra el
          valor actual antes de tocar `model.settings` o el motor).
      - 4 tests nuevos: `resolvedChannel` mantiene/cae/vacío (lógica pura,
        `AudioDeviceListTests`); los 10 de `CalibrationWizardTests` siguen
        verdes sin cambios (la nueva selección de canal no afecta
        `isReady`/`canAdvance`).
      - **Pendiente, no cerrado en esta tarea — freestyle no lee timecode
        real.** `.freeMode`/`.practice` (`LivePracticeView`) nunca llaman a
        `startTimecodeCapture()`: el movimiento sale de `PracticeSession`
        (ratón/trackpad/teclado), no del vinilo, esté calibrado o no. Es el
        hueco de B4.2 (motor RT definitivo con captura integrada en la
        práctica, todavía bloqueado — ver B4.2 más arriba), no un bug de esta
        pantalla; conectar timecode real a la práctica es un cambio mayor
        (toca `PracticeSession`/`LivePracticeView`, decide qué pasa con
        scoring/dropout) que se preguntó al autor antes de tocarlo.
- [x] **F.65** Vinilo real driving Freestyle/práctica (velocidad, no scoring todavía) `XFApp`
      - Motivado por el autor: quiere que Freestyle/práctica se muevan con el
        vinilo real, no solo ratón/trackpad — es el corazón de "hardware real
        primero" (CLAUDE.md §3.5).
      - **Hecho:** `PracticeSession.pushRealVelocity(_:sampleDurationSeconds:)`
        — a diferencia de `scrub`/`scrollBy`/`nudge` (ganancia "humana" para
        ratón/trackpad), el DVS ya trae la velocidad exacta
        (`MotionSample.velocity`, 1.0 = 33⅓ rpm nominal): mover el vinilo a
        ritmo normal avanza el sample cargado al mismo ritmo. Deshace
        exactamente la conversión que hace `normalizedVelocity` (verificado
        por álgebra + test: `normalizedVelocity * sampleDurationSeconds ==
        ratio`, así que tras volver a pasar por el `onAdvance` de
        `LivePracticeView`, `engine.setVelocity` recibe el ratio real
        intacto). Reutiliza `scrubbing`/`lastScrubAt` de `scrub()`: si el
        vinilo deja de mandar muestras > 80 ms (aguja levantada, dropout de
        B5.5), la fricción sintética retoma sola. Se ignora si la máquina
        lleva el disco (`machineDrivesDisc`, F.23), igual que el resto de
        inputs. 5 tests nuevos en `PracticeSessionTests` (identidad tras
        `normalizedVelocity`, escala con ratio/duración, no frena entre
        muestras, se ignora con la máquina al mando, duración 0 no revienta).
      - **Encontrado durante el diseño — carrera real en el motor.**
        `LivePracticeView.loadInstrumental(initial: true)` llama a
        `engine.startOutput()` sin condición al terminar de cargar la base
        (async); si algo abriera el motor en modo dúplex (con entrada) antes,
        esta llamada lo revertiría a "solo salida" segundos después, matando
        la captura en silencio. Hay que resolver esto ANTES de cablear la
        captura real a la práctica.
      - **Decisión del autor:** la práctica solo intenta modo dúplex si hay
        un dispositivo de ENTRADA configurado (`AppSettings.inputDeviceUID`
        no vacío, vía el paso 1 del asistente o Ajustes › Hardware) — no
        siempre, para no pedir permiso de micrófono a quien practica sin
        mesa.
      - **Cerrado (2026-09-05).** `AppModel.motionSampleEvents`
        (`PassthroughSubject<MotionSample, Never>`, nuevo) — mismo tráfico
        que `onTimecodeSample` pero como publisher: `pollTimecode()` envía a
        los dos. `LivePracticeView` gana `captureRealTimecode`/
        `motionSamples`/`startRealCapture`/`stopRealCapture`; se suscribe con
        `.onReceive(motionSamples)` → `receiveRealMotion(_:)` (confianza
        ≥ 0.6, mismo umbral que el paso Timecode del asistente; si no,
        ignora la muestra y deja que la fricción sintética frene sola).
        `AppRootView` pasa `captureRealTimecode: !model.settings.
        inputDeviceUID.isEmpty` (la decisión del autor: solo dúplex con
        entrada configurada) y cablea `startRealCapture`/`stopRealCapture` a
        `model.startTimecodeCapture()`/`stopTimecodeCapture()`, en las DOS
        pantallas (`.practice` y `.freeMode`).
      - **Carrera resuelta:** `loadInstrumental(initial: true)` ya NO llama a
        `engine.startOutput()` sin condición — si `captureRealTimecode`,
        llama a `startRealCapture()` en su lugar (un solo sitio decide el
        modo del motor, no dos). `stop()`/`.onDisappear` para la captura
        SOLO si se pudo haber arrancado (si no, `stopTimecodeCapture()`
        haría un `stop()`+`startOutput()` de más en cualquier salida de la
        práctica sin mesa).
      - Tests: `PracticeSessionTests` (F.65, turno anterior) + 1 nuevo en
        `AppModelTimecodeCaptureTests` (`motionSampleEvents` no dispara sin
        motor, mismo criterio que `onTimecodeSample`). El comportamiento con
        motor real (¿suena bien la velocidad real en la mesa?) sigue sin
        test — necesita hardware delante, como el resto del host de audio.
        `make verify` en verde.
- [x] **F.66** Quitar el paso de latencia del asistente de calibración (petición directa) `XFApp`
      - El autor pidió directamente quitar el paso "Prueba de latencia" del
        asistente: "no le veo sentido" — no daba pie a ninguna acción dentro
        del propio flujo (a diferencia de Timecode/Fader, que sí terminan en
        un ajuste guardado).
      - Hecho (2026-09-05): `CalibrationStep` pasa de 4 a 3 casos
        (`audio`/`timecode`/`fader`, sin `.latency`). `CalibrationWizardModel`
        pierde `latencyMs`/`reportLatency`/`latencyVerdict`; `result()` ya no
        pasa `latencyMs` a `DeviceCalibration` (queda `nil`, el campo sigue
        existiendo en `XFPersistence` para calibraciones antiguas — no se
        toca ese módulo). `LatencyCalibrationStep` (vista) y `LatencyVerdict`
        (tipo, sin más usos) se borran. `AppRootView` pierde
        `refreshDeclaredLatency()` y la llamada a `AudioDeviceLatency` en la
        selección del paso 1; `AudioDeviceLatency` (F.48) se queda intacta
        para otros usos (F.50, compensar al puntuar).
      - Tests: `CalibrationWizardTests` reescrito sin los casos de latencia
        (8 tests, antes 10). `make verify` en verde.
- [x] **F.67** El paso "Fader" cuenta cortes reales + "Aprender MIDI del fader" `XFCapture` `XFApp`
      - Motivado por el autor: "vamos a continuar con la parte del fader y
        los cortes en la calibración" y, acto seguido: "debe haber un botón
        de aprender midi del fader, al pulsar debes mover el fader a izq y a
        der para detectar el rango completo y aprender qué CC es el fader" —
        como el selector de audio de Ableton pero para MIDI: no asumir el
        `cc`/canal que declare el perfil (si es que declara alguno), sino
        descubrirlo observando el aparato real, igual que ADR-021 lo
        descubrió a mano para la Rane 72 (5 min moviendo *solo* el
        crossfader).
      - Hecho (2026-09-05):
        · `XFCapture`: `MidiFaderLearner` (nuevo, puro) — agrupa el tráfico
          CC por `(canal, cc)` mientras se arma, y `bestGuess(minSpan:)`
          devuelve el que más rango ha barrido (con `minSpan` para que el
          ruido de un botón cercano no gane por casualidad), desempatando
          por número de mensajes. `bestSpanSoFar` da el progreso en vivo.
          7 tests.
        · `AppModel`: nuevo hook `onRawMidiMessage` (mismo patrón que
          `onTimecodeSample`) — ve TODO el tráfico MIDI, sin filtrar, para
          que el asistente pueda "aprender" sin que `AppModel` conozca
          `CalibrationWizardModel` (ADR-073).
        · **Arreglado de paso, no buscado:** `midiMonitor.onMessage` mutaba
          `@Published`/enviaba a `PassthroughSubject` **desde el hilo de
          CoreMIDI**, no el principal — `MidiLearnModel` (F.59) ya lo hacía
          bien con un comentario explícito sobre esto; `AppModel` se había
          quedado sin el `DispatchQueue.main.async` correspondiente desde
          F.61. Con hardware real de por medio (justo lo que se estaba
          probando) esto es una fuente real de corrupción/crash, no solo
          teórica — se corrige aquí. Los 5 tests de
          `AppModelMidiCrossfaderTests` que llamaban a `onMessage?()` y
          afirmaban en el mismo tick necesitaron un `flushMain()` (vacía la
          cola principal con una `expectation`) para seguir siendo
          deterministas.
        · `CalibrationWizardModel`: `startFaderLearn`/`reportFaderLearnProgress`/
          `reportLearnedFader`/`cancelFaderLearn` + estado publicado
          (`faderLearning`, `faderLearnSpan`, `learnedFaderChannel`/`CC`/
          `Min`/`Max`). Aprender con éxito **reinicia `cutsDetected`**: los
          cortes contados antes de aprender pudieron ir contra el CC
          equivocado.
        · `AppRootView`: `rebuildFaderConfig()` prioriza lo aprendido en
          esta sesión sobre lo que declare el perfil (mismo criterio que
          `AppModel.rebuildCrossfaderSource`); `handleCalibrationMidi(...)`
          reparte cada mensaje real al `MidiFaderLearner` (mientras se
          aprende) o al `FaderBinarizer` en vivo (si no), contando un corte
          cada vez que `isOpen` CAMBIA. Los sliders de cutIn/histéresis y el
          CC aprendido reconstruyen el binarizador al vuelo
          (`.onChange`) — mover un slider durante la calibración se nota
          en el acto en el conteo de cortes, no hace falta salir y volver a
          entrar.
        · `CalibrationStepViews`: botón "Aprender MIDI del fader" + barra de
          progreso del rango barrido + "Listo"; muestra el CC/canal
          aprendido o avisa de que usa el del perfil. `CalibrationStep.
          pendingNote` para `.fader` se retira (ya detecta cortes de
          verdad, el aviso de "usa el monitor MIDI de HW_BRINGUP" quedó
          obsoleto).
      - **Pendiente, no cerrado aquí:** lo aprendido vive solo en la sesión
        de calibración (`CalibrationWizardModel`) — no se persiste en
        `DeviceCalibration` (XFPersistence no tiene campos para
        canal/cc/rango MIDI todavía) ni se usa en
        `AppModel.rebuildCrossfaderSource` para la práctica real. Guardarlo
        de verdad es un cambio de otro módulo (`XFPersistence` + su schema
        GRDB) — se pregunta antes de tocarlo.
      - Tests: 7 en `MidiFaderLearnerTests` + 4 en `CalibrationWizardTests`
        + 1 en `AppModelMidiCrossfaderTests` (`onRawMidiMessage`). `make
        verify` en verde.
- [x] **F.68** Salida separada de scratch y base instrumental (dos pares de canales) `CXFAudioCore` `XFApp`
      - Motivado por el autor: con mesa de batalla real, quiere sacar el
        scratch y la instrumental por DOS pares de canales del mismo
        dispositivo — como dos tiras de un mezclador real (Deck 1/Deck 2),
        no una mezcla ya hecha por un único par. ADR-075.
      - Hecho (2026-09-05): `xf_engine_render` gana `out_instr_l`/
        `out_instr_r` (además de `out_scratch_l`/`r`); el modo lo decide la
        propia llamada — los CUATRO punteros no-nulos = separado (dos buses
        independientes, cada uno con su soft-clip); falta cualquiera de los
        dos de la base = combinado (bit a bit igual que antes, verificado
        con test). `xf_engine_start`/`xf_engine_start_output` ganan
        `instrumental_channel` (`<= 0` o igual al del scratch = combinado,
        ASBD de 2 canales; distinto = separado, ASBD de 4 canales no
        intercalados + `ChannelMap` de dos pares). La CAPTURA de entrada se
        queda SIEMPRE en 2 canales — el modo separado es solo de salida.
        `EngineHandle.preferredInstrumentalOutputChannel` +
        `AppSettings.instrumentalOutputChannel` (`0` = combinado), picker
        nuevo en Ajustes › Hardware ("Canal de la instrumental") junto al de
        salida existente.
      - **Pendiente, no cerrado aquí:** no verificado por hardware con los
        oídos (RT-safe, no se puede probar sin escuchar la mesa real).
      - **Paso Audio del asistente (2026-09-05, mismo día):** el selector de
        "Canal de la instrumental" también aparece en el paso 1 del
        asistente (antes solo en Ajustes), con "Combinado" como opción
        explícita — a diferencia del canal de entrada/salida (que cae al
        primer par si el guardado ya no es válido), aquí si el par elegido
        deja de existir en el dispositivo actual cae a `nil` (combinado),
        no al primer par: saltar a otro par sin pedirlo sería peor sorpresa
        que volver al comportamiento de siempre.
      - Tests: `XFEngineSplitOutputTests` (nuevo, 4: aísla scratch/base,
        metrónomo con la base en separado, cae a combinado si falta un
        puntero, combinado sigue igual que antes) + 3 en `AppSettingsTests`
        (por defecto combinado, ida y vuelta, negativo se acota a 0). Todos
        los call-sites existentes de `xf_engine_render`/`xf_engine_start*`
        actualizados (`TakeAudioRenderer`, `EngineHandle.renderBlock`,
        `XFEngineRTTests`, `XFEngineInstrumentalTests`). `make verify` en
        verde.
- [x] **F.69** Botón "Reiniciar cortes" en el paso Fader del asistente `XFApp`
      - Motivado por el autor: quiere poder repetir los diez cortes con otro
        ajuste de cutIn/histéresis sin salir del paso.
      - Hecho (2026-09-05): `CalibrationWizardModel.resetFaderCuts()` vuelve
        `cutsDetected` a 0 SIN tocar `faderCutIn`/`faderHysteresis` (los
        sliders no se mueven solos). Botón junto al contador, solo visible
        con `cutsDetected > 0`.
      - Tests: `testReiniciarCortesVuelveA0SinTocarLosSliders`. `make
        verify` en verde.

- [x] **F.70** El plato para en firme con el timecode real; silencio (no clamp) antes del principio del sample `CXFAudioCore` `XFApp`
      - Reportado por el autor tras probar con la Rane 72 real: (1) al parar
        el vinilo, "el teal" seguía moviéndose un rato más — debía moverse
        EXCLUSIVAMENTE con el timecode; (2) al scratchear hacia atrás del
        principio del sample, la posición se clavaba en 0 en vez de un
        "silencio infinito" — sin eso hay deriva y se pierde la referencia
        con el vinilo real.
      - Hecho (2026-09-05, ADR-076): `PracticeSession` separa
        `timecodeDriving`/`lastTimecodeAt` de `scrubbing`/`lastScrubAt`
        (F.44) — al cortarse la señal real (>80 ms) el plato para EN FIRME,
        sin la fricción sintética de F.08 (esa la conserva el trackpad). El
        tope de abajo de `coastPlatter` pasa de `posLo` a
        `posLoFloor = posLo - patternSpan·2.5` (mismo margen que `posHi`):
        ningún scratch real lo alcanza, solo frena el martilleo sintético de
        `scrollBy`. En el motor RT, `xf_player.c` deja de saturar el cabezal
        por abajo (sin bucle); la convolución ya devolvía silencio fuera de
        `[0, last]`, solo hacía falta un `floor()` de verdad para el cabezal
        negativo (antes truncaba, asumiendo que siempre era >= 0).
      - Tests: 2 en `XFPlayerTests` (cabezal negativo + vuelta exacta al
        mismo frame) + 2 en `PracticeSessionTests` (parada en firme +
        preserva la referencia). `make verify` en verde, 766 tests.
      - Pendiente: confirmar "con los oídos" en la Rane 72 real.

- [x] **F.71** Botón "Refrescar dispositivos" en el paso Audio del asistente `XFApp`
      - Encontrado investigando el bug del picker de instrumental
        "desaparecido": la lista de CoreAudio del asistente solo se
        refresca al ENTRAR en Calibración; si el driver de la mesa tiene un
        hipo justo tras un replug de USB mientras ya estabas dentro, te
        quedas con la foto vieja (menos pares de salida de los que hay de
        verdad) sin ningún cambio de pantalla que la refresque sola.
      - Hecho (2026-09-05): botón que re-enumera `AudioDeviceList.all()` y
        vuelve a aplicar la selección, sin salir del asistente.

- [x] **F.72** La calibración del fader se guarda de una sesión a otra; el teal ya baja también en pantalla `XFPersistence` `XFApp`
      - Reportado por el autor probando F.70/F.71 en la Rane 72: (1) el
        picker de instrumental (F.71) resultó ser build vieja, resuelto solo
        relanzando; (2) "la calibración no se guarda de una vez a otra"; (3)
        "el teal sigue sin poder pasar de abajo" pese a F.70.
      - (3), causa real: `PracticeScene.traceY` (SpriteKit) recortaba la
        posición normalizada a `max(-0.1, n)` — una tolerancia de redondeo de
        cuando `PracticeSession` clavaba la posición a 0; con ese clamp ya
        quitado (F.70) se quedaba "pegada" cerca del principio en vez de
        seguir bajando. Arreglado a `max(-4.0, n)`, simétrico con el
        `min(4.0, n)` de arriba.
      - (2), causa real (dos partes, ninguna en `AppSettings` — eso ya
        persistía bien): `CalibrationWizardModel.result()` guarda con
        `deviceKey` = UID del dispositivo de salida, pero
        `AppModel.rebuildCrossfaderSource()` LEÍA con `deviceKey:
        activeProfileId` (el perfil `.conf`, otra clave) — la calibración
        guardada nunca se encontraba al leer. Además nadie precargaba el
        asistente con lo ya guardado al volver a entrar.
      - Hecho (2026-09-05, ADR-077, permiso del autor para tocar
        `XFPersistence` sellado): `rebuildCrossfaderSource()` busca por
        `settings.outputDeviceUID` (se relanza también si ese UID cambia);
        `AppRootView.applyCalibrationSelection()` fija
        `calibrationModel.deviceKey` al UID resuelto y precarga el
        asistente (`CalibrationWizardModel.applyLoaded`) una vez por
        dispositivo. Migración `v2` en `XFPersistence` (v1 intacta): 4
        columnas NULLABLE en `deviceCalibration` para el CC MIDI
        **aprendido** (F.67), que antes solo vivía en memoria durante la
        sesión — `rebuildCrossfaderSource` ahora también lo usa sobre el del
        perfil.
      - Tests: 2 en `CalibrationTests` (XFPersistence) + 4 en
        `CalibrationWizardTests` + 2 en `AppModelMidiCrossfaderTests`
        (discriminan explícitamente "lee por UID, no por perfil" y "el CC
        aprendido manda sobre el del perfil"). `make verify` en verde, 774
        tests.
      - Pendiente: confirmar "con los oídos" en la Rane 72 real.

- [x] **F.73** Más hueco debajo de la onda del patrón, para ver el scratch antes del principio del sample `XFApp`
      - Reportado por el autor probando en la Rane 72: "cuando scratcheo el
        principio del sample no se ve en la autopista" — `PracticeSession`
        ya integraba posiciones negativas (F.70) y `traceY` ya las mapeaba
        sin recortar (F.72), pero `curveInset: 8` (el margen entre la onda
        del patrón y el borde de la autopista, en las dos llamadas a
        `HighwayGeometry` de `AppRootView`) dejaba solo 16 puntos de hueco
        real antes del recorte del `SKCropNode` — cualquier bajada, por
        pequeña que fuera, desaparecía casi al instante.
      - Hecho (2026-09-05): `curveInset` sube de 8 a 48 en los dos sitios
        (práctica y Freestyle). `laneHeight` NO se toca (es el alto real del
        carril de fader, otra cosa). Con el margen nuevo, un scratch real
        hacia atrás del principio queda visible antes de salirse por abajo.
      - Sin test dedicado (parámetro de layout, no lógica) — `make verify`
        en verde, 774 tests (sin cambios de conteo).
      - Pendiente: confirmar "con los ojos" en la Rane 72 real.

- [x] **F.74** "Sticker drift" — el plato sigue la posición del decoder, no una velocidad reintegrada `XFApp`
      - Pedido por el autor (sin poder probar en la Rane 72 en el momento):
        "revisa el código para evitar el sticker drift del vinilo".
      - Causa real encontrada revisando `PracticeSession.pushRealVelocity`
        (F.65/F.70): solo recibía `MotionSample.velocity` y reintegraba la
        posición ella misma a 60 Hz, sujetando la última velocidad conocida
        entre dos muestras — `AppModel` sondea el decoder a 30 Hz
        (`pollTimecode`, ~33 ms), así que un scratch rápido que cupiera
        entero en esa ventana se aproximaba mal. `MotionSample.position`
        (segundos-nominales acumulados por `xf_timecoder.c` **por bloque de
        audio**, 1-3 ms — mucho más fino) ya existía y no se usaba para
        nada: se tiraba la posición exacta del decoder para recalcular una
        peor a mano.
      - Hecho (2026-09-05, ADR-078): `pushRealVelocity(_:sampleDurationSeconds:)`
        pasa a `pushRealMotion(position:velocity:sampleDurationSeconds:)`. Un
        ancla (`realMotionAnchorRevolutions`/`realMotionAnchorPlatterPosition`),
        fijada en la primera muestra real de cada racha, hace que cada
        muestra siguiente recalcule `platterPosition` con un ÚNICO salto
        desde el ancla — no una cadena de sumas que pudiera acumular error.
        `coastPlatter` sigue interpolando a 60 Hz entre dos muestras reales
        (para que la traza no dé saltos), pero cada muestra real CORRIGE esa
        interpolación: el error nunca tiene más de ~33 ms para acumularse.
        Al soltar el ancla (corte de señal, F.70) se reancla fresca al
        volver la señal, sin saltar con una referencia vieja.
        `LivePracticeView.onAdvance` ya mandaba la posición al motor de
        audio como ancla anti-deriva (`engine.setScratchTarget`, ADR-042) —
        la corrección llega también al audio SIN TOCAR el motor RT.
      - Tests: 9 en `PracticeSessionTests` (renombrados de `pushRealVelocity`
        a `pushRealMotion`, + 2 nuevos: sigue la posición del decoder sin
        acumular error, y re-ancla sin saltar tras un corte de señal).
        `make verify` en verde, 776 tests.
      - Pendiente: confirmar "con los ojos" en la Rane 72 real.

- [x] **F.75** El ancla de posición del audio pasa a ser afinable (el trim por defecto puede no dar abasto con timecode real) `CXFAudioCore` `XFApp`
      - Tras probar F.74 en la Rane 72, el autor reportó que el "sticker
        drift" seguía: "hay zona que se ve la onda y no suena y conforme se
        desplaza el sonido luego suena en zonas que no hay onda. La parte
        del dibujo de la onda debe cuadrar perfecto con el teal".
      - Causa real: F.74 arregló la autopista (ya fiel al decoder), pero
        el AUDIO tiene su propio "ancla" separada (`xf_player`'s
        `target_playhead`, ADR-042) — un trim deliberadamente LENTO Y
        ACOTADO (~250 ms, tope 0,015 frames/muestra ≈ 1,5 % de pitch),
        afinado para una fuente RUIDOSA (ratón: una corrección agresiva
        se oiría como un barrido). Antes de F.74, `PracticeSession`
        reintegraba la posición con el MISMO tipo de aproximación que el
        motor RT (velocidad sujeta ~33 ms) — los dos lados compartían el
        error, así que "parecían" ir sincronizados aunque los dos
        estuvieran mal respecto al vinilo real. Al arreglar SOLO el lado
        visual, el motor RT se quedó con su aproximación de siempre: con
        timecode real (posición EXACTA, no una estimación) ese trim lento
        puede no dar abasto en un scratch continuo y rápido.
      - Hecho (2026-09-05, ADR-079): `xf_player_set_seek_trim(ms, max_trim)`
        (nuevo, mismo patrón que `set_glide_ms`/`set_speed_gate`) +
        `xf_engine_set_scratch_seek_trim` (guarda + aplica al player en
        curso, se reaplica al cargar un sample nuevo). `AppSettings` gana
        `scratchSeekTrimMs`/`scratchSeekMaxTrim`; sección nueva "Ancla de
        posición (timecode real)" en Ajustes › Debug; `LivePracticeView`
        lo aplica al abrir la práctica como el resto del "tacto" del
        plato. Los *defaults* NO cambian (250 ms/0,015) — sin poder
        verificar por oído, se deja el punto de partida conservador y se
        expone para que el autor lo afine él mismo en la mesa real.
      - Tests: 1 en `XFEngineRTTests` (el tope configurable corrige más
        con un `max_trim` más alto, pero sigue acotado al nuevo tope) + 1
        en `AppSettingsTests` (ida y vuelta + acotado). `make verify` en
        verde, 778 tests.
      - Pendiente: el autor prueba distintos valores de "Tiempo"/"Fuerza"
        en la Rane 72 real; si encuentra uno que cierra el hueco sin
        click, ese valor debería volver como el nuevo *default*.

- [x] **F.76** Medidor de deriva del vinilo (Fase 0 de `docs/TIMECODE_DRIFT.md`) `CXFTimecode` `XFCapture` `CXFAudioCore` `XFApp`
      - El autor pidió un PLAN para acabar con el "sticker drift" de una
        vez (tres rondas — F.70/F.74/F.75 — atacándolo por síntoma, sin
        poder medirlo nunca). Plan completo en `docs/TIMECODE_DRIFT.md`,
        confirmado por el autor: fase 0 (instrumentar) + fase 1 (cerrar
        fugas) primero, con permiso para el ADR de la fase 2 (tocar
        `CXFTimecode`, sellado) cuando llegue.
      - Diagnóstico (con fichero y línea, no hipótesis): el vinilo lleva
        grabado un bitstream de posición ABSOLUTA que xwax ya decodifica
        (`timecoder_get_position`) — `xf_timecode.c:98` lo llama y **tira
        el valor**, solo mira si es `>= 0` para la confianza. Lo que sí se
        usa (`xf_timecoder_position()`) es una INTEGRAL de la estimación
        de velocidad, que puede acumular sesgo sin límite. Además: el ring
        de entrada pierde frames en silencio si el sondeo a 30 Hz del
        hilo principal no drena a tiempo, y el contador de esas pérdidas
        (`input_ring_drops`) existía desde siempre sin getter — nadie lo
        había leído nunca.
      - Hecho (2026-09-05, ADR-080, permiso del autor para tocar
        `CXFTimecode`/`XFCapture` sellados — aditivo, sin tocar nada
        existente): `xf_timecoder_absolute_position`/`xf_timecoder_locked`
        (segundos nominales, misma unidad que la integral, para restar
        directo) + `TimecodeMotionSource.absoluteLock` +
        `xf_engine_input_ring_drop_count` (getter nuevo del contador que
        ya existía). `AppModel.timecodeDriftMs`/`timecodeLockedFraction`
        se calculan en `pollTimecode()` y se enseñan en el paso Timecode
        del asistente junto al scope, con los frames perdidos del ring.
      - Tests: 2 en `CXFTimecodeTests` + 1 en `TimecodeMotionSourceTests`
        (confirman que la cuadratura sintética, sin LFSR real, nunca se
        da por enganchada — B5.5 ya validó el enganche con vinilo real) +
        1 en `XFEngineRTTests` (el ring cuenta lo que pierde sin drenar) +
        1 en `AppModelTimecodeCaptureTests`. `make verify` en verde, 783
        tests.
      - Pendiente (Fase 1, aprobada): cerrar las fugas ya diagnosticadas
        en `docs/TIMECODE_DRIFT.md` (gate de confianza, watchdog, ring
        fuera del hilo principal) — se hace con números reales de la
        Rane 72 en la mano, no a ciegas. El autor prueba esta build y
        trae la lectura de "Deriva"/"Enganchado"/"Frames perdidos" del
        paso Timecode.
      - **Corrección el mismo día:** la primera versión del medidor daba
        "−136567 ms" en la Rane 72 real — un bug del propio cálculo, no
        deriva de verdad. Comparaba `sample.position` (arranca en 0 al
        crear el motor) contra la posición absoluta (vive en el reloj del
        vinilo FÍSICO, un disco de ~712 s — dondequiera que esté la
        aguja) sin anclar los ceros primero: lo que medía era la posición
        de la aguja en el disco, no una deriva acumulada. Arreglado con el
        mismo patrón de ancla que ADR-078:
        `AppModel.timecodeDrift(integratedNow:absoluteNow:anchor:)`
        (función `static` pura, extraída para poder testearla sin
        hardware) fija `(integrada, absoluta)` en el primer enganche y
        compara los DELTAS desde ahí. 4 tests nuevos — uno reproduce el
        bug exacto (misma posición absoluta enorme, cero separación real
        → el resultado tiene que dar ~0). `make verify` en verde, 787
        tests.

- [x] **F.77** El ring de entrada del timecode se drena fuera del hilo principal (primer arreglo de Fase 1) `XFApp`
      - Con el medidor de F.76 ya arreglado, el autor probó en la Rane 72
        real: solo girando el disco, sin scratchear — **deriva −95,7 ms,
        99 % enganchado, 977 frames perdidos**. Tras unos scratches —
        **deriva −3170,7 ms, 60 % enganchado, 1433 frames perdidos**.
      - Diagnóstico: 977 frames perdidos SIN SCRATCHEAR SIQUIERA es la
        pista decisiva — el `Timer` de `pollTimecode()` en `RunLoop.main`
        (30 Hz) competía con el redibujado de SwiftUI/SpriteKit por el
        hilo principal y perdía; con solo ~85 ms de capacidad en el ring
        (32 bloques de 128 frames a 48 kHz), cualquier retraso de la UI
        más largo que eso pierde frames de vinilo real PARA SIEMPRE —
        nunca llegan a `xf_timecoder_submit`. Cada frame perdido es
        movimiento que la integral de `xf_timecoder_position()` jamás ve:
        se queda corta frente a la posición absoluta, de ahí la deriva
        negativa y creciente. Explica el síntoma original sin que haga
        falta ni un scratch.
      - Hecho (2026-09-05, ADR-081): `drainTimecode()` (antes
        `pollTimecode()`) pasa a `timecodeDrainQueue` (cola serial
        dedicada, QoS `.userInitiated`) con un `DispatchSourceTimer` a
        100 Hz (10 ms, antes 30 Hz) — con ~85 ms de margen en el ring,
        deja de sobra colchón frente al jitter de una cola que ya no
        compite con la UI. Solo `applyTimecodeSample(_:lock:)` sigue en
        el hilo principal (toda la mutación `@Published`, sin cambios de
        comportamiento), vía `DispatchQueue.main.async`.
        `stopTimecodeCapture()` cancela el timer con `.sync` en la MISMA
        cola antes de tocar `timecodeSource` — sin eso, parar la captura
        mientras el timer dispara sería una carrera de datos real.
      - Sin test nuevo (el comportamiento real necesita CoreAudio con un
        dispositivo delante, como el resto de este fichero) — `make
        verify` en verde, 787 tests (sin cambio de conteo).
      - Pendiente: el autor vuelve a probar en la Rane 72 y trae los
        números nuevos de "Frames perdidos"/"Deriva". Si bajan mucho,
        confirma que esta era la fuga dominante; si queda deriva de
        fondo, el siguiente sospechoso es el sesgo del filtro de pitch de
        xwax durante aceleraciones (diagnóstico B de
        `docs/TIMECODE_DRIFT.md`), que solo se cierra con la Fase 2
        (fusión con la posición absoluta).

---

## Reglas de uso

- No se empieza un bloque sin cerrar el anterior.
- Una tarea no esta hecha hasta que `make verify` esta en verde.
- Las tareas **SELLAR** son el momento en que el modulo deja de poder romperse.
- Se desarrolla y se prueba en el MacBook Pro Intel de 2015. Es la maquina de referencia.
- El binario es universal desde B0.6. arm64 se cubre con CI, no con hardware.
- Si aparece trabajo nuevo, va a FUTURIBLES por defecto.
