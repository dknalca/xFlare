# CLAUDE.md — xFlare

> Contexto permanente del proyecto. Léelo entero antes de tocar código.
> Si una instrucción puntual contradice este documento, **pregunta antes de asumir**.
> Última actualización: 2026-08-31
>
> **Nota de versiones.** Las secciones 1-13 son la redacción original (2026-08-27).
> Los addenda del final (v0.2 a v0.6) y este bloque las corrigen donde difieren:
> plataforma **macOS 11.0** (no 14), toolchain **Swift 5.7.2 / Xcode 14.2**,
> layout **SPM** (no `xcodeproj`), puerta de latencia **por máquina** (ADR-024),
> hardware de referencia **Rane Seventy-Two MK1**. Ante duda, mandan los addenda.

---

## 1. Qué es xFlare

xFlare es un **entrenador de scratch / turntablism para macOS**.

Es, en esencia, "Synthesia para scratch": el usuario ve descender por pantalla el
movimiento objetivo del vinilo y los cortes de crossfader, los ejecuta con sus
platos y su mesa de batalla reales, y la app mide la precisión y le explica **qué**
está haciendo mal — no sólo cuánto.

**Entrada:** timecode de vinilo (señal de audio analógica capturada por USB) +
posición del crossfader. En mesas de batalla como la Rane 72 el crossfader **no
expone su posición por MIDI** (ADR-021): el método primario es `audio_return` con
tono piloto sobre el retorno USB del máster; MIDI CC solo si la mesa lo ofrece.
**Salida:** sample scratcheado + pista instrumental + metrónomo.

---

## 2. Usuario objetivo

DJ turntablista con hardware real: dos platos, vinilos de timecode y una mesa de
batalla (referencia: **Rane Seventy-Two MK1**). Sabe lo que es un flare. No
necesita que le expliquen qué es un crossfader. Quiere practicar mejor, no jugar.

**No es el usuario objetivo:** el principiante absoluto sin hardware, ni el
usuario de controlador de fiesta.

---

## 3. Principios de producto — NO NEGOCIABLES

1. **La latencia manda sobre todo lo demás.** Si una feature compromete el
   presupuesto de latencia, la feature se cae. Sin discusión.
2. **Anti-gamificación.** Nada de rachas, vidas, monedas, confeti ni presión
   artificial. Melodics falla justo aquí. Feedback sobrio, informativo, adulto.
3. **Soberanía del usuario.** Sin cuenta, sin nube, sin telemetría, sin conexión.
   Funciona en un avión. Los datos son ficheros locales que el usuario puede copiar.
4. **Enseñar, no puntuar.** Un "78%" no enseña nada. "Tu click de vuelta llega
   15 ms tarde" sí. Toda métrica debe ser accionable.
5. **Hardware real primero.** El ratón y el jog MIDI existen sólo para poder
   desarrollar sin la mesa delante. El ciudadano de primera es el timecode.

---

## 4. Restricciones duras

| Restricción | Valor |
|---|---|
| Plataforma | **macOS 11.0 Big Sur mínimo.** Universal Intel + Apple Silicon. Nada de Windows, Linux, iOS ni Catalyst (ADR-022) |
| Toolchain | **Xcode 14.2 / Swift 5.7.2**, `swift-tools-version: 5.7` (ADR-023). `swift build` y `swift test` OK en local (el crash de `swift test` de ADR-029 se resolvio el 2026-08-31 completando el primer arranque de Xcode 14.2). toolchain swift.org 5.8.1 instalada como red (compila mas rapido de perfilar) |
| Latencia total plato → altavoz | Tabla por máquina (ADR-024): **≤ 10 ms** en la máquina de referencia, **≤ 15 ms** aceptable en el Intel de 2015. Objetivo 7 ms |
| Buffer de audio | 64 frames @ 48 kHz (1,33 ms), adaptable a 128 al detectar overloads (ADR-024) |
| Licencia del proyecto | **GPL-3.0-only** (impuesta por xwax 1.10 — ver DECISIONS ADR-003 y ADR-030) |
| Distribución | DMG notarizado + Homebrew. **La Mac App Store está descartada** |
| Dependencias de red | **Ninguna en runtime.** Ni una |

### Presupuesto de latencia (orientativo)

```
captura USB      1,5 ms
decode timecode  2,0 ms
proceso + mezcla 1,5 ms
salida USB       1,5 ms
driver/HAL       3,0 ms
─────────────────────────
TOTAL           ~9,5 ms  ← techo en la máquina de referencia
```

En el MacBook Pro Intel de 2015 el techo real es **≤ 15 ms** con buffer de 128
frames (ADR-024). Ver la tabla por máquina en `docs/PLATFORM_SUPPORT.md` §7.
Cualquier PR que suba estos números necesita justificación explícita.

---

## 5. Stack

| Capa | Tecnología | Por qué |
|---|---|---|
| UI | **SwiftUI** | Declarativo, rápido de iterar |
| Highway + scope | **SpriteKit** | 120 fps sin pelearse con Metal. Metal es la vía de escape si el profiling lo exige |
| Audio RT | **CoreAudio** (AudioUnit / HAL) en **C/C++17** | Único camino a <10 ms |
| Decode timecode | **xwax `timecoder.c`** vendorizado | Probado contra Serato CV02, Traktor MK1, MixVibes |
| MIDI | **CoreMIDI** | Timestamps en el mismo dominio de reloj que CoreAudio |
| Persistencia | **SQLite** vía GRDB (MIT) | Fichero local, copiable |
| Prototipado | **Python 3.11** en `tools/` | Iterar scoring y DSP en minutos, no en horas |

### Reparto de lenguajes

- **Swift ≈ 80%** — todo lo que no corre en el hilo de audio.
- **C / C++17 ≈ 20%** — exclusivamente el hilo de tiempo real.
- **Puente:** bridging header. Sin FFI, sin bindings generados, sin ceremonia.

---

## 6. Estructura del repositorio

Layout **Swift Package Manager**: un target por módulo, el grafo de `Package.swift`
es la arquitectura (ver `docs/ARCHITECTURE.md`). No hay `.xcodeproj` con lógica
dentro; el proyecto Xcode, cuando exista, será una cáscara fina que solo empaqueta
`XFApp`. Así Claude Code compila y testea desde terminal sin abrir Xcode.

```
xFlare/
├── CLAUDE.md                  ← este fichero
├── PLAN.md                    ← plan estratégico (MVP + iteraciones)
├── TODO.md                    ← backlog táctico por bloques (empezar aquí)
├── README.md
├── LICENSE                    ← GPL-3.0-only (ver LICENSE-TODO.md)
├── Package.swift              ← define los 13 targets y el grafo de dependencias
├── Makefile                   ← verify, test, seal, status, golden-update, universal
├── docs/                      ← DECISIONS, ARCHITECTURE, NOTATION, CURRICULUM, ...
├── Sources/
│   ├── CXFAudioCore/          C  · ring buffer SPSC, callback CoreAudio RT-safe
│   ├── CXFTimecode/           C  · wrapper xf_timecode + vendor/xwax/ INTACTO
│   ├── XFClock/               Swift · reloj musical, PPQ 480, transporte
│   ├── XFNotation/            Swift · modelo XFN, compositor mano×fader
│   ├── XFProfiles/            Swift · parser .conf de mesa, herencia, autodetección
│   ├── XFCapture/             Swift · MotionSource / FaderSource, binarización fader
│   ├── XFAnalysis/            Swift · DTW, emparejado de clicks, scoring (puro)
│   ├── XFPersistence/         Swift · GRDB 6.x, sesiones, progreso
│   ├── XFEngine/              Swift · máquina de estados de la sesión
│   ├── XFDesign/              Swift · tokens y componentes SwiftUI
│   ├── XFRender/              Swift · escena SpriteKit: autopista, scope
│   ├── XFApp/                 Swift · pantallas, navegación, ciclo de vida
│   └── XFTestKit/             Swift · fixtures, fuentes falsas, helpers de golden
├── Tests/                     ← un target <Módulo>Tests por módulo
├── Fixtures/
│   ├── sessions/              .xfsession grabados (replay tests)
│   └── golden/                SVG/JSON de referencia
├── data/                      JSON: primitivas, librería, currículo, schemas
├── profiles/                  .conf de mesa (CC0-1.0, no GPL)
├── tools/                     Python · prototipado y validación (NO va en la app)
└── preview/                   SVG/PNG de la notación XFN
```

---

## 7. ⚠️ Reglas de oro del hilo de audio

**Esta es la sección más importante del documento.** Todo lo que viva bajo
`Sources/RT/` corre cada 1,33 ms en un hilo de prioridad de tiempo real. Si lo
violas, el usuario oye clicks y la app es basura.

### Prohibido dentro del callback de audio

- ❌ `malloc`, `free`, `new`, `delete` — **cero reservas de memoria**
- ❌ Mutex, semáforos, `lock`, cualquier espera bloqueante
- ❌ Llamadas al sistema: ficheros, red, `printf`, logging
- ❌ **Cualquier código Swift.** ARC puede reservar memoria de forma impredecible.
      Apple lo desaconseja explícitamente. La frontera es sagrada.
- ❌ Excepciones, RTTI, `std::string`, `std::vector` (crecen ⇒ reservan)
- ❌ Bucles de duración no acotada

### Obligatorio

- ✅ Todos los búferes preasignados en la inicialización
- ✅ Comunicación con el resto de la app **sólo** por ring buffers SPSC lock-free
      o variables atómicas
- ✅ Coste computacional acotado y predecible en el peor caso
- ✅ Si necesitas avisar de algo, encola un evento; no lo proceses ahí

### El patrón correcto

```
[hilo RT en C]  ──eventos──▶  ring buffer  ──▶  [Swift, hilo normal]
                                                  scoring, UI, disco
[hilo RT en C]  ◀──params──   atómicas     ◀──   [Swift, hilo normal]
```

---

## 8. Convenciones de código

### Swift
- **Swift 5.7.2** (toolchain fijada, ADR-023). `async`/`await` y actores sí; nada
  de callbacks anidados. **Sin** macros, *parameter packs*, Observation/`@Observable`
  ni concurrencia estricta de Swift 6. Lista de APIs prohibidas: `docs/PLATFORM_SUPPORT.md` §4
- `struct` por defecto; `class` sólo cuando hace falta identidad
- Nada de force unwrap (`!`) salvo en tests
- Un tipo por fichero, nombre del fichero = nombre del tipo
- Nombres en **inglés** en el código; comentarios en **español**

### C / C++
- C11 o C++17. Nada de C++ moderno exótico en la capa RT
- Prefijo `xf_` en todos los símbolos públicos de C
- `static` para todo lo que no cruce el fichero
- Cada función RT lleva en su cabecera: `/* RT-SAFE */` o `/* NO RT-SAFE */`
- El código vendorizado de xwax **no se modifica**. Si hace falta adaptarlo, se
  hace en un wrapper propio y se documenta en `docs/TIMECODE.md`

---

## 9. Nivel del autor — lee esto antes de escribir

El autor (xFlare) tiene:
- **Swift: 0.** Parte de cero.
- **C/C++: nivel universitario + Arduino.** Entiende punteros, búferes, structs,
  bucles. No conoce C++ moderno, templates ni metaprogramación.
- **Python: algo de experiencia.**

### En consecuencia

1. **Comenta el *porqué*, no el *qué*.** `i += 1 // incrementa i` es ruido.
   `// avanzamos 1 frame porque el timecoder consume mono, no estéreo` es útil.
2. **La capa RT lleva comentarios densos.** Cada bloque no obvio necesita 2-3
   líneas explicando la intención y por qué es RT-safe.
3. **Al introducir un patrón de Swift nuevo** (property wrappers, actors,
   `@Observable`, protocolos con associated types), añade un comentario de 2
   líneas explicando qué hace y por qué se usa aquí.
4. **Evita la magia.** Entre una solución elegante e inescrutable y una explícita
   y algo más larga, elige la explícita. El autor tiene que poder leer esto.
5. **Nada de código sin explicación.** Al terminar una tarea, resume en 3-5
   líneas qué has hecho y qué debería mirar el autor.

---

## 10. Comandos

> El proyecto es **SPM** (no `.xcodeproj`, ver addenda v0.2). Se compila y testea
> desde terminal.

```bash
# Build / tests (todo o un modulo)
swift build
make verify                 # build + lint + perfiles + tests (gate para cerrar tarea)
make test                   # tests estrictos
make test M=XFClock         # solo un modulo
swift test --filter XFClockTests

# Empaquetar la app / el DMG
make app                    # xFlare.app (debug)
make dmg REL=1              # xFlare-<version>.dmg (release universal, para Releases)
make universal && make archs  # verifica los dos slices (x86_64 + arm64)

# Estado del backlog
make status

# Prototipado Python
cd tools && python3 -m venv .venv && source .venv/bin/activate && pip install -r requirements.txt

# Medición de latencia (bloque B1 — script propio; ver docs/HW_BRINGUP.md)
python3 tools/measure_latency.py

# Profiling de tiempo real
# Instruments → plantilla "Audio System Trace". Buscar overloads del hilo RT.
```

---

## 11. Glosario de scratch

Necesitas esto para entender los requisitos. No inventes terminología.

| Término | Significado |
|---|---|
| **Timecode** | Vinilo con señal de audio codificada (senoidales en cuadratura + bitstream de posición). No es MIDI |
| **DVS** | Digital Vinyl System. Controlar audio digital con vinilos de timecode |
| **Modo relativo** | Sólo velocidad y dirección. **El que usa xFlare** |
| **Modo absoluto** | Además, posición de la aguja en el disco. No lo usamos |
| **Click** | Apertura o cierre del crossfader. Evento discreto y puntuable |
| **Cut-in point** | Posición del fader donde el sonido empieza a oírse. Varía por mesa y curva |
| **Hamster / reverse** | Crossfader invertido. **El autor corta en reverse** |
| **Sentence** | Frase de scratch completa; también un sample largo con una frase hablada |
| **Baby** | Adelante-atrás sin fader. El scratch fundamental |
| **Chirp** | Cierre del fader al inicio del movimiento y apertura al volver |
| **Stab** | Empujón rápido hacia adelante con el fader abierto |
| **Tear** | Movimiento partido en 2 o 3 tramos de velocidad distinta |
| **Transformer** | Movimiento continuo troceado abriendo y cerrando el fader |
| **Flare** | El fader parte **abierto** y se cierra brevemente 1, 2 o 3 veces por movimiento |
| **Orbit** | Flare aplicado en ambas direcciones del movimiento |
| **Crab** | Cierres múltiples usando varios dedos contra el pulgar |
| **Scribble** | Movimiento muy rápido y corto, con tensión del antebrazo |
| **TTM** | Turntablist Transcription Methodology. Notación: curva de movimiento + carril de fader |
| **Scope Lissajous** | Figura circular del timecode. Diagnóstico estándar de la señal |

---

## 12. Qué NO hacer

- ❌ **No añadas dependencias** sin consultarlo. Cada una es riesgo de licencia
      (el proyecto es GPL-3.0-only, ADR-030) y de latencia.
- ⚠️ **JUCE:** su opción libre es GPLv3, así que ya **no es incompatible** con la
      licencia. Aun así no se usa: la UI es SwiftUI. No lo metas sin ADR.
- ✅ **Apache-2.0 ahora vale** (es compatible con GPLv3). MIT y BSD también.
      Sigue haciendo falta un ADR para cualquier dependencia nueva.
- ❌ **No escribas Swift en el hilo de audio.** Nunca. Bajo ningún concepto.
- ❌ **No implementes red, cuentas, ranking ni social.** Fuera de alcance.
- ❌ **No añadas gamificación.** Ni rachas, ni XP, ni logros, ni confeti.
- ❌ **No te adelantes de fase.** Cada fase de `PLAN.md` lleva una sección
      "No hacer en esta fase". Respétala.
- ❌ **No modifiques el código vendorizado de xwax.** Envuélvelo.
- ❌ **No incluyas samples con copyright.** Ni "Ahhh", ni "Fresh", ni nada
      procedente de discos comerciales.

---

## 13. Flujo de trabajo esperado

1. Lee la fase actual en `PLAN.md`.
2. Marca la tarea que vas a abordar.
3. Implementa **una tarea cada vez**. No agrupes.
4. Comprueba el criterio de aceptación de forma verificable.
5. Marca el checkbox y resume en 3-5 líneas qué debe revisar el autor.
6. Si tomas una decisión técnica no trivial, **añádela a `docs/DECISIONS.md`**
   con su fecha, contexto, alternativas y consecuencias.


---

# Reglas de modularidad (anadido v0.2)

Estas reglas estan por encima de cualquier otra consideracion de comodidad.
Detalle completo en `docs/ARCHITECTURE.md`.

## Antes de empezar cualquier tarea

1. Abre `TODO.md` y coge **la primera tarea no hecha del bloque activo**. No elijas
   la que te parezca mas interesante.
2. Consulta `docs/MODULE_STATUS.md`.
3. Confirma en voz alta que modulo vas a tocar y cual es el criterio de aceptacion.

## Durante

- **Se toca UN modulo por tarea.** Si necesitas modificar otro, PARA y preguntame.
- **Un modulo `SEALED` no se modifica.** Ni "solo esta linea". Si de verdad hace
  falta, para y pideme un ADR.
- **Los tests de un modulo sellado son inmutables.** Si un test sellado se pone rojo,
  el fallo esta en tu codigo nuevo, no en el test. No lo edites.
- Nada sube de capa. `XFAnalysis` jamas importa `XFCapture`; recibe datos ya
  capturados. Si te hace falta, el diseno esta mal: para y preguntame.
- Dentro del callback de audio: solo C, sin malloc, sin locks, sin ARC, sin logs.
- Lo que no sea API publica es `internal`. `public` es un contrato para siempre.

## Antes de decir que has terminado

1. `make verify` en verde. Sin excepciones ni "esto ya lo arreglo luego".
2. Actualiza el estado en `TODO.md` y en `data/backlog.json`.
3. Si la tarea era SELLAR: `make seal M=XFxxx`, escribe `Sources/XFxxx/README.md`
   y actualiza `docs/MODULE_STATUS.md`.
4. Resume en tres lineas que has cambiado y que modulos podrian verse afectados.

## Lo que NO debes hacer nunca

- Refactorizar codigo de un modulo que no es el de tu tarea, aunque te duela verlo.
- Crear un "fichero de utilidades comun" que todos importen. Es el agujero por donde
  se cuela el acoplamiento. Si algo lo necesitan dos modulos, va en el modulo de
  abajo que ambos ya dependen, o se duplica.
- Adelantar tareas de bloques posteriores porque "ya que estoy".
- Anadir dependencias externas sin ADR. El proyecto es GPL-3.0-only (ADR-030):
  MIT, BSD y Apache-2.0 sirven; con ADR igualmente.


---

# Restricciones de plataforma (anadido v0.4) — CRITICO

**Minimo macOS 11.0 · Swift 5.7.2 · Xcode 14.2 · universal Intel + Apple Silicon.**

Esto es lo que mas facil se te va a colar, porque casi todos los ejemplos recientes
de SwiftUI usan APIs que aqui **no compilan**. Antes de proponer cualquier API,
comprueba `docs/PLATFORM_SUPPORT.md` seccion 4.

## Prohibido sin `if #available` y ruta alternativa

`NavigationStack` · `NavigationSplitView` · `@Observable` / Observation ·
`.searchable` · `Table` · `AsyncImage` · `ShareLink` · `SwiftData` ·
`.scrollContentBackground` · `Duration` / `ContinuousClock` · `swift-testing` ·
macros de Swift · *parameter packs* · concurrencia estricta de Swift 6

## Usa en su lugar

`NavigationView` · `ObservableObject` + `@Published` + `@StateObject` · XCTest ·
GRDB 6.x · `mach_absolute_time` · CoreMIDI clasico (`MIDIPacketList`) ·
`thread_policy_set` con `THREAD_TIME_CONSTRAINT_POLICY` para el hilo de audio

## Rendimiento

- No asumas 120 fps. Sincroniza con el refresco real: **60 en Intel**, 120 si lo hay.
- No asumas que 64 frames de buffer valen en todas las maquinas: debe poder subir
  a 128 solo.
- La maquina de desarrollo **es** el MacBook Pro Intel de 2015 con Monterey. No hay
  otra. Si algo va lento ahi, va lento y punto: no lo justifiques con el hardware.
- Compila por modulo, no el proyecto entero. En un doble nucleo eso importa.

## Y ademas

- `NSMicrophoneUsageDescription` es obligatorio: el timecode entra como entrada de
  audio y sin permiso la app parece rota sin decir por que.
- Si necesitas subir el minimo de macOS o cambiar la toolchain: **para y pideme un
  ADR**. No lo hagas por tu cuenta.


# Intel y Apple Silicon (anadido v0.6)

- El binario es **universal** desde el primer dia. No escribas nada que solo
  compile en una arquitectura.
- **Nunca compares goldens de coma flotante byte a byte.** Redondea a 4 decimales
  al serializar y compara con tolerancia `1e-9`. Entre `x86_64` y `arm64` los
  ultimos bits difieren legitimamente.
- En el hilo de audio: `thread_policy_set` **y** unirse al workgroup del dispositivo
  de audio. En Apple Silicon lo segundo no es opcional (nucleos P/E).
- Si tocas C vendorizado, comprueba que no dependa de intrinsecos SSE.
- No propongas "ya lo hacemos universal mas adelante". Es ADR-028 y es ahora.
