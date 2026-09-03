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
- [ ] **B5.5** **SELLAR CXFTimecode** `CXFTimecode`
      - Bloqueado por hardware: los tests usan señal de cuadratura **sintética** (validan el modo relativo contra el contrato de xwax). Antes de congelar hay que pasar **un vinilo de timecode real** por un interface y comprobar enganche, escala de velocidad y dropout con la aguja de verdad.
      - **Listo para el día del hardware:** `spike/b5-timecode/tcprobe` (compila 2026-09-02) abre la entrada, la pasa por `xf_timecoder` y muestra vel/pos/conf/dir en vivo. Procedimiento en `docs/HW_BRINGUP.md` paso 6.

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
        22 tests (12 MIDI + 5 envolvente + los HID de antes). Falta la corrida con la Rane 72; el conector tambien es la ruta HID (respaldo de la 72). `docs/DEVICE_PROFILES.md` §3 documenta las claves `hid.*`; los perfiles rane-72 y djm-s11 llevan el bloque HID comentado.
- [x] **B6.4b** AudioReturnFaderSource: tono piloto y deteccion (ADR-021) `XFCapture`
      - Criterio: funciona con el perfil rane-seventy-two
      - Hecho (2026-09-01): `AudioReturnFaderSource` conforma `FaderSource`. `submit(pcm:frames:hostTime:)` (PCM estereo del retorno del master, se drena del ring buffer como `TimecodeMotionSource`) corre un **Goertzel** de un bin (19,5 kHz, hop de 64 muestras, bin entero: 26), normaliza contra el nivel de piloto con el fader abierto (auto-max con fuga lenta + `calibrate(openLevel:)`), y pasa el valor continuo al `FaderBinarizer` de B6.5 (cut-in + histeresis, ADR-017) que resuelve `isOpen`. Devuelve los flancos por hop. Guarda muestras sueltas entre submits; `pilotLevel` para un medidor. 9 tests con **piloto sintetico** modulado en amplitud (como `--selfcheck` del spike): detecta apertura/cierre, 0 eventos fantasma en 1 s de fader quieto con ruido, hamster, calibracion, hostTime por hop. Falta la corrida con la Rane 72.
- [x] **B6.5** Binarizacion del fader con cut-in calibrado e histeresis (ADR-017) `XFCapture`
      - Criterio: 0 eventos fantasma en 1 min de fader quieto
      - Hecho: `FaderBinarizer` — disparador de Schmitt alrededor de `cutIn` con banda `hysteresis`; flag `hamster` para reverse (ADR-008). `binarize([(hostTime,value)]) -> [FaderSample]`, conserva estado entre llamadas. Test: 60.000 lecturas con ruido ±0,03 y banda 0,08 → **0 transiciones**.
- [x] **B6.6** Formato .xfsession: grabar y reproducir + ReplaySource `XFCapture`
      - Criterio: una sesion grabada se reproduce bit a bit igual
      - Hecho: `XFSession` (JSON Lines: cabecera de calibración + muestras). Los floats se guardan como **cadena** (`"\(x)"`) para ida y vuelta exacta — el `JSONEncoder` de esta toolchain no re-parsea el mismo bit en un `Double` (problema de ADR-028). `ReplayMotionSource` / `ReplayFaderSource` conforman los protocolos y avanzan con `seek(toHostTime:)` (reloj de audio, determinista). Ida y vuelta value-equal + re-encode estable. `clockMap` reconstruye el `ClockMap` de la toma. 15 tests.
- [ ] **B6.7** **SELLAR XFCapture** `XFCapture`
      - Bloqueado por B6.3 (timecode), B6.4/B6.4b (conectores CoreMIDI / IOHIDManager / audio). Hecho ya: protocolos (B6.1), teclado (B6.2), binarizador (B6.5), .xfsession + replay (B6.6), decodificación HID. 32 tests.

## B7 — XFDesign + XFRender

*Que se vea, y que se vea bien.*

- [x] **B7.1** Tokens de diseno de UI_DESIGN.md seccion 2 `XFDesign`
      - Hecho: `XFColor` (paleta de §2, `Color(hex:)`), `XFSpacing` (4/8/12/16/24/32/48), `XFRadius` (10/16/24), `XFStroke`, `XFFont` (title/body/mono — `design: .monospaced` para cifras a ancho fijo, sin `monospacedDigit()` que es macOS 12), `HitLevel` (escala de acierto: color **+ forma** por daltonismo, `init(absOffsetMs:)` con las ventanas de SCORING.md).
- [x] **B7.2** Componentes base: tarjeta, boton, stepper de BPM, badge de acierto `XFDesign`
      - Hecho: `XFCard` (superficie + radio 16 + borde 1px, `raised` para modales), `XFButtonStyle` (.filled/.bordered, radio 10, easeOut 180 ms), `BPMStepper` (`‹ 80 BPM ›`, número monoespaciado, respeta `range`), `HitBadge` + `HitShape` (dibuja círculo lleno/círculo/rombo/triángulo/cruz según el nivel). 7 tests: valores de token, clasificación de `HitLevel`, formas distintas, los componentes se construyen. macOS 11.
- [ ] **B7.2b** Render sincronizado al refresco real, 60 fps garantizados en Intel (ADR-024) `XFRender`
      - Criterio: 60 fps estables en el MacBook Pro 2015 con la autopista completa
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
      - Hecho (2026-09-01): `make seal M=XFDesign` (7 tests) y `make seal M=XFRender` (34 tests) en verde. `Sources/XFRender/README.md` escrito; `Sources/XFDesign/README.md` actualizado a SEALED. `Package.swift` excluye el README de XFRender. `docs/MODULE_STATUS.md` → ambos SEALED 2026-09-01, `apiVersion = 1`. **ADR-036** (layout puro + escena delgada, sincronizacion al reloj de AUDIO, golden SVG, Lissajous reconstruido). **B7.2b** queda pendiente: es medir fps en las dos maquinas + `SKView`, aditivo, no cambia contrato.

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
      - Estado: **versión sintética completa** (`ReplayScoringTests` + `SyntheticTake` generan el `Take` desde el patrón). La batería good/late/sloppy corre ahora contra **un patrón representativo de cada nivel 1-4** (forward-cut L1, transformer-2 L2, flare-1c L3, flare-2c L4), no solo el flare: good → ≥0.85 y 3★, late(+35 ms) → sesgo (no dispersión), sloppy(±45 ms) → dispersión + peor puntuación con margen, clicks perdidos contados. Invariante fija: good ≫ sloppy en cada patrón. **Falta**: `.xfsession` grabados reales (hardware) — `<patrón>__good/late/sloppy` — para cerrar la tarea y desbloquear B8.8.
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
- [x] **B11.4** Pantalla de resultados con diagnostico `XFApp`
      - Hecho (2026-09-01): junto con B11.13. `ResultsSummary` (puro) traduce lo que calculo `XFAnalysis` a texto: 3 filas de estrella (las apagadas con su condicion, sacada de `starReasons` por prefijo `★`/`★★`/`★★★` y sin el `Titulo:`, o la condicion por defecto si aun no toca), puntuacion `3.840 / 4.800` (millares con punto), `%`, badge Record, frases del coach en orden. `ResultsView` SwiftUI con las estrellas escalonadas. 6 tests.
- [x] **B11.5** Modo libre con grabacion de los ultimos 30 s `XFApp`
      - Hecho (2026-09-01): `FreeModeRecorder` (clase) — buffer rodante de `MotionSample`/`FaderSample`: al llegar una muestra tira las que caen fuera de la ventana de 30 s. No mira el reloj (el driver pasa cada muestra con su `hostTime`). `snapshot` para guardar como `.xfsession`, `durationSeconds`, `reset()`. `FreeModeView` SwiftUI (sin fantasma, indicador de grabacion, boton Guardar). 5 tests.
- [x] **B11.6** Navegador de la libreria `XFApp`
      - Hecho (2026-09-01): `LibraryEntry` (scratch + estado de bloqueo, `init(scratch:isUnlocked:)`) + `LibraryBrowser` (puro): `levels`/`families`, `filtered(query:level:family:onlyUnlocked:)` (busqueda por subcadena sin mayusculas ni acentos), `groupedByLevel(...)`. `LibraryView` SwiftUI con buscador y filtro de familia. 6 tests.
- [x] **B11.7** Ajustes `XFApp`
      - Hecho (2026-09-01): `AppSettings` (envoltorio tipado de la tabla clave/valor `setting`): hamster, metronomo, buffer 64/128, escala de tolerancia (0.5..2.0), alto contraste, reducir movimiento. `init(raw:)` tolera claves ausentes o ilegibles (caen al default) y recorta rangos; `.raw` para guardar. `SettingsView` SwiftUI (Form). Todo local (CLAUDE.md 3). 5 tests.
- [x] **B11.8** Accesibilidad: VoiceOver, alto contraste, teclado `XFApp`
      - Criterio: segun UI_DESIGN.md seccion 4
      - Hecho (2026-09-01): `A11y.Palette` (alto contraste: ghost al 60%, trazos mas gruesos — XFDesign esta sellado, esto va encima). `A11y.resultsDescription` (resumen de resultados para VoiceOver: N/3 estrellas, puntuacion sin leer la barra, mejor marca, que falta, diagnosticos) y `highwayLiveAnnouncement` (region en vivo con el resumen de compas). Atajos de teclado en `PracticeView` (flechas=BPM, Esc=salir) y `ResultsView` (R=otra vez). 4 tests.
- [x] **B11.9** Pantalla Mi mesa: lista de perfiles, insignias y prueba en vivo `XFApp`
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

- [~] **B12a.0** Empaquetar recursos en el bundle `XFApp`
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
        {MacOS,Resources}` y hace `cp -R data profiles` a `Contents/Resources/`;
        `make dmg` lo empaqueta. **Falta**: smoke test lanzando la app desde
        `/Applications` (o el DMG) sin el repo delante — acción manual, como la
        parte de hardware.
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
        RELEASE UNIVERSAL (verificado: el `.app` del DMG da `Mach-O universal
        (x86_64 arm64)`, `Signature=adhoc`). `xFlare-<version>.dmg` ~45 MB.
      - **Falta**: publicarlo en GitHub Releases (acción manual / CI, ver
        `docs/RELEASE.md` §3).
      - Al cerrarlo del todo, marcar B12a.0 como hecho.
- [x] **B12a.5** Nota de release
      - Hecho (2026-09-03): `docs/RELEASE.md` — lista de comprobación pre-flight,
        cómo construir (`make universal` + `make dmg REL=1`), cómo publicar
        (`gh release create`), y la **plantilla del texto de la nota** con el
        rodeo de Gatekeeper (clic derecho → Abrir / `xattr -dr
        com.apple.quarantine`) y el enlace al tag exacto del fuente (GPL-3.0).
- [ ] **B12a.6** README publico, capturas, video de 30 s
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

- [~] **F.0** Calentamiento adaptativo con deteccion de oxidacion (ADR-027)
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
        10 tests (`WarmupPlannerTests`).
      - Falta: la **pantalla** de calentamiento (flujo de N pases, botón de
        saltar) y engancharla al arranque de sesión.
- [ ] **F.0b** Variantes avanzadas: encadenado, densidad creciente, rampa de tempo, un solo lado `XFNotation`
      - Criterio: docs/VARIANTS.md seccion 4
- [ ] **F.1** Dos platos: juggling, chasing, notacion de doble carril
- [ ] **F.2** Pads y sampler; scratch sobre pads
- [~] **F.3** Importar tus propios samples con deteccion del punto cero
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
      - Falta (cuando toque): puntos de cue por sample, biblioteca de samples
        del usuario, deteccion de tempo/loop si el sample es ritmico.
- [~] **F.4** Exportar la toma como video vertical para compartir
      - Criterio: el bucle de crecimiento mas barato que existe
      - Iniciado (2026-09-03): **vídeo hecho** (sin audio todavía).
        `TakeVideoExporter` (XFApp): `framePlan(...)` (los `currentTick` de cada
        fotograma) y `trace(from: XFSession)` (la línea grabada al dominio de
        ticks del patrón) son puros; `render(HighwayFrame → CGImage)` rasteriza
        con Core Graphics (rejilla, fantasma partido por fader, **tu línea
        teñida por acierto**, marcas ○/●, phantom clicks); `export(...)` monta
        el mp4 H.264 9:16 con `AVAssetWriter` en segundo plano. Botón
        **"Vídeo…"** en el panel "Grabar línea". 5 tests, incluido un export
        real a fichero temporal verificado con `AVURLAsset` (pista de vídeo,
        tamaño y duración).
      - Falta: **audio** (necesita un render offline del motor siguiendo la
        traza grabada), y quizá una barra de progreso.
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
