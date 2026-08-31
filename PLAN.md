# PLAN.md — xFlare

> **Plan estratégico.** Define el alcance del MVP (v1), la hoja de ruta de
> iteraciones posteriores, los criterios de aceptación por hito y los riesgos.
>
> El **backlog táctico** (qué tarea toca ahora, un bloque cada vez) está en
> `TODO.md`, con espejo legible por máquina en `data/backlog.json`. Este documento
> dice **por qué** ese orden y **cuándo** algo está terminado de verdad.
>
> Reconcilia el antiguo plan por Fases (0-8) con el backlog por Bloques (B0-B12):
> ver la tabla de correspondencia en la sección 3.

**Leyenda:** `[ ]` pendiente · `[~]` en curso · `[x]` hecho

---

## 1. Filosofía del plan

1. **MVP primero, features después.** v1 es el gimnasio de scratch más útil que
   existe, aunque no tenga importación de ejercicios, analítica profunda ni
   feedback RGB. Todo eso son iteraciones posteriores (sección 9), no v1.
2. **Un bloque cada vez, una tarea cada vez.** No se empieza un bloque sin cerrar
   el anterior. Adelantarse es la forma clásica de no terminar nunca.
3. **Sellar módulos.** Cuando un módulo cumple las 5 condiciones de
   `docs/ARCHITECTURE.md` §6 pasa a `SEALED` y deja de poder romperse. Sus tests
   son inmutables.
4. **La latencia es puerta de calidad, no objetivo.** Ver sección 8.
5. **Se desarrolla y se prueba en el MacBook Pro Intel de 2015 con Monterey.** Es
   la máquina de referencia. El slice `arm64` se cubre con CI.

---

## 2. Definición del MVP (v1)

**El MVP está completo cuando los hitos A-G de la sección 4 están cerrados.**
En ese punto xFlare:

| Área | Qué hace en v1 |
|---|---|
| Audio RT | Callback CoreAudio RT-safe, buffer 64→128 adaptativo, `thread_policy_set` + workgroup de audio, latencia dentro de la tabla por máquina |
| Timecode | xwax vendorizado, **modo relativo** (ADR-004), hamster desde el día 1 (ADR-008), recuperación de dropout |
| Captura de fader | `audio_return` con tono piloto (primario, ADR-021) + MIDI si la mesa lo ofrece; binarización con cut-in calibrado e histéresis (ADR-017) |
| Visual | Scope Lissajous + autopista SpriteKit sincronizada al **reloj de audio**, capas fantasma / usuario / delta |
| Modo fantasma | Scoring híbrido: clicks discretos (ventanas ±20/40/70/110 ms) + DTW de contorno de tono (afinación relativa, ADR-005) |
| Diagnóstico | Frases accionables en ms con signo; distingue sesgo sistemático de dispersión (ADR-018) |
| Estrellas | 3 estrellas por criterios ortogonales (ADR-025), no umbrales del mismo número |
| El gym | Librería generativa (25 scratches, ADR-015), niveles L1-L3 jugables (≥20 ejercicios), escalera de BPM adaptativa, variantes offset / amplitude / mirror / subdivision / swing / blind (ADR-026) |
| Persistencia | Intentos con `.xfsession` crudo, progreso agregado, mejor BPM con 3★, sesgo medio, esquema de repetición espaciada y de "cuenta / no cuenta para estrellas" (para el calentamiento futuro) |
| Pantallas | Calibración de 4 pasos, Home / mapa de la matriz, Práctica, Resultados / diagnóstico, Librería, Ajustes, Mi mesa + asistente de mapeo MIDI/HID |
| Mesas | Perfil de referencia `rane-seventy-two` (MK1) + `generic-midi` + `keyboard`; `.conf` en INI plano (ADR-019), CC0 (ADR-020) |
| Modo Destete | Nivel 1 (autopista completa) y nivel 4 (ciego, vía variante `blind`). Niveles 2-3 (fade / intermitente) opcionales; si estorban, van a Iteración 2 |
| Build | Binario universal `x86_64` + `arm64` desde B0.6, CI en `macos-14` (ADR-028) |
| Distribución | DMG notarizado + fórmula de Homebrew. **Sin Mac App Store** (ADR-003) |

**Fuera de v1** (van a iteraciones, sección 9): formato `.xflare` e importación,
modo REC, analítica histórica profunda, multi-controlador más allá del perfil de
referencia, feedback RGB, y todo lo de `TODO.md` → FUTURIBLES.

**Soberanía del usuario, en v1 y siempre:** sin cuenta, sin nube, sin telemetría,
sin red en runtime. Funciona en un avión.

---

## 3. Correspondencia Fases ↔ Bloques ↔ Hitos

El antiguo `PLAN.md` describía Fases 0-8 por features. `TODO.md` ejecuta por
Bloques B0-B12 (orden por dependencias y por sellado de módulos). Equivalencia:

| Fase antigua | Bloques que la realizan | Hito | ¿En v1? |
|---|---|---|---|
| Fase 0 · Fundamentos audio + timecode | B0, B1, B4, B5 | A, C | Sí |
| Fase 1 · Scope y monitor visual | B5b, B6 (parcial), B7 | C, D | Sí |
| Fase 2 · Motor de audio completo | B4.3-B4.4, B11 (samples, modo sin mesa, metrónomo) | C, F | Sí |
| Fase 3 · Modo fantasma: el juego | B2, B3, B7.4, B8, B9 | B, E | Sí |
| Fase 4 · El gym: catálogo de técnicas | B3, B9, B10, B11 | E, F | Sí |
| Fase 5 · Formato `.xflare` y modo REC | — | — | **No → Iteración 2** |
| Fase 6 · Analítica y progreso | B10 (básico) / resto | F | Básico sí; profundo → **Iteración 3** |
| Fase 7 · Multi-controlador | B5b, B6, B11.10 (básico) / resto | D, F | Perfil de referencia sí; resto → **Iteración 4** |
| Fase 8 · Feedback RGB y pulido | B12 (empaquetado) / RGB | G | Empaquetado sí; RGB → **Iteración 5** |

---

## 4. Hitos del MVP

Orden de ejecución (el de `TODO.md`):
**B0 → B1 → B2 → B3 → B4 → B5 → B5b → B6 → B7 → B8 → B9 → B10 → B11 → B12.**

---

### Hito A — Viabilidad · bloques B0, B1

**Objetivo.** Que exista el esqueleto, que `make verify` signifique algo, y tener
**el número de latencia real** de la máquina de referencia. Si ese número no entra
en la tabla de la sección 8, el plan se detiene y se abre un ADR con el plan B
antes de escribir nada más.

**Criterio de aceptación.**
- `swift build` y `swift test` pasan con los 13 targets vacíos; el grafo de
  dependencias es exactamente el de `docs/ARCHITECTURE.md` §2.
- `make verify` corre y sale 0. `make status` imprime el backlog.
- `LICENSE` con el texto **oficial** de la GPL-3.0 descargado de gnu.org
  (`LICENSE-TODO.md`), cabecera de licencia en cada fuente propia.
- Binario universal desde el primer día: `lipo -archs` muestra `x86_64 arm64`.
- CI en verde: `macos-13` (toolchain fijada), `macos-14` (arm64), trabajo universal.
- **Latencia round-trip medida por loopback** en la máquina de referencia,
  anotada en `docs/TIMECODE.md`. Decisión documentada (B1.3).
- Captura del crossfader por tono piloto validada con jitter < 5 ms (B1.4). Si
  falla → ADR con el plan C **antes** de seguir.
- La Rane 72 (MK1) enumera sus canales USB en Monterey (B1.7).

**No hacer en este hito.** Ni UI, ni scoring, ni ejercicios, ni persistencia, ni
SpriteKit. Los prototipos de B1 son **desechables**.

> 🚩 **Puerta de calidad.** Ver sección 8. No se avanza al Hito B con la latencia
> en rojo sin un ADR que lo justifique.

---

### Hito B — Núcleo puro · bloques B2, B3

**Objetivo.** `XFClock` y `XFNotation` sellados. Swift puro, sin hardware, se
sellan rápido y enseñan el ritmo del proceso con algo fácil.

**Criterio de aceptación.**
- `XFClock`: conversiones tick ↔ ms ↔ hostTime con PPQ 480, ida y vuelta sin
  pérdida en 10.000 valores; transporte (play/stop/loop/cuenta atrás); `ClockMap`.
- `XFNotation`: modelos `Codable` que decodifican `data/*.json` sin pérdida y
  validan contra `data/schema/*.json`; compositor mano × fader portado de
  `tools/xfn_core.py`; **golden**: la librería compilada en Swift es idéntica a
  `data/scratches/library-v0.1.json` sobre los 25 scratches (redondeo a 4
  decimales, tolerancia `1e-9`, ADR-028).
- Fases con tramo parcial de curva (`u0`/`u1`) y función de recorte exacta.
- Transformaciones de variante (offset, amplitude, mirror, subdivision, swing)
  con golden contra `tools/xfn_core.py`.
- Cálculo de eventos evaluables y `maxScore` por variante: 2-Click Flare base =
  3.600; su `div16` = 4.800 (`docs/SCORING.md` §1).
- Ambos módulos `SEALED` en `docs/MODULE_STATUS.md`.

**No hacer en este hito.** Hardware, UI, red, DTW (eso es `XFAnalysis`).

---

### Hito C — Motor de audio real · bloques B4, B5, B5b

**Objetivo.** `CXFAudioCore`, `CXFTimecode` y `XFProfiles` sellados. Esta vez el
motor de audio es para quedarse. Puerta de latencia **definitiva**.

**Criterio de aceptación.**
- Ring buffer SPSC lock-free en C: tests al 100%, incluido productor/consumidor
  concurrente.
- Callback CoreAudio RT-safe, 64 frames, **0 malloc / 0 locks** verificado con
  Instruments; el hilo fija prioridad con `thread_policy_set` **y** se une al
  workgroup del dispositivo (obligatorio en Apple Silicon, ADR-028).
- Reproductor de sample con resampling por velocidad y dirección: scratch audible
  sin clicks ni aliasing. Metrónomo mezclado en la **salida principal** (ADR-007).
- **PUERTA DE CALIDAD:** round-trip ≤ 10 ms en la referencia (≤ 15 ms en el Intel
  de 2015 con buffer 128), **0 overloads en 5 min**, sin deriva tras 10 min.
  Medido y documentado en `docs/TIMECODE.md`.
- xwax vendorizado **INTACTO** en `Sources/CXFTimecode/vendor/xwax/`; compila sin
  tocar `timecoder.c` ni `lut.c`; si trae intrínsecos SSE se condicionan por
  arquitectura sin tocar la lógica (B0.7).
- Wrapper `xf_timecode` en modo relativo; hamster desde el día 1 (test con señal
  invertida); confianza de señal y recuperación de dropout (no se cuelga al
  levantar la aguja).
- `XFProfiles`: parser INI propio sin dependencias que carga los 6 perfiles de
  `profiles/` sin pérdida; resuelve `extends` con detección de herencia circular;
  mismos errores que `tools/xf_profile.py`; autodetección por comodines (si hay
  empate, pregunta, no elige); precedencia bundle → carpeta de usuario
  (`docs/DEVICE_PROFILES.md` §5).
- Los tres módulos `SEALED`.

**No hacer en este hito.** Enrutado multicanal fino, grabación de sesión a WAV,
selector de samples en UI (eso vive en `XFApp`, Hito F).

---

### Hito D — Entrada y espejo · bloques B6, B7

**Objetivo.** `XFCapture` sellado y la autopista dibujando. Un espejo fiel de lo
que hace el vinilo y el fader, **sin evaluar nada todavía**. Aquí se desbloquea el
desarrollo sin mesa.

**Criterio de aceptación.**
- Protocolos `MotionSource` / `FaderSource` (`docs/ARCHITECTURE.md` §3).
- `KeyboardMotionSource` / `KeyboardFaderSource`: se puede hacer un baby scratch
  con el teclado.
- `TimecodeMotionSource` sobre `CXFTimecode`; `MidiFaderSource` con fallback;
  `AudioReturnFaderSource` con tono piloto que funciona con el perfil
  `rane-seventy-two`.
- Binarización del fader con cut-in calibrado e histéresis: **0 eventos fantasma**
  en 1 min de fader quieto.
- Formato `.xfsession`: una sesión grabada se reproduce **bit a bit igual**
  (`ReplaySource`). Es la base de los tests de replay.
- `XFDesign`: tokens de `docs/UI_DESIGN.md` §2 y componentes base.
- `XFRender`: escena SpriteKit sincronizada al **reloj de audio** (nunca al
  frame), sin deriva tras 10 min, **60 fps estables en el MacBook Pro 2015** con
  la autopista completa, 120 donde haya ProMotion. Capas fantasma + usuario +
  teñido por tolerancia. Scope Lissajous. Golden tests de render en SVG sobre los
  25 scratches.
- `XFCapture`, `XFDesign`, `XFRender` `SEALED`.
- **Verificación de usuario:** un scratch real se dibuja reconocible y sin retraso
  perceptible; el scope se degrada visiblemente al ensuciar la aguja; el cut-in
  calibrado coincide con el punto real de apertura a oído.

**No hacer en este hito.** Curva objetivo evaluada, puntuación, ejercicios, BD.

---

### Hito E — El juego · bloques B8, B9

**Objetivo.** El corazón del producto. `XFAnalysis` y `XFEngine` sellados. Curva
objetivo, tu curva encima, y una evaluación que **enseña**.

**Criterio de aceptación.**
- Emparejado de clicks objetivo/usuario y **desfase con signo** en ms.
- DTW de contorno de tono, afinación **relativa** (ADR-005): evalúa forma y
  dirección, no frecuencia absoluta.
- Consistencia (σ) y amplitud de recorrido.
- Generador de diagnósticos en lenguaje natural (ADR-018): distingue sesgo
  sistemático de dispersión y lo dice distinto.
- Puntuación por evento sobre `maxScore` (`docs/SCORING.md` §1); 3 estrellas
  ortogonales (ADR-025): un 88% con un fallo suelto da 1 estrella, no 2.
- **Tests de replay** por patrón de nivel 1-4: `good` puntúa ≥ 0.88, `late`
  detecta sesgo positivo ~35 ms, `sloppy` puntúa ≤ 0.60 y señala dispersión
  (`docs/TESTING.md`).
- `XFEngine`: máquina de estados (calentamiento, series, descanso, boss,
  resultados); escalera de BPM adaptativa (2 fallos baja, 3 aciertos sube);
  desbloqueo por **compases consecutivos**, no por media.
- El scoring corre **fuera del hilo de audio**. 0 latencia añadida al callback.
- `XFAnalysis`, `XFEngine` `SEALED`.
- **Verificación de usuario:** un baby bien ejecutado puntúa alto; uno cojo se
  detecta y se explica por qué. Un flare con el click tarde produce el mensaje
  concreto de desfase, en ms y con signo. El resultado se entiende sin manual.

**No hacer en este hito.** Persistencia, pantallas finales, rampa de BPM con
histórico (eso necesita BD).

---

### Hito F — Producto usable · bloques B10, B11

**Objetivo.** `XFPersistence` sellado y **todas las pantallas**. Que el progreso
sobreviva a cerrar la app y que un usuario nuevo llegue a tocar sin ayuda externa.

**Criterio de aceptación.**
- `XFPersistence`: esquema GRDB 6.x y migraciones; histórico de tomas, progreso y
  desbloqueos; repetición espaciada (1, 3, 7, 21 días); calibración por
  dispositivo; tabla de intentos con `eventScores` y ruta al `.xfsession`
  (`data/schema/attempt.schema.json`); progreso agregado (intentos, mejor, media
  de 5, mejor BPM con 3★, sesgo medio — `docs/SCORING.md` §3); estado de
  **dominado** (3★ base + 2★ en tres variantes) y desbloqueo de variantes. El
  esquema distingue desde ya intentos que **cuentan para estrellas** de los que
  no (para el calentamiento futuro, ADR-027).
- `XFApp`: asistente de calibración de 4 pasos; Home con mapa de la matriz;
  pantalla de práctica (la autopista); resultados con diagnóstico y estrellas
  apagadas que **dicen qué falta**; modo libre con grabación de los últimos 30 s;
  navegador de la librería; Ajustes; pantalla "Mi mesa" con insignias de
  verificación y prueba en vivo; asistente de mapeo MIDI/HID con monitor en crudo
  (si no llega MIDI en 5 s, propone `audio_return`); permiso de micrófono con
  texto honesto y pantalla de ayuda si se deniega; detección de Rosetta
  (`sysctl.proc_translated`) con aviso en calibración.
- **Modo sin mesa** completo: mezcla interna a auriculares USB, para practicar de
  viaje.
- Accesibilidad: VoiceOver en navegación y resultados, alto contraste, todo
  accionable con teclado (`docs/UI_DESIGN.md` §4).
- Banco de samples de fábrica **libres de derechos** (mínimo 8, incluyendo una
  *sentence*). Nada de "Ahhh", "Fresh" ni material de discos comerciales.
- **Verificación de usuario:** al menos 20 ejercicios jugables cubriendo L1-L3;
  la rampa adaptativa converge al BPM real en menos de 10 vueltas; el modo ciego
  es jugable solo con audio y metrónomo.

**No hacer en este hito.** Formato `.xflare`, importación, analítica histórica
profunda, feedback RGB.

---

### Hito G — Distribución · bloque B12

**Objetivo.** Que lo pueda usar alguien que no seas tú.

**Criterio de aceptación.**
- Binario universal verificado y matriz de pruebas de `docs/PLATFORM_SUPPORT.md`
  §9 completa en las dos máquinas.
- Firma y notarización con `notarytool`; la app arranca en un Mac limpio desde el
  DMG **sin avisos de Gatekeeper**.
- DMG + fórmula de Homebrew.
- README público, capturas, vídeo de 30 s.
- **5 DJs probándolo y sus notas.** El examen de verdad.

---

## 5. Qué NO se hace en v1 (resumen vinculante)

- ❌ Servidor, cuentas, ranking, comunidad online, moderación.
- ❌ Formato `.xflare`, embebido de WAV, importación con aviso legal, modo REC.
- ❌ Gamificación: rachas agresivas, XP, monedas, logros, confeti.
- ❌ Dos platos, pads/sampler, import de samples propios.
- ❌ Feedback RGB a los pads de la mesa.
- ❌ Analítica histórica profunda (mapa de calor del compás, detección de meseta).
- ❌ Multi-controlador más allá del perfil de referencia + genérico + teclado.
- ❌ Scripting de mapeos (solo declarativo, ADR-009).
- ❌ Subir el mínimo de macOS o cambiar la toolchain sin ADR.
- ❌ Modificar el código vendorizado de xwax.
- ❌ Adelantar tareas de bloques posteriores "ya que estoy".

---

## 6. Cómo trabaja Claude Code con este plan

1. Abrir `TODO.md`, coger **la primera tarea no hecha del bloque activo**.
2. Consultar `docs/MODULE_STATUS.md`. Confirmar en voz alta qué módulo se toca y
   cuál es el criterio de aceptación.
3. **Un módulo por tarea.** Si hace falta tocar otro, PARAR y preguntar.
4. Un módulo `SEALED` no se toca. Sus tests no se editan.
5. `make verify` en verde antes de dar nada por terminado.
6. Marcar el checkbox en `TODO.md` **y** el estado en `data/backlog.json`.
7. Si la tarea era SELLAR: `make seal M=XFxxx`, escribir `Sources/XFxxx/README.md`,
   actualizar `docs/MODULE_STATUS.md`.
8. Toda decisión técnica no trivial → entrada en `docs/DECISIONS.md` con fecha,
   contexto, alternativas y consecuencias.
9. Resumir en 3-5 líneas qué se cambió y qué módulos podrían verse afectados.

---

## 7. Entorno de desarrollo

- **Máquina de referencia:** MacBook Pro 13" Early 2015, Intel, **macOS 12
  Monterey**. Se desarrolla y se prueba aquí.
- **Toolchain:** Xcode 14.2 / Swift 5.7.2, `swift-tools-version: 5.7` (ADR-023).
  `swift build` y `swift test` funcionan en local. El crash de `swift test` que
  describía ADR-029 se resolvió (2026-08-31) completando el primer arranque de
  Xcode 14.2. No hizo falta Xcode 14.1.
- **arm64:** se compila universal desde B0.6 y la lógica se verifica en CI
  (`macos-14`, gratis en repos públicos). El audio en tiempo real y el timecode
  en Apple Silicon quedan **sin verificar en hardware** hasta que un usuario con
  un Mac M lo pruebe; el README lo dice.
- **Git:** se incorpora más adelante, cuando el autor vea cómo avanza la app.
- **Nextcloud:** la carpeta vive dentro de Nextcloud; excluir `.build/` de la
  sincronización además del `.gitignore` cuando se active.
- **Red:** solo en el primer `swift build` (descarga de GRDB 6.x, luego cacheada).
  En runtime, ninguna.

---

## 8. Puerta de latencia (ADR-013 + ADR-024)

En scratch la app **es** el disco. Por encima de ~10 ms el gesto se siente
"gomoso" y cualquier turntablista lo detecta. El techo **deja de ser un número
único** y pasa a ser una tabla que se rellena midiendo (Hito A / Hito C):

| Máquina | Buffer | Round-trip | Estado |
|---|---|---|---|
| Máquina de referencia | 64 frames | ≤ 10 ms deseable, objetivo 7 ms | por medir |
| MacBook Pro 2015 (Monterey) | 64 frames | ≤ 10 ms deseable | por medir |
| MacBook Pro 2015 (Monterey) | 128 frames | ≤ 15 ms aceptable | por medir |

- Presupuesto orientativo: captura USB 1,5 · decode 2,0 · proceso+mezcla 1,5 ·
  salida USB 1,5 · driver/HAL 3,0 → ~9,5 ms.
- El buffer sube de 64 a 128 frames **solo** al detectar overloads (ADR-024).
- Si en el Intel de 2015 no se baja de 15 ms, se **documenta como limitación
  conocida** y la app lo dice en la calibración, en vez de fingir que va fino.
- Ninguna feature puede comprometer este presupuesto. Un PR que suba el número
  necesita justificación explícita.
- Perfilado con Instruments (Audio System Trace) como criterio de aceptación, no
  como pulido posterior.

---

## 9. Iteraciones post-v1

No se toca ninguna hasta que v1 esté en manos de gente y haya feedback real.

### Iteración 2 — Motor de contenido (antigua Fase 5)

Lo que rompe el techo de un catálogo cerrado.

- Formato `.xflare` especificado en `docs/XFLARE_FORMAT.md`, con `format_version:
  1` desde el primer commit y compatibilidad hacia atrás.
- Metadatos: autor, BPM, técnica, dificultad, orientación (hamster o no),
  hardware, duración.
- El sample WAV **se embebe** en el `.xflare` (ADR-006).
- **Aviso legal obligatorio y no omitible** al importar, con confirmación
  explícita (ADR-006). Nunca un "no volver a mostrar".
- Modo REC: grabar una ejecución y convertirla en ejercicio; cuantización opcional
  contra la rejilla; edición post-grabación (recortar, repetir sección, ajustar
  tempo).
- Exportar / importar con checksum de integridad; biblioteca local de importados
  con búsqueda y filtros.
- Modo Destete niveles 2-3 (fade / intermitente) si no entraron en v1.
- Intercambio **por fichero**. Sin servidor. Un repo de GitHub para ejercicios de
  la comunidad da el 90% del valor con el 2% del trabajo (ADR-010).

### Iteración 3 — Analítica profunda (antigua Fase 6)

- Gráfica de dispersión temporal con **sesgo con signo** (adelantado / atrasado).
- Mapa de calor del compás: qué subdivisión se atraganta.
- **Detección de meseta** + sugerencia concreta de qué cambiar.
- Exportar / importar todo el progreso como fichero.
- Criterio: tras 10 sesiones, la app identifica correctamente la técnica más débil.

### Iteración 4 — Multi-controlador (antigua Fase 7)

- Formalizar los protocolos `PlatterSource`, `FaderSource`, `PadSurface`.
- `MidiJogSource`: soporte de controladores con jog wheel.
- Perfiles adicionales: DJM-S9 / S11, DDJ-SX3.
- **Pilotar la app desde la mesa**: reintentar, siguiente, BPM ±, play/pause. El
  usuario no puede soltar el fader para coger el ratón.
- Criterio: un controlador desconocido queda usable en < 2 min vía MIDI Learn; una
  sesión completa se navega sin teclado ni ratón.

### Iteración 5 — Feedback RGB y pulido (antigua Fase 8)

- Salida CoreMIDI hacia los pads de la mesa (por hilo aparte, **0 latencia** al
  hilo de audio).
- Color: verde perfecto, amarillo aceptable, rojo fallo. Iluminar el pad que toca
  pulsar, anticipándolo.
- Modo alto contraste y pantalla completa optimizado para portátil de 13".

### Iteración 6+ — Futuribles

Ver `TODO.md` → FUTURIBLES. Calentamiento adaptativo con detección de oxidación
(ADR-027, el esquema de BD ya lo soporta desde v1), variantes avanzadas
(encadenado, densidad creciente, rampa de tempo, un solo lado), dos platos
(juggling, chasing), pads y sampler, import de samples propios, export a vídeo
vertical, transcripción de scratch desde audio/vídeo a XFN, rutinas de usuario,
retos diarios, más mesas, port a Linux/Windows, modo profesor, repositorio
comunitario de perfiles.

---

## 10. Riesgos activos

| # | Riesgo | Impacto | Mitigación |
|---|---|---|---|
| R1 | **Latencia fuera de la tabla** | Proyecto inviable | Puerta de calidad en Hito A (B1) y Hito C (B4.5). Medir antes de construir |
| R2 | **El crossfader de la Rane 72 no manda MIDI** | Alto | Confirmado como probable (ADR-021). Plan primario: `audio_return` con tono piloto. Validar en B1.4. Plan C (fader MIDI externo) si falla |
| R3 | Samples de fábrica insuficientes o feos | Medio | Presupuestar tiempo real de diseño sonoro en el Hito F |
| R4 | La GPL (v3, ADR-030) cierra la App Store y el closed-source | Aceptado | Decisión consciente. Vender sí; cerrar el código y la App Store, no. Distribución DMG + Homebrew |
| R5 | Copyright de samples embebidos en `.xflare` | Medio | Aviso legal en importación (Iteración 2). Riesgo residual asumido (ADR-006) |
| R6 | Autor con Swift a nivel 0 | Medio | Comentarios densos exigidos (CLAUDE.md §9). Swift antes que Rust por esto |
| R7 | Ámbito creciendo sin control | Alto | Secciones "No hacer" (5) y la barrera de iteraciones. Son vinculantes |
| R8 | arm64 sin verificar en hardware | Aceptado | CI cubre la lógica; el README lo dice hasta que un usuario con Mac M lo pruebe |
| R9 | Compilación lenta en el doble núcleo de 2015 | Medio | Arquitectura modular: se compila un módulo, no el proyecto entero |

---

## 11. Métrica de éxito del MVP

**Hitos A-G cerrados.** En ese punto, xFlare ya es la mejor herramienta que existe
para practicar scratch, aunque no tenga importación ni comunidad.

El hueco que ocupa es real y estrecho: nadie junta captura de timecode + notación
tipo TTM + evaluación con diagnóstico + currículo (`docs/PRIOR_ART.md`). Visual
Scratch hizo la primera pieza hace años y se quedó ahí; Melodics hizo las otras
tres para otros instrumentos.

Todo lo demás es amplificación.
