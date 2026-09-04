# DECISIONS.md — xFlare

> Registro de decisiones de arquitectura (ADR). Cada entrada explica **qué** se
> decidió, **por qué**, **qué se descartó** y **qué cuesta**.
>
> Regla: toda decisión técnica no trivial que se tome durante el desarrollo se
> añade aquí. Si dudas de si merece una entrada, la merece.
>
> **Contiene todos los ADR: 001-013** (redacción original, con puntos medios en
> el título) **y 014-053** (fusionados desde el antiguo `ADR-014-onward.md` el
> 2026-09-03; formato algo más terso, con guiones). Las entradas nuevas van al
> final, antes de la plantilla.

---

## ADR-001 · Sólo macOS

**Fecha:** 2026-08-27 · **Estado:** aceptada · **Mínimo revisado por ADR-022**

> ⚠️ El mínimo concreto de esta entrada (**macOS 14+**) quedó **sustituido por
> ADR-022**: el mínimo real es **macOS 11.0 Big Sur**, con binario universal
> Intel + Apple Silicon. Lo que sigue vigente de ADR-001 es la decisión de fondo:
> **solo macOS**, sin Windows, sin Linux, sin iOS.

**Contexto.** La inmensa mayoría de DJs trabajan sobre Mac. El proyecto lo lleva
una sola persona.

**Decisión.** macOS 14+ exclusivamente. Sin Windows, sin Linux, sin iOS.

**Alternativas descartadas.**
- *Multiplataforma desde el inicio:* triplica el trabajo de la capa de audio, que
  es justo la parte crítica.
- *Windows en el roadmap:* para latencia decente necesitaría **ASIO**, cuyo SDK de
  Steinberg es notoriamente incompatible con la GPL. Es la razón por la que
  Audacity y Mixxx no distribuyen builds con ASIO. Dado el ADR-003, Windows tiene
  fricción **legal**, no sólo técnica.

**Consecuencias.**
- ✅ CoreAudio y CoreMIDI son excelentes y están muy documentados.
- ✅ **Regalo inesperado:** `AudioTimeStamp` y `MIDITimeStamp` comparten dominio de
  reloj (`mach_absolute_time`). Alinear el click del crossfader con la posición
  exacta del vinilo es trivialmente preciso. En Windows sería una pesadilla.
- ❌ Se renuncia a la mayor parte del mercado teórico. Se acepta.
- 📌 Si alguna vez se porta, **Linux antes que Windows** (ALSA/JACK son limpios).

---

## ADR-002 · Híbrido Swift + C, no C++ puro ni Rust

**Fecha:** 2026-08-27 · **Estado:** aceptada

**Contexto.** Hay que elegir lenguaje para un proyecto con audio en tiempo real,
interoperabilidad con C, UI de juego y un autor con Swift a nivel 0, C/C++ de
universidad más Arduino, y algo de Python. El criterio explícito del autor es
maximizar la velocidad de desarrollo asistido por Claude Code.

**Decisión.** Swift ≈ 80 % (UI, SpriteKit, MIDI, scoring, persistencia) y
C/C++17 ≈ 20 % (exclusivamente el hilo de audio). Puente por bridging header.

**Razones.**
1. La capa C es **C de Arduino**: búferes, punteros, bucles apretados, cero
   `malloc`. Terreno que el autor ya conoce.
2. Swift, viniendo de Python, es más suave que C++ moderno. SwiftUI se lee casi
   como pseudocódigo.
3. `timecoder.c` de xwax **ya es C plano**. Swift lo llama directamente por
   bridging header: sin FFI, sin bindings generados, sin `unsafe`.
4. Xcode aporta debugger e **Instruments**, imprescindible para perfilar latencia.
5. Swift y SwiftUI están extraordinariamente bien cubiertos por Claude Code.

**Alternativas descartadas.**
- *Rust:* técnicamente elegante y RT-safe por diseño, pero borrow checker + FFI
  `unsafe` + ecosistema de UI inmaduro en macOS, partiendo de nivel 0, es receta
  de abandono. Coste estimado: varias semanas extra.
- *C++ puro:* válido, pero sin JUCE (ADR-003) habría que montar la UI a mano.
- *Python para la app:* descartado sin matices. GIL y recolector de basura
  producen jitter impredecible. **Sí se usa en `tools/`** para prototipar el DTW,
  el scoring y el análisis de curvas: iterar ahí cuesta minutos en vez de horas.

**Consecuencias.**
- ⚠️ La frontera Swift/C es sagrada. **Nunca** código Swift en el callback de
  audio: ARC puede reservar memoria de forma impredecible y Apple lo desaconseja.
- 📌 CLAUDE.md §9 exige comentarios densos por el nivel de Swift del autor.

---

## ADR-003 · Vendorizar xwax ⇒ el proyecto es GPL (versión corregida en ADR-030)

**Fecha:** 2026-08-27 · **Estado:** aceptada · **Sustituye a:** stack permisivo previo · **Corregida por:** ADR-030 (2026-08-31)

> ⚠️ **Corrección (ADR-030).** Esta entrada asumía que `timecoder.c` / `lut.c`
> son **GPL-2.0-only**. Cierto hasta xwax **1.7**; desde **xwax 1.8 (2021)** el
> proyecto se relicenció a **GPL-3.0**. Al vendorizar **xwax 1.10** en el bloque
> B5, el proyecto pasa a **GPL-3.0-only**. Cambian dos consecuencias de la tabla
> de abajo: **JUCE** (opción GPLv3) deja de ser incompatible, y **Apache-2.0**
> pasa a ser compatible. Lo demás (App Store descartada, nunca closed-source, el
> valor de xwax es su código maduro) sigue igual. Detalle en ADR-030.

**Contexto.** Decodificar timecode de vinilo es DSP no trivial: detección de
cuadratura de fase, PLL y decodificación de un bitstream de posición. `xwax`
lleva años haciéndolo y **Mixxx usa su código internamente**.

**Decisión.** Vendorizar `timecoder.c` y `lut.c` de xwax sin modificarlos, y
licenciar xFlare bajo la misma licencia que xwax. *(Escrito como GPL-2.0-only;
xwax 1.8+ es GPL-3.0, así que es **GPL-3.0-only** — ver ADR-030.)*

**Razones.**
- Ahorra semanas de ingeniería inversa.
- Está probado contra vinilos reales: Serato CV02, Traktor MK1, MixVibes DVS V2.
- Evita el infierno de depurar un decoder propio sin saber si el fallo está en el
  código o en la aguja.
- `timecoder.c` está diseñado para **definir timecodes propios** (resolución,
  bits, semilla, taps): permite crear un modo relativo simplificado a medida.

**Matiz honesto sobre "aprovechar futuras actualizaciones".** El argumento es más
débil de lo que parece. Entre la 1.7 y la 1.10 el timecoder sí ganó soporte de
vinilos Pioneer RekordBox y algún bugfix, pero el grueso de las actualizaciones
es fontanería de Linux irrelevante en macOS. El desarrollo va por lista de correo
(`xwax-devel`), no por GitHub: integrar cambios es comparar tarballs a mano. El
valor real de xwax es el **código maduro y probado**, no las actualizaciones de
mañana. *(Se vendoriza la 1.10 y se asume su licencia GPL-3.0 — ADR-030.)*

**Consecuencias — importantes y algunas irreversibles.**

| Consecuencia | Detalle |
|---|---|
| ✅ Open source en GitHub | Encaja perfectamente con la intención del autor |
| ~~JUCE descartado~~ | *Corregido por ADR-030:* con GPL-3.0-only, la opción GPLv3 de JUCE **es compatible**. No se usa igualmente (UI = SwiftUI) |
| ~~Apache-2.0 incompatible~~ | *Corregido por ADR-030:* Apache-2.0 **es compatible** con GPLv3. MIT/BSD también |
| ❌ **Mac App Store descartada** | Los términos de la App Store chocan con la GPL (precedente VLC, 2011). Distribución por DMG notarizado y Homebrew |
| ❌ Nunca habrá versión closed-source | Vender sí se puede (la GPL no lo prohíbe); cerrar el código, no |

**Alternativa considerada y descartada.** Ejecutar xwax como proceso separado
comunicándose por IPC preservaría la libertad de licencia, pero añade latencia,
complejidad de empaquetado y una frontera legal discutible. Para un proyecto
open source en solitario no compensa.

---

## ADR-004 · Modo relativo, no absoluto

**Fecha:** 2026-08-27 · **Estado:** aceptada

**Decisión.** El decoder opera en **modo relativo**: sólo velocidad y dirección.

**Razón.** En un ejercicio de scratch da igual dónde esté la aguja. Sólo importa
cómo se mueve el disco.

**Consecuencias.**
- ✅ Inmune a discos rayados, aguja sucia y *needle drop*.
- ✅ Decoder más simple y más robusto.
- ✅ El punto de cue del sample lo fija la app, no la posición del vinilo.
- ❌ Sin salto por posición absoluta. No se necesita para practicar.

---

## ADR-005 · Afinación relativa, no absoluta

**Fecha:** 2026-08-27 · **Estado:** aceptada · **Origen:** decisión del autor

**Contexto.** ¿Debe el usuario replicar el tono exacto del ejercicio de referencia?

**Decisión.** **No.** Se evalúa el **contorno** del tono, no su valor absoluto.
Si el ejercicio sube de tono de una ida a otra, el usuario debe subir de tono —
no reproducir la frecuencia exacta.

**Razón (del autor).** Replicar el tono exacto a mano es materialmente imposible.
Exigirlo haría el scoring frustrante y pedagógicamente inútil.

**Consecuencias.**
- ✅ El scoring evalúa forma y dirección, que es lo que un profesor corrige.
- ✅ Encaja de forma natural con DTW, que compara formas, no valores absolutos.
- 📌 Las métricas de amplitud se normalizan respecto al rango del propio usuario.

---

## ADR-006 · El sample se embebe en el `.xflare`

**Fecha:** 2026-08-27 · **Estado:** aceptada · **Origen:** decisión del autor

**Contexto.** Un ejercicio necesita su sample. Puede referenciarse o embeberse.

**Decisión.** **Se embebe** el WAV dentro del fichero `.xflare`. Al **importar**,
la app muestra un aviso legal con confirmación explícita indicando que xFlare no
se responsabiliza del contenido distribuido por terceros.

**Razón (del autor).** Un ejercicio debe funcionar tal cual al importarlo. Muchos
ejercicios dependen de un sample concreto — a veces una *sentence* completa — y
referenciarlo por nombre haría que la mitad de los ejercicios compartidos no
sonaran.

**Alternativa descartada.** Referenciar el sample por nombre y hash contra un
banco local. Legalmente más limpio, pero rompe la experiencia de importación, que
es justo el motor de contenido del producto.

**Consecuencias.**
- ✅ Un `.xflare` es autocontenido: se importa y se juega.
- ⚠️ **Riesgo residual de copyright aceptado conscientemente.** El aviso legal
  mitiga, no elimina. Registrado como riesgo R5 en `PLAN.md`.
- 📌 El aviso es **obligatorio y no omitible**. Nunca un checkbox de "no volver a
  mostrar".
- 📌 Los samples **de fábrica** siguen siendo obligatoriamente libres de derechos.
  Nada de "Ahhh" ni "Fresh" ni material de discos comerciales.

---

## ADR-007 · El metrónomo va en la salida principal

**Fecha:** 2026-08-27 · **Estado:** aceptada · **Origen:** decisión del autor

**Contexto.** La propuesta inicial era enviar la claqueta por un canal de salida
independiente.

**Decisión.** **Rechazada.** El metrónomo se mezcla en la salida principal y se
activa o desactiva con **un solo control visible**, sin entrar en ajustes.

**Razón (del autor).** En mesas de sólo dos canales, un canal dedicado a la
claqueta significa perderla. La mayoría de setups de batalla son de dos canales.

**Consecuencias.**
- ✅ Funciona en cualquier mesa, incluidas las de dos canales.
- ✅ Enrutado más simple.
- 📌 Requiere que quitar y poner la claqueta sea un gesto inmediato, mapeable a un
  botón de la mesa (ver tarea 7.6).

---

## ADR-008 · Soporte de hamster / reverse desde el día uno

**Fecha:** 2026-08-27 · **Estado:** aceptada

**Contexto.** Muchos turntablistas invierten el crossfader para cortar con la
mano contraria. **El autor corta en reverse.**

**Decisión.** Ajuste global **normal / hamster**, expuesto como interruptor
visible en la interfaz, no enterrado en preferencias. La orientación viaja además
**dentro del fichero `.xflare`**.

**Razón.** Es el requisito que más se olvida en software de DJ, y afecta a la
mitad del público objetivo. Si un ejercicio se grabó en hamster y se reproduce en
normal, todos los clicks quedan invertidos y el scoring no tiene sentido.

**Consecuencias.**
- 📌 El scoring debe normalizar la orientación antes de comparar.
- 📌 La importación avisa si la orientación del ejercicio no coincide con la del
  usuario, y ofrece convertirla.

---

## ADR-009 · Perfiles de controlador declarativos (JSON), sin scripting

**Fecha:** 2026-08-27 · **Estado:** aceptada

**Decisión.** Los perfiles de dispositivo son ficheros JSON declarativos en
`Resources/Devices/`, más MIDI Learn para lo que no tenga perfil.

**Razón.** Mixxx acabó necesitando scripting en JavaScript para sus mapeos y es
un pozo de complejidad y de bugs difíciles de reproducir. Se empieza declarativo
y sólo se añade scripting si un caso real lo exige.

**Consecuencias.**
- ✅ Los usuarios pueden aportar perfiles sin saber programar.
- ✅ Los perfiles son auditables y diffeables en Git.
- ❌ Algún controlador exótico podría no ser mapeable. Se acepta.

---

## ADR-010 · Sin plataforma online en la v1

**Fecha:** 2026-08-27 · **Estado:** aceptada

**Contexto.** La idea de que un scratcher grabe en modo REC y otros importen su
ejercicio es estratégicamente lo más valioso del proyecto.

**Decisión.** El intercambio se hace **por fichero**: exportar e importar
`.xflare`. Sin servidor, sin cuentas, sin comunidad integrada. Un repositorio de
GitHub para ejercicios de la comunidad cubre la necesidad inicial.

**Razón.** Un servidor implica moderación de contenido, costes recurrentes,
gestión de cuentas y RGPD. Es el 2 % del trabajo por el 90 % del valor hacerlo por
fichero. Se aplaza hasta que haya demanda real.

**Consecuencias.**
- ✅ Coherente con el principio de soberanía del usuario (sin cuenta, sin nube).
- ✅ Cero coste operativo.
- 📌 El formato debe estar **versionado desde el primer commit** para no romper lo
  que la comunidad publique.

---

## ADR-011 · Scoring híbrido: eventos discretos + gesto continuo

**Fecha:** 2026-08-27 · **Estado:** aceptada

**Contexto.** Un golpe de batería es un evento puntual. Un scratch es un gesto
continuo. No se pueden puntuar con el mismo motor.

**Decisión.** Dos motores complementarios.

| Motor | Entrada | Método |
|---|---|---|
| **Discreto** | Clicks del crossfader | Ventanas de juicio ±20 / ±40 / ±70 / ±110 ms |
| **Continuo** | Curva de movimiento del vinilo | **DTW** (Dynamic Time Warping) + métricas derivadas |

**Métricas derivadas — el número crudo no enseña nada.**
- Amplitud del movimiento
- **Simetría adelante/atrás** — el error nº 1 del novato
- **Consistencia entre repeticiones** — lo que separa a un scratcher bueno
- Velocidad de pico
- 🎯 **Desfase entre el click del fader y la inversión del vinilo** — la métrica
  killer. En un flare o un crab, el click debe caer en un punto preciso del
  recorrido. Poder decir *"tu flare va 15 ms tarde en el click de vuelta, por eso
  suena embarrado"* es exactamente lo que corrige un profesor, y **ningún
  software lo mide**.

**Consecuencias.**
- ⚠️ El DTW es costoso: corre **fuera** del hilo de audio, al terminar el intento.
- 📌 Se prototipa primero en Python (`tools/`) sobre curvas grabadas, y se porta
  a Swift cuando los umbrales estén afinados.

---

## ADR-012 · Anti-gamificación explícita

**Fecha:** 2026-08-27 · **Estado:** aceptada

**Contexto.** Melodics es la referencia funcional más cercana. Su interfaz está
bien resuelta, pero su capa de gamificación se percibe como orientada a la
monetización, y la comunidad le reprocha el **"efecto Guitar Hero"**: se acaba
dependiendo de la pista visual y sin ella no se sabe tocar.

**Decisión.** Nada de rachas, vidas, XP, monedas, logros ni confeti. El feedback
es sobrio e informativo. Y se implementa el **Modo Destete** en cuatro niveles:

| Nivel | Qué ve el usuario |
|---|---|
| 1 · Completo | Highway normal |
| 2 · Fade | Las notas se desvanecen a mitad de caída: se anticipa, no se reacciona |
| 3 · Intermitente | Cada 2 compases desaparece el highway y vuelve para verificar |
| 4 · Ciego | Sólo metrónomo y audio. La pantalla puntúa pero no adelanta nada |

**Razón.** El objetivo es que el usuario sepa scratchear **sin la app**. Un
producto que crea dependencia de sí mismo ha fracasado como herramienta de
aprendizaje, por mucho que retenga.

**Consecuencias.**
- ✅ Diferenciación clara y honesta frente a Melodics.
- ❌ Menor retención por enganche. Es intencionado.

---

## ADR-013 · La latencia es una puerta de calidad, no un objetivo

**Fecha:** 2026-08-27 · **Estado:** aceptada

**Contexto.** En una app de batería el usuario golpea y se dispara un sample: la
latencia molesta pero se tolera. **En scratch la app *es* el disco.** El usuario
mueve el vinilo y el sonido debe seguirle.

**Decisión.** Techo duro de **10 ms** round-trip, objetivo 7 ms. Se mide en la
Fase 0, antes de construir nada más. Si no se cumple, **el plan se detiene** hasta
arreglarlo.

**Razón.** Por encima de ~10 ms el scratch se siente "gomoso" y cualquier
turntablista lo detecta al instante. Serato anda por 5-7 ms. Si xFlare no llega
ahí, es injugable por bonita que sea.

**Consecuencias.**
- 📌 Ninguna feature puede comprometer el presupuesto de latencia.
- 📌 Buffer de 64 frames a 48 kHz y reglas RT estrictas (CLAUDE.md §7).
- 📌 Perfilado con Instruments (Audio System Trace) como parte del criterio de
  aceptación, no como pulido posterior.

---

## ADR-014 — Notacion propia (XFN) inspirada en TTM, no derivada

**Estado:** aceptada
**Contexto:** La Periodic Matrix of Skratches / TTM es la convencion visual que los DJs
ya saben leer, pero es obra con copyright y marca registrada, y xFlare se publica bajo
GPL-3.0-only.
**Decision:** Adoptar la *gramatica visual* (tiempo en X, posicion de disco en Y, marcas
de fader sobre la curva) y los nombres comunes de las tecnicas, pero definir un formato
propio (XFN) y un grafismo propio. No incluir material de TTM en el repositorio.
**Consecuencias:** Libertad total de licencia y de evolucion del formato. A cambio,
nuestra notacion puede diferir en detalles del convenio TTM; se documenta en
`NOTATION.md` §4 y se marca lo no verificado en `MATRIX_MAPPING.md` §3.

## ADR-015 — Libreria generativa, no catalogo plano

**Estado:** aceptada
**Contexto:** La matriz tiene ~900 tecnicas. Modelarlas una a una es inmantenible.
**Decision:** Almacenar ~10 patrones de mano y ~16 de fader y componerlos
(`mano × fader × subdivision × ciclos`). Los patrones de fader se expresan en
fracciones de fase (0..1), no en ticks, para que escalen con el tempo.
**Consecuencias:** Anadir un patron de fader anade decenas de scratches. El catalogo
(`tools/catalog.json`) es data, no codigo. Riesgo: algunas tecnicas reales no encajan
en el producto cartesiano (hydroplane, needle skiz) y necesitaran casos especiales.

## ADR-016 — PPQ 480 y tiempo musical, nunca segundos

**Estado:** aceptada
**Decision:** Todo patron se almacena en ticks con PPQ=480. El BPM es un parametro de
reproduccion, no del patron.
**Consecuencias:** Un patron sirve para toda la escalera de tempos del gym sin
recalcularse. La conversion a ms se hace en un unico punto del codigo.

## ADR-017 — El fader se binariza con la curva de corte calibrada

**Estado:** aceptada
**Contexto:** El crossfader de la Rane 72 es analogico; XFN necesita eventos discretos.
**Decision:** Binarizar en el punto de corte medido en la calibracion de Fase 1, con
histeresis para evitar eventos fantasma. Guardar tambien la posicion continua cruda
para analisis posterior.
**Consecuencias:** El scoring de clicks es robusto. La curva cruda queda disponible por
si en v0.2 se quieren evaluar fades no binarios.

## ADR-018 — El gym evalua diagnostico, no nota

**Estado:** aceptada
**Decision:** El resultado principal de un ejercicio es un diagnostico accionable
(que click, cuanto desfase, en que direccion), no un porcentaje. La progresion se
desbloquea por compases consecutivos superados, no por media.
**Consecuencias:** Mas trabajo de analisis (agrupacion de errores, deteccion de sesgo
sistematico vs varianza), pero es el diferenciador real frente a un juego de ritmo.

## ADR-019 — Perfiles de dispositivo en INI plano, sin dependencias

**Estado:** aceptada
**Contexto:** Hace falta un fichero por modelo de mesa, aportado por la comunidad.
Candidatos: JSON (ruidoso de editar a mano, diffs feos), YAML/TOML (necesitan
dependencia externa y hay que auditar su licencia frente a GPL-3.0-only).
**Decision:** INI plano con secciones, parseado por codigo propio (~150 lineas de
Swift). Extension `.conf`.
**Consecuencias:** Cero dependencias, editable por un DJ sin saber programar, diffs
limpios en los pull requests. A cambio, no hay tipos ni anidamiento: se compensa con
claves con punto (`timecode.deck1.ch`) y un validador (`tools/xf_profile.py`).

## ADR-020 — Los perfiles se publican bajo CC0, no GPL

**Estado:** aceptada
**Contexto:** El resto de xFlare es GPL-3.0-only. Los perfiles son datos de
interoperabilidad con hardware aportados por usuarios.
**Decision:** `profiles/` se libera bajo CC0-1.0. Se anade el flag `verified` y solo
es `true` si alguien lo ha probado contra el aparato fisico.
**Consecuencias:** Cualquier proyecto puede reutilizarlos, lo que multiplica el
incentivo para aportar. Se evita pedir cesion de copyright a colaboradores por un
fichero de veinte lineas. La UI debe mostrar siempre la insignia de verificacion,
o el repositorio comunitario pierde toda credibilidad.

## ADR-021 — Captura del crossfader por retorno de audio con tono piloto

**Estado:** propuesta — **VALIDAR EN EL BLOQUE B1**
**Contexto:** El crossfader MAG FOUR de la Rane Seventy-Two (MK1, el hardware de
referencia) es un componente de audio por hardware. La mesa no parece exponer su
posicion por MIDI a terceros; su mapeo MIDI esta orientado a pads y a Serato. Lo
mismo cabe esperar de la DJM-S11.
Sin la posicion del fader, xFlare no puede puntuar clicks, que es el nucleo del
producto.
**Decision:** Que el perfil declare el metodo de captura (`midi`, `audio_return`,
`hid`, `none`). Para mesas de battle, `audio_return`: xFlare mezcla en su salida un
tono piloto inaudible (~19,5 kHz a -40 dBFS), captura el retorno del master de la
mesa por USB y detecta la presencia del tono. Tono ausente = fader cerrado.
**Consecuencias:** Funciona con cualquier mesa que tenga retorno USB, sin depender
del fabricante. Anade la latencia del bucle, que es **constante y medible**: se
determina en calibracion y se resta. Requiere un canal de retorno libre y que el
usuario no filtre agudos en el master.
**Riesgo:** si la validacion de B1 falla, el proyecto necesita un plan C (por
ejemplo, un fader externo MIDI barato en paralelo). No construir nada encima de
esto hasta tener el numero medido.

## ADR-022 — Minimo macOS 11.0 y binario universal Intel + Apple Silicon

**Estado:** aceptada
**Contexto:** Las maquinas objetivo son un MacBook Pro 13" Early 2015 (Intel) y otro
Mac con macOS 12. El primero venia con Catalina 10.15, pero **soporta Monterey**
(su tope; Ventura pide un Mac de 2017 o posterior). Con 10.15 como minimo no existen
`@main struct App: App`, `WindowGroup`, `@StateObject`, `LazyVGrid`, `MIDIEventList`
ni los audio workgroups: habria que escribir la UI casi entera en AppKit.
**Decision:** Minimo **macOS 11.0 Big Sur**. Binario universal `x86_64` + `arm64`.
Se actualiza el MacBook Pro de 2015 a Monterey y pasa a ser la maquina de pruebas
de referencia para Intel.
**Consecuencias:** Se pueden usar SwiftUI 2, el ciclo de vida moderno y CoreMIDI
nuevo. Se pierde Catalina, que era soporte para un sistema que la propia maquina
objetivo puede dejar atras gratis. Toda API posterior a 11.0 queda prohibida salvo
tras `if #available` con ruta alternativa.

## ADR-023 — Toolchain fijada en Xcode 14.2 / Swift 5.7.2

**Estado:** aceptada
**Contexto:** Monterey admite como maximo Xcode 14.2 (Swift 5.7.2); Catalina se
quedaria en Xcode 12.4 (Swift 5.3.2). El techo real lo pone la maquina de desarrollo.
**Decision:** `swift-tools-version: 5.7`. Tests con XCTest. Sin macros, sin
*parameter packs*, sin Observation, sin `swift-testing`, sin concurrencia estricta
de Swift 6. GRDB pinneado a la serie 6.x.
**Consecuencias:** Queda descartada buena parte de los ejemplos recientes que
circulan por internet — que es justo el riesgo cuando el codigo lo escribe un LLM.
Por eso la lista de APIs prohibidas esta tambien en `CLAUDE.md`. Revisar esta ADR
si cambia la maquina de desarrollo.

## ADR-024 — Rendimiento adaptativo en lugar de objetivos fijos

**Estado:** aceptada
**Contexto:** El Intel de 2015 es un doble nucleo con pantalla de 60 Hz. Los 120 fps
y los 10 ms de round-trip se fijaron pensando en hardware moderno.
**Decision:** El renderizador se sincroniza con el refresco real (60 o 120) en vez
de fijar 120. El buffer de audio puede subir de 64 a 128 frames automaticamente al
detectar overloads. El presupuesto de latencia pasa a ser una tabla por maquina:
≤10 ms en la de referencia, ≤15 ms aceptable en el Intel de 2015.
**Consecuencias:** La puerta de calidad de la Fase 0 deja de ser un numero unico.
Si el Intel de 2015 no baja de 15 ms, se documenta como limitacion conocida y la app
lo dice en la pantalla de calibracion, en vez de fingir que va fino.

## ADR-025 — Tres estrellas por criterios ortogonales, no por umbrales del mismo numero

**Estado:** aceptada
**Contexto:** El patron habitual (70/85/95% del mismo indicador) permite sacar la
maxima puntuacion en una toma con suerte y no dice nada de que mejorar.
**Decision:** Cada estrella mide algo distinto: ★ completado (≥70%), ★★ limpio
(≥85% **y cero eventos a 0**), ★★★ solido (≥95%, **σ ≤ 15 ms** y al BPM objetivo).
Las estrellas no bajan nunca; se guarda la mejor marca.
**Consecuencias:** El numero de estrellas es en si mismo un diagnostico. La segunda
castiga el fallo suelto y la tercera exige regularidad, que es lo que separa tocar
de dominar. Requiere calcular σ y comprobar el tempo, no solo un porcentaje.

## ADR-026 — Las variantes son transformaciones generadas, no patrones nuevos

**Estado:** aceptada
**Contexto:** Se quieren variantes de entrada desplazada, recorrido, tempo, swing y
espejo. Escribirlas a mano multiplicaria por diez un catalogo ya generativo.
**Decision:** Una variante es una funcion `Scratch -> Scratch`. Id `ejercicio@variante`.
Para poder recortar por mitad de un movimiento, las fases del carril de disco
admiten un tramo parcial de su curva (`u0`, `u1`) en lugar de partirse en rectas.
**Consecuencias:** Diez variantes salen gratis para los 25 scratches. El maximo de
puntos se calcula por variante, asi que una `offset` puede diferir en un evento
respecto a la base por efecto de borde: se comparan porcentajes, no puntos brutos.
`mirror` (invertir el gesto) queda claramente separado del modo **hamster**, que es
una opcion del perfil de mesa y no una variante.

## ADR-027 — El calentamiento registra pero no penaliza

**Estado:** propuesta (futuribles, disenada en `docs/WARMUP.md`)
**Contexto:** Se quiere un repaso diario de lo dominado con variantes cambiantes.
**Decision:** El calentamiento no modifica estrellas (`countsForStars: false`) pero
si guarda cada toma. Si un ejercicio dominado baja de 2★, se marca **oxidado** y
vuelve a la rotacion.
**Consecuencias:** El valor real del calentamiento no es entrenar, es **detectar
decaimiento antes de que se note en una actuacion**. Obliga a que el esquema de la
base de datos distinga desde el principio entre intentos que puntuan y los que no,
aunque la funcion no se implemente hasta despues de la v1. Por eso se diseña ahora.

## ADR-028 — Universal desde el primer dia, CI en Apple Silicon, Rosetta solo como red

**Estado:** aceptada
**Contexto:** La maquina de desarrollo es Intel, pero la mayoria de Macs vendidos ya
son Apple Silicon y el objetivo es que otros puedan usar la app. Rosetta 2 mantiene
soporte amplio hasta **macOS 27 (otono 2026)** y pierde el soporte general en
**macOS 28 (otono 2027)**; ademas no traduce drivers.
**Decision:**
1. **Binario universal `x86_64` + `arm64` desde la tarea B0.6**, no al final.
2. **CI en runners `macos-14`** (Apple Silicon), gratis e ilimitados en repos
   publicos, para verificar que la logica pasa en arm64 sin comprar hardware.
3. Los **goldens numericos se redondean a 4 decimales** y las comparaciones usan
   tolerancia `1e-9`: la comparacion byte a byte fallaria entre arquitecturas por
   diferencias legitimas de coma flotante.
4. El hilo de audio fija prioridad con `thread_policy_set` **y ademas** se une al
   workgroup del dispositivo (`kAudioDevicePropertyIOThreadOSWorkgroup`), necesario
   en Apple Silicon por la division entre nucleos de rendimiento y de eficiencia.
5. Si se detecta ejecucion bajo Rosetta (`sysctl.proc_translated`), la app **avisa**
   en la calibracion en lugar de fingir que la latencia es normal.
**Consecuencias:** El coste de soportar ambas arquitecturas se reparte en tareas
pequenas desde el principio en vez de convertirse en un muro al final. Se asume que
el audio en tiempo real en Apple Silicon queda **sin verificar en hardware** hasta
que un usuario con un Mac M lo pruebe, y el README lo dice explicitamente.

## ADR-029 — `swift test` no ejecuta con Xcode 14.2 sobre Monterey: plan de tests

**Fecha:** 2026-08-31 · **Estado:** RESUELTA (2026-08-31, misma tarde) — se aplico
la via C · **Matiza:** ADR-023

> **Resolucion (2026-08-31).** `swift test` **ya ejecuta** en la maquina de
> referencia con Xcode 14.2. No hizo falta Xcode 14.1 (via A) ni mover el gate a
> CI (via B).
>
> **Que lo arreglo:** completar la instalacion de componentes del primer arranque
> de Xcode 14.2 — es la via **C** de la tabla, que resulto NO ser de alto riesgo.
> En la primera investigacion `sudo xcodebuild -runFirstLaunch` se habia probado
> con el setup a medias y crasheaba en `IDEInitializePlugIns`. Al **abrir
> Xcode.app 14.2 por la GUI** (se creo `~/Library/Developer/Xcode/` a las ~22:17
> del 2026-08-31) el instalador de componentes adicionales corrio entero e
> instalo, entre otras cosas, el soporte de XCTest de la plataforma macOS
> (`libXCTestBundleInject.dylib` + `libXCTestSwiftSupport.dylib` en
> `MacOSX.platform/Developer/usr/lib/`). Tras eso desaparece la recursion
> infinita en `libswiftCore` y el `SIGSEGV`.
>
> **Verificado:** 4 corridas verdes seguidas — `swift test` con la toolchain de
> Xcode 14.2 / Swift 5.7.2 (12 tests, 0 fallos), `make test` (`TOOLCHAINS=swift`
> → swift.org 5.8.1, 12 tests, 0 fallos) y `make verify` (exit 0, sin `signal
> code 11`).
>
> **Consecuencias aplicadas:**
> - B0.1 y B0.5 pasan a `[x]` — su criterio ("`swift build` y `swift test`
>   pasan") ya se cumple en local.
> - `make test` y `make seal` dejan de llevar la advertencia de "crashean hasta
>   ADR-029"; siguen siendo estrictos, pero ahora pasan.
> - `make verify` mantiene `test-advisory` (tolerante) por si otra maquina de dev
>   entra sin los componentes; el texto ya no habla de bug sin resolver.
> - No se instala Xcode 14.1. ADR-023 no se re-fija: release y tests van los dos
>   con Xcode 14.2 / Swift 5.7.2.
> - CI (ADR sin numero, `.github/workflows/ci.yml`) sigue corriendo `swift test`
>   en los runners; alli nunca estuvo el bug.
>
> **Si reaparece** (Xcode reinstalado, maquina nueva, `xcode-select` a un Xcode
> sin primer arranque): abrir Xcode.app una vez y dejar que instale componentes,
> o `sudo xcodebuild -runFirstLaunch`. Si aun asi crashea, via A (Xcode 14.1 en
> paralelo via `DEVELOPER_DIR`).

---

_Investigacion original (se conserva como registro):_

**Estado inicial:** propuesta — **PENDIENTE DE DECISION** · **Matiza:** ADR-023

**Contexto.** ADR-023 fijo Xcode 14.2 / Swift 5.7.2 porque es el Xcode mas alto que
corre en Monterey. Al levantar el andamiaje (B0.1) se descubre que **`swift build`
funciona, pero `swift test` no ejecuta** en la maquina de referencia (MacBook Pro
Intel, macOS 12.7.6):

- Cualquier bundle de test **Swift** —incluido un `swift package init` vacio— crashea
  con `SIGSEGV`. El crash report muestra **recursion infinita** en
  `libswiftCore.dylib` (`MetadataCacheEntryBase::doInitialization`), disparada
  desde `libXCTestSwiftSupport.dylib` (`type metadata completion function for
  XCUIDeviceProvisioningRequest`).
- `libXCTestSwiftSupport.dylib` se carga desde
  `Xcode.app/.../MacOSX.platform/Developer/usr/lib/` (el correcto, no el de UI) y
  `libswiftCore.dylib` desde el runtime del SISTEMA (dyld shared cache de macOS 12).
  Es una **incompatibilidad de ABI** entre el `libXCTestSwiftSupport` de Xcode 14.2
  y el runtime Swift de macOS 12.7.6.

**Lo que NO lo arregla (probado el 2026-08-31):**
- Instalar la toolchain de swift.org **5.7.3 o 5.8.1** y usarla via `TOOLCHAINS=swift`.
  Compila (5.8.1 compila GRDB; 5.7.3 **no** —bug del verifier con `some
  ColumnExpression`—), pero **XCTest en macOS siempre viene de Xcode**, no de la
  toolchain, asi que el crash persiste identico.
- `DYLD_LIBRARY_PATH` / `DYLD_FRAMEWORK_PATH` hacia un `libswiftCore` mas nuevo:
  ignorado (binario `xctest` firmado con library validation; namespace de dos
  niveles).
- Re-firmar `xctest` ad-hoc + forzar el `libswiftCore` de la toolchain: sigue
  crasheando.
- `xcodebuild test` contra el paquete SPM: crashea antes, en `IDEInitializePlugIns`
  (setup de Xcode incompleto; requiere `sudo xcodebuild -runFirstLaunch`).

**Opciones sobre la mesa (a decidir con el autor):**

| # | Opcion | Coste | Riesgo |
|---|---|---|---|
| A | **Xcode 14.1** (ultimo cuyo XCTest corre en Monterey), en paralelo solo para `swift test` via `DEVELOPER_DIR`. Xcode 14.2 se queda para el build de release. | Descarga ~7 GB con Apple ID | Bajo — es el fix documentado |
| B | **Tests solo en CI** (`macos-13` / `macos-14`). `make verify` local = build + lint + profiles-check; la ejecucion de tests la valida GitHub Actions. | Montar git + repo + CI **ya** (estaba aplazado) | Medio — dev en solitario sin `swift test` local |
| C | `sudo xcodebuild -runFirstLaunch` y reintentar la ruta `xcodebuild test`. | 1 comando con admin | Alto — probablemente el mismo `libXCTestSwiftSupport` crashee igual |

**Decidido:** via **C** — ver el bloque "Resolucion" al principio de este ADR. La
via C resulto bastar (completar el primer arranque de Xcode 14.2), sin el alto
riesgo que se le estimaba.

**Consecuencias segun la opcion:**
- A: dos Xcode instalados; `Makefile` usa `DEVELOPER_DIR=<Xcode 14.1>` solo en
  `test`/`seal`. Se re-fija ADR-023 (release sigue en 14.2, tests en 14.1 / 5.7.1).
- B: el gate real pasa a ser el CI; se adelanta el trabajo de git que el autor
  habia aplazado. `docs/TESTING.md` y las condiciones de SELLADO se reescriben para
  decir "verde en CI" en vez de "verde en `make verify` local".
- C: si funciona, es el mas barato; si no, se cae a A o B.

**La toolchain swift.org 5.8.1** queda instalada en
`~/Library/Developer/Toolchains/` de todos modos: compila el proyecto entero
(GRDB incluido) mas rapido de perfilar que Xcode y sirve de red si Xcode 14.2 da
mas guerra. No resuelve los tests por si sola.

## ADR-030 — xwax 1.8+ es GPL-3.0 → xFlare pasa a GPL-3.0-only

**Fecha:** 2026-08-31 · **Estado:** aceptada · **Corrige:** ADR-003

**Contexto.** ADR-003, la piedra angular de licencias del proyecto, afirma que
`timecoder.c` / `lut.c` de xwax son **GPL-2.0-only** y de ahí deriva todo: JUCE
descartado, nada de Apache-2.0, dependencias solo MIT/BSD. Al descargar xwax para
vendorizarlo (bloque B5.1) se comprueba en la fuente:

- **xwax ≤ 1.7** (2018): cabeceras de `timecoder.c` / `lut.c` = *"GNU General
  Public License version 2, as published by the Free Software Foundation"* — GPL-
  2.0-only, sin "or later". Es lo que ADR-003 asumió.
- **xwax 1.8** (2021-08-18): del `CHANGES`, *"Change to the license to GPL version
  3"*. Desde entonces (1.8, 1.9, 1.10) todo el árbol es **GPL-3.0**; la 1.10
  añade además un aviso explícito de "no copiar a software propietario".

Quien redactó ADR-003 miró una versión antigua (o no revisó el relicenciamiento);
el propio "matiz sobre la 1.10" de ADR-003 se escribió sin notarlo.

**Decisión.**
1. Vendorizar **xwax 1.10** intacto en `Sources/CXFTimecode/vendor/xwax/`
   (`timecoder.c`, `timecoder.h`, `lut.c`, `lut.h`, `debug.h`, `pitch.h`).
2. **El proyecto pasa a `GPL-3.0-only`.** `LICENSE` = texto oficial de la GNU GPL
   v3 de gnu.org. Cabecera `SPDX-License-Identifier: GPL-3.0-only` en todas las
   fuentes propias.
3. Se **levantan** dos prohibiciones de ADR-002/003, ahora sin fundamento:
   - **JUCE**: su opción libre es GPLv3 → *compatible*. No se adopta igualmente
     (la UI es SwiftUI), pero deja de ser una barrera legal.
   - **Apache-2.0**: es *compatible* con GPLv3 (no lo era con GPLv2). Las
     dependencias pueden ser MIT, BSD **o Apache-2.0**. Cualquier dependencia
     nueva sigue necesitando ADR.
4. **No cambia:** App Store descartada (términos incompatibles con la GPL, v2 y
   v3 por igual — precedente VLC); nunca closed-source; vender sí se puede;
   distribución DMG notarizado + Homebrew.

**Alternativas descartadas.**
- *Vendorizar xwax 1.7 (GPL-2.0) y mantener el proyecto GPL-2.0-only:* cero
  cambios de documentación, pero renuncia a soporte de vinilos Pioneer RekordBox
  y a los bugfixes 1.8–1.10, y deja el timecoder congelado en 2018. El autor
  eligió la 1.10 / GPL-3.0.
- *Vendorizar 1.10 y mantener GPL-2.0-only:* ilegal. Código GPLv3 no se combina en
  una obra GPLv2-only.

**Consecuencias.**
- ✅ Código de timecode más nuevo y mantenido; base de licencia sólida y honesta.
- ✅ El espacio de dependencias se amplía (Apache-2.0 entra).
- ⚠️ GPLv3 es más restrictiva con la tivoización y las patentes; para una app de
  escritorio open source distribuida por DMG/Homebrew no cambia nada práctico.
- 📌 `timecoder.c` compila con 2 warnings `-Wshorten-64-to-32` (líneas 438–439).
  Son de xwax; **no se tocan**. Anotado en `docs/TIMECODE.md`.
- 📌 xwax 1.10 no trae intrínsecos SSE ni flags `-msse`: compila igual en `arm64`
  (cierra B0.7 sin trabajo extra).

## ADR-031 — XFClock: contrato de redondeo tick↔hostTime y transporte como valor

**Fecha:** 2026-08-31 · **Estado:** aceptada · **Extiende:** ADR-016

**Contexto.** Al implementar `XFClock` (bloque B2) hay dos decisiones que fijan
contrato público y conviene dejar por escrito antes de sellar el módulo:

1. La conversión entre tick musical y `hostTime` pasa por `Double` (ms y ns
   intermedios). ¿Es "sin pérdida" como pide el criterio de B2.1?
2. ¿Cómo avanza el transporte — con su propio temporizador o empujado desde
   fuera?

**Decisión.**

1. **El dominio canónico es el tick entero.** `Tempo` y `ClockMap` redondean *al
   tick / host-tick más cercano* en cada frontera. La ida y vuelta
   `tick(fromHostTime:) ∘ hostTime(fromTick:)` (y su análoga en ms) devuelve el
   mismo `Tick` exacto para todo el rango de trabajo, porque un tick musical dura
   muchos host ticks (a 120 bpm, ~1 ms ≈ 10⁶ ns) y el error de redondeo
   intermedio nunca se acerca a medio tick musical. Se verifica con 10.000
   valores × 6 tempos × 2 timebases (Intel 1/1 y Apple Silicon 125/3) en los
   tests sellados. **Límite conocido:** un tick anterior al origen del reloj daría
   `hostTime` negativo; se satura a 0 y ahí la ida y vuelta no lo recupera. No
   ocurre en uso real (`anchorHostTime` es un `mach_absolute_time` grande) y está
   cubierto por un test explícito.

2. **`Transport` es un `struct` (valor), sin hilo ni temporizador propio.** El
   driver de audio calcula cuántos ticks han pasado según el **reloj de audio** y
   llama a `advance(by:)`. La cuenta atrás se modela como `position` negativa que
   sube hasta 0; el loop envuelve con un único `%` (cubre varias vueltas por
   bloque). `HostClock.now()` es la única función del módulo que lee el mundo.

**Alternativas descartadas.**
- *Aritmética racional de 128 bits para tick↔host:* se evita el redondeo pero
  añade complejidad (y riesgo de overflow en `Int64`) sin beneficio observable —
  la ida y vuelta ya es exacta con `Double`.
- *Transporte con su propio `DispatchSourceTimer`:* haría el módulo no
  determinista, intestable sin tiempo real, y desincronizaría la autopista del
  sonido (justo lo que `PLAN.md` §8 prohíbe).

**Consecuencias.**
- ✅ `XFClock` se sella sin hardware ni tiempo real; sus tests corren en 0,2 s.
- ✅ La misma `ClockMap` sirve para una toma en vivo y para un `.xfsession`
  reproducido: `XFAnalysis` es una función pura.
- 📌 Tempo variable dentro de una toma **no** está soportado (un `Tempo` por
  `ClockMap`). Si hiciera falta, es un tipo nuevo, no un cambio incompatible.
- 📌 `apiVersion = 1`. Cualquier cambio incompatible de la API de `XFClock`
  necesita ADR nuevo, subir `apiVersion` y re-sellar.

## ADR-032 — El golden de XFNotation se compara campo a campo, no byte a byte

**Fecha:** 2026-08-31 · **Estado:** aceptada · **Aplica:** ADR-028 · **Afecta:** B3.3

**Contexto.** La tarea B3.3 pide que "la libreria compilada en Swift sea identica
a `library-v0.1.json`" con "diff vacio **byte a byte** sobre los 25 scratches".
Pero **ADR-028 prohibe explicitamente** comparar goldens de coma flotante byte a
byte: entre `x86_64` y `arm64` los ultimos bits difieren de forma legitima, y por
eso existen los helpers `XFTestKit.Golden` (redondeo a 4 decimales, tolerancia
`1e-9`), creados en B0.8 "antes de escribir el primer golden".

Ademas, reproducir el `json.dump(indent=2, ensure_ascii=False)` de Python desde
`JSONEncoder` de Swift byte a byte es inviable de entrada (Swift serializa el
`Double` `1.0` como `1`, no como `1.0`), y perseguir esa igualdad no aporta nada.

**Decision.** El golden de B3.3 (y los que vengan) compara **campo a campo**:
enteros, cadenas y enums de forma exacta; dobles via `Golden.round4` +
`Golden.approxEqual` (tolerancia `1e-9`). El texto de TODO.md "byte a byte" se lee
como "sin diferencias observables", no literal.

**Consecuencias.**
- ✅ El golden pasa en las dos arquitecturas sin trucos de serializacion.
- ✅ `GoldenLibraryTests` verifica los 25 scratches (todas las fases y eventos de
  fader) contra `data/scratches/library-v0.1.json`.
- 📌 Si algun dia se quiere un serializador XFN con salida canonica estable (para
  `.xfsession` o para regenerar la libreria desde Swift), es un tipo nuevo con
  sus tests; no cambia este contrato de comparacion.

**Resolucion de las dos decisiones abiertas (2026-09-01, el autor):**
- **B3.6 — `ScoreEvents`:** manda `docs/SCORING.md`. `pitch` pasa a ser **uno por
  semicorchea** (`ppq/4`), no por corchea: asi el 2-Click Flare base da 16 + 16 +
  4 = 36 eventos = 3600, como dice SCORING.md. La formula es uniforme para todas
  las variantes. SCORING.md y `scoring.json` se actualizan para reflejarlo (el
  ejemplo `div16` pasa de "4800" a 5600, coherente con la formula).
- **B3.5 — `subdivision` y `dropout`:** `subdivision` se implementa como
  `Composer.composeWithSubdivision` (recompone con otra `division` ajustando los
  ciclos para conservar la longitud musical). `dropout` **no** entra en
  XFNotation: no transforma el patron, solo decide que compases puntuan y apaga
  la guia visual — es logica de sesion (`XFEngine`).
- Con esto, XFNotation queda **SEALED (2026-09-01)**.

## ADR-033 — `MotionSample` / `FaderSample` en un modulo nuevo `XFPrimitives` (capa 0)

**Fecha:** 2026-09-01 · **Estado:** aceptada · **Afecta:** ARCHITECTURE.md §2/§3, B6, B8

**Contexto.** `docs/ARCHITECTURE.md` situa `MotionSample` y `FaderSample` "en
XFCapture", pero `Take` (en `XFAnalysis`) contiene `[MotionSample]` / `[FaderSample]`
y la regla de oro es que **`XFAnalysis` jamas importa `XFCapture`** (las flechas
solo bajan). Con los tipos de muestra dentro de `XFCapture` el diseno no cierra.

**Decision.** Los dos `struct` de muestra —value types puros, `Sendable`, sin
logica— van a un **modulo nuevo `XFPrimitives`** en el fondo del grafo, sin
dependencias. `XFCapture` (que los produce) y `XFAnalysis` (que los consume)
dependen de `XFPrimitives`; siguen sin verse entre si.

"Capa 0" aqui es **posicion en el grafo**, no codigo de tiempo real: `XFPrimitives`
es Swift y nunca corre en el callback de audio (ese es C).

**Alternativas descartadas.**
- *Ponerlos en `XFClock`:* `XFClock` es "el reloj musical"; meterle tipos de
  captura le cambia la responsabilidad y ya esta sellado.
- *Que `XFAnalysis` dependa de `XFCapture`:* rompe el principio que hace que el
  scoring se pueda desarrollar y testear sin hardware.
- *Fichero de utilidades comun:* justo lo que `CLAUDE.md` prohibe. Un modulo con
  frontera explicita no es eso.

**Consecuencias.**
- ✅ `XFAnalysis` se puede escribir y testear con `Take` sinteticos, sin hardware.
- ✅ `XFPrimitives` es diminuto y se sella de inmediato (2 tipos, 4 tests).
- 📌 Contrato: `MotionSample { hostTime, position, velocity, confidence }`,
  `FaderSample { hostTime, value, isOpen }`. Cambio incompatible → ADR + subir
  `apiVersion` + re-sellar.
- 📌 El grafo de capas de ARCHITECTURE.md §2 se actualiza con la fila y el dibujo.

## ADR-034 — XFEngine: facade `Session` y que una serie se aprueba por streak

**Fecha:** 2026-09-01 · **Estado:** aceptada · **Afecta:** B9.4 (sellado de XFEngine)

**Contexto.** B9.1–B9.3 dejaron tres `struct` valor sueltos: `SessionMachine`
(fases), `BPMLadder` (tempo adaptativo) y `UnlockTracker` (racha de desbloqueo).
Antes de sellar el modulo hay que decidir (a) si se cablean entre si o los
compone `XFApp`, y (b) que hace pasar una **serie**, que ni `docs/CURRICULUM.md`
ni `data/curriculum/` definen con precision — solo dan el `pass` del ejercicio
(`accuracy` + `consecutiveBars`) y la regla de la escalera ("2 series falladas
seguidas bajan, 3 aprobadas seguidas suben").

**Decision.**

1. **Se añade un facade `Session`** (value type, como sus tres piezas) como unica
   puerta de entrada del modulo. El driver de la sesion habla solo con el:
   `beginSeries()`, `recordBar(accuracy:)`, `endRest()`, `recordBoss(accuracy:)`,
   `reset()`. `Session` alimenta a `UnlockTracker` con `(accuracy, currentBPM)`
   por compas, cuenta los compases de la serie y, al llegar a `barsPerSeries`,
   cierra la serie: fija aprobado/suspenso, mueve `BPMLadder` y prepara la
   siguiente. Sellar XFEngine con las piezas sueltas dejaria el contrato a medias
   y cualquier cableado posterior necesitaria re-sellado.

2. **Una serie se aprueba si TODOS sus compases llegan al umbral**
   (`UnlockRule.accuracy`); un solo compas por debajo la suspende. Es la lectura
   "streak, no media" de `docs/CURRICULUM.md` §2, coherente con las 3 estrellas
   (ADR-025). El `minBPM` de la regla **no** entra en el aprobado de serie (la
   escalera ya elige el tempo, gatearlo seria circular); `minBPM` solo lo aplica
   `UnlockTracker` para el desbloqueo de nivel.

3. **El boss no alimenta la racha de desbloqueo.** Es una toma "sin red", una
   medida aparte que va al `Summary` (`bossAccuracy`).

4. **`BPMLadder` gana un `reset()`** (vuelve al `startBPM`, no al primer escalon)
   para que `Session.reset()` — el "otra vez" de la pantalla de resultados —
   deje las tres piezas como al principio.

**Alternativas descartadas.**
- *Componer en `XFApp`:* mueve logica de dominio a la capa de pantallas y hace
  imposible testear el bucle de sesion sin UI.
- *Serie aprobada por media ≥ umbral:* premia "casi siempre bien", justo lo que
  el curriculo evita.
- *Serie aprobada si hay una sub-racha de N buenos:* mas parametros, sin apoyo en
  los datos; con series de 2–4 compases no aporta sobre "todos".

**Consecuencias.**
- ✅ El bucle de sesion completo se testea como valor, sin hardware ni tiempo
   real (`SessionTests`).
- ✅ XFEngine queda **SEALED (2026-09-01)**, `apiVersion = 1`.
- 📌 Contrato publico: `Session`, `SessionMachine`, `SessionPhase`,
   `SessionConfig`, `BPMLadder`, `UnlockRule`, `UnlockTracker`. Cambio
   incompatible → ADR + subir `apiVersion` + re-sellar.
- 📌 Lo que queda fuera y llega despues sin romper esto: elegir el ejercicio de
   repaso por repeticion espaciada (necesita `XFPersistence`), el modo ciego, y
   el calentamiento adaptativo de ADR-027.

## ADR-035 — XFPersistence: esquema completo en `v1`, reglas de producto dentro, catalogo fuera

**Fecha:** 2026-09-01 · **Estado:** aceptada · **Afecta:** B10 (sellado de XFPersistence)

**Contexto.** El bloque B10 pide base local con histrico de tomas, progreso
agregado, dominado, desbloqueo de variantes, repeticion espaciada y calibracion
por dispositivo. Hay que decidir (a) como se versiona el esquema, (b) que reglas
de producto viven en la BD y cuales las pone el llamante, y (c) como se cuenta el
tiempo para la repeticion espaciada.

**Decision.**

1. **Un esquema, una migracion `v1`.** `v1` crea las 10 tablas de todo el bloque
   aunque el codigo que las consulta llegue en tareas sueltas. Regla de oro: una
   migracion publicada **no se toca**; los cambios entran como `v2`, `v3`... y la
   base de cada usuario se pone al dia aplicando solo las que le falten.
   `XFDatabase` abre el fichero y aplica el migrador; `Schema` es interno.

2. **`XFDatabase` es la unica puerta.** Los records (`Attempt`, `AttemptEvent`,
   `PracticeSession`, `ExerciseProgress`, `VariantUnlock`, `ExerciseMastery`,
   `ReviewItem`, `DeviceCalibration`) son publicos como *forma de los datos*; las
   consultas y comandos son metodos sobre `XFDatabase` repartidos por fichero
   (`XFDatabase+Attempts`, `+Progress`, `+Mastery`, `+Unlocks`, `+Review`,
   `+Calibration`).

3. **Las reglas de producto fijas viven aqui**, con su fuente citada: umbral de
   dominado (`masteryBaseStars = 3`, `masteryVariantStars = 2`,
   `masteryVariantCount = 3`, `docs/SCORING.md` §4) e intervalos de repaso
   (`ReviewItem.intervalDays = [1, 3, 7, 21]`, `docs/CURRICULUM.md` §7). Son
   constantes de producto, no configurables.

4. **El catalogo NO entra.** Las reglas que dependen de `data/curriculum/`
   (que variante desbloquea cual, con cuantas estrellas) las construye el
   llamante como `[VariantUnlockRule]` y se las pasa a
   `evaluateUnlocks(exerciseId:rules:at:)`. XFPersistence no lee ficheros del
   bundle.

5. **`countsForStars`** (ADR-027) esta en `attempt` desde `v1`: el progreso
   agregado y el dominado ignoran los intentos de calentamiento; el tiempo total
   practicado los suma.

6. **"Dia" = 86 400 s exactos** en la repeticion espaciada. Para 1/3/7/21 dias
   la precision de calendario no aporta y asi el calculo es determinista y sin
   zona horaria.

**Consecuencias.**
- ✅ Toda la logica de progreso se testea con base en memoria, sin hardware
   (`AttemptHistoryTests`, `ProgressTests`, `MasteryTests`, `ReviewScheduleTests`,
   `CalibrationTests`).
- ✅ XFPersistence queda **SEALED (2026-09-01)**, `apiVersion = 1`.
- 📌 Contrato publico: `XFDatabase` + los records + `VariantUnlockRule` +
   `ProgressSummary` + las constantes de dominado. Cambio incompatible → ADR +
   subir `apiVersion` + re-sellar. Cambio de esquema → migracion nueva.

## ADR-036 — XFRender: layout puro + escena delgada, sincronizado al reloj de audio

**Fecha:** 2026-09-01 · **Estado:** aceptada · **Afecta:** B7 (sellado de XFDesign y XFRender)

**Contexto.** La autopista y el scope son SpriteKit, que no se puede testear sin
GPU en CI. Hay que decidir como se prueba la geometria, como se garantiza "sin
deriva tras 10 min" (`docs/PLAN.md` Hito D) y de donde salen los datos del scope
si las portadoras crudas del timecode viven en la capa RT (`CXFTimecode`).

**Decision.**

1. **Cada vista = un `…Layout` puro + una `…Scene`/`…View` delgada.**
   `HighwayLayout` / `ScopeLayout` son `struct` sin SpriteKit ni estado: dado el
   patron/lecturas + geometria + el tick de AUDIO, devuelven un `…Frame`/`…Figure`
   de puntos ya en coordenadas de vista. `HighwayScene` / `ScopeScene` solo
   pintan ese valor y reutilizan nodos (0 reservas por fotograma). Toda la logica
   se testea sobre los layouts; las escenas solo tienen que compilar.

2. **Sincronizacion al reloj de AUDIO, nunca al frame.** La escena no integra
   tiempo: `SKScene.update(_:)` (que SpriteKit llama al refresco real) lee un
   `currentTick: () -> Double` inyectado que va con el reloj de audio, y dibuja
   ese instante. `HighwayLayout.frame(atTick:)` es una funcion pura del tick:
   `frame(T) == frame(T + lengthTicks)` **bit a bit**, y por tanto no hay deriva
   por muchas horas que pase. Es lo que verifican los tests en vez de un
   cronometro. Bug encontrado al hacerlo: anclar la rejilla de muestreo con la
   division entera *truncada* de Swift rompe esa invariancia con `tMin` negativo;
   se usa division *hacia abajo*.

3. **La capa de usuario y el tinte los alimenta `XFAnalysis`, no `XFRender`.**
   `TracePoint.level` / `ClickHit.offsetMs` llegan ya clasificables; `XFRender`
   solo elige color (`HitLevel.color`) y parte la curva. El render no juzga
   tolerancia.

4. **El scope es un Lissajous reconstruido.** Las dos portadoras en cuadratura
   crudas viven en el hilo RT (C) y no suben hasta capa 2. `ScopeLayout` usa la
   **fase acumulada** (`position · 2π`) para el angulo y la **confianza** para el
   radio: señal limpia → punto sobre la circunferencia; aguja sucia → se hunde y
   `isDegraded`. Suficiente para "el espejo del plato" de `docs/UI_DESIGN.md`
   §3.3.

5. **Golden de render en SVG, no en PNG.** `HighwaySVG.document(...)` serializa el
   frame a texto con coordenadas a 4 decimales en locale C (politica de ADR-028):
   un golden de `x86_64` pasa igual en `arm64`, y el diff es legible. Los 25 en
   `Fixtures/golden/highway/`, regenerables con `make golden-update`.

6. **XFDesign se sella a la vez.** Solo tokens y componentes SwiftUI (macOS 11);
   no tenia decisiones abiertas.

**Consecuencias.**
- ✅ 33 tests de XFRender sin GPU (`HighwayLayout`, capa de usuario, `ScopeLayout`,
   `HighwaySVG`, golden de los 25). XFDesign: 7.
- ✅ XFDesign y XFRender quedan **SEALED (2026-09-01)**, `apiVersion = 1`.
- 📌 Contrato publico XFRender: `HighwayGeometry/Layout/Frame`, `FaderBand`,
   `TracePoint`, `TintedPolyline`, `ClickHit`, `TintedMark`, `HighwaySVG`,
   `HighwayScene/View`, `ScopeReading/Geometry/Layout/Figure`, `ScopeScene/View`.
- 📌 Pendiente y aditivo: medir 60 fps en el Intel de 2015 y 120 en ProMotion
   (B7.2b) — es hardware + `SKView`, no cambia el contrato.

## ADR-037 — Primera distribucion: DMG sin notarizar por GitHub Releases

**Fecha:** 2026-09-01 · **Estado:** aceptada · **Afecta:** B12 (se parte en B12a / B12b)
· **Matiza:** CLAUDE.md §4 ("Distribucion: DMG notarizado + Homebrew")

**Contexto.** Hace falta que testers con hardware real (platos, mesa de batalla,
vinilos de timecode) prueben xFlare antes de invertir en la cadena completa de
publicacion. Notarizar exige cuenta de Apple Developer de pago, `notarytool`,
`stapler` y una vuelta de subida/espera por cada build; la formula de Homebrew
exige un tap y mantener el `sha256`. Todo eso es trabajo que no desbloquea a
ningun tester hoy.

**Decision.** La primera via de distribucion es un **DMG sin notarizar colgado en
GitHub Releases**. El bloque B12 se parte:

- **B12a — DMG para Releases (ahora que toque el bloque).** Empaquetar el `.app`
  y publicarlo. Alcance minimo:
  1. `data/` y `profiles/` dejan de leerse del repo (`RepoContentLoader` via
     `#filePath`) y pasan a recursos del bundle; en la app, `Bundle.module` /
     `DirectoryContentLoader`. `RepoContentLoader` queda solo para tests y `swift run`.
  2. `Info.plist` con `NSMicrophoneUsageDescription` (obligatorio: sin el, la
     captura de timecode falla sin explicar por que), `CFBundleIdentifier`,
     version, icono.
  3. Binario **universal** `x86_64 + arm64` (ADR-028, no se relaja).
  4. **Firma ad-hoc** (`codesign -s -`): en Apple Silicon un `.app` sin ninguna
     firma directamente no arranca. No se notariza.
  5. DMG plano (sin fondo ni layout) con el `.app` dentro. Nota de release con el
     rodeo de Gatekeeper (clic derecho -> Abrir, o
     `xattr -dr com.apple.quarantine xFlare.app`).
  6. GPL-3.0: la release enlaza el tag exacto del fuente correspondiente.
- **B12b — Notarizacion + Homebrew (mas adelante, sin fecha).** El plan final de
  CLAUDE.md §4. No se descarta; se pospone.

**Alternativas descartadas.**
- *Notarizar ya:* coste de cuenta + tooling + latencia por build sin tester que
  lo pida todavia.
- *Distribuir el ejecutable SPM pelado:* no es un `.app`, no tiene `Info.plist`,
  no puede pedir permiso de microfono, no sale en el Dock. Inservible para probar
  el flujo real.
- *Seguir con `RepoContentLoader` en el build distribuido:* la ruta `#filePath`
  del repo no existe en la maquina del tester; la app no encontraria el catalogo.

**Consecuencias.**
- ✅ Testers con hardware pueden instalar y arrancar (con un clic derecho la
  primera vez).
- ✅ B12a es un alcance acotado y verificable; no arrastra la cadena de
  notarizacion.
- ❌ Gatekeeper marca la app como "de desarrollador no identificado" en el primer
  arranque. Asumido y documentado en cada release.
- ❌ Sin auto-update ni canal de Homebrew: actualizar = descargar el DMG nuevo a
  mano.
- 📌 El empaquetado de recursos (`data/`, `profiles/`) deja de ser "pendiente y
  aditivo de XFApp" y pasa a ser el nucleo de B12a.
- 📌 Cuando exista cuenta de Apple Developer, B12b reutiliza el mismo `.app` de
  B12a: solo añade `codesign` con identidad real + `notarytool` + `stapler`.

## ADR-038 — Rejilla de negras y compás en la autopista (re-sellado de XFRender)

**Fecha:** 2026-09-01 · **Estado:** aceptada · **Afecta:** XFRender (SEALED 2026-09-01)
· **Re-sellado:** sí (cambio aditivo)

**Contexto.** La autopista se veía sin referencia de tiempo: el usuario pidió
"ver la rejilla dividida a negras y un poco más oscura la división de compás".
La paleta ya tenía los tokens reservados para esto (`XFColor.grid` "rejilla de
compás", `XFColor.gridBeat` "línea de negra", `docs/UI_DESIGN.md` §2), pero
`HighwayLayout` / `HighwayScene` no dibujaban nada. XFRender está sellado
(ADR-036), así que el cambio va por ADR.

**Decisión.** Añadir la rejilla a XFRender como **cambio aditivo**:

1. `HighwayGeometry` gana `beatsPerBar: Int = 4`. El modelo XFN no lleva compás
   de tiempo y la práctica de scratch es 4/4 salvo que se diga otra cosa; el
   default no obliga a tocar ningún llamador.
2. `HighwayFrame` gana `beatLines: [CGFloat]` y `barLines: [CGFloat]` (x de vista,
   de izquierda a derecha), ambos con default `[]` en el `init`.
3. `HighwayLayout.frame(...)` las calcula: una línea por negra `b·ppq` visible;
   es de **compás** o de **negra** según su posición **dentro del patrón**
   (`wrapped(b·ppq) / ppq  %  beatsPerBar == 0`), **no** según la posición
   absoluta de sesión. Así el conjunto de líneas (valores y clasificación) es
   idéntico en `T` y en `T + L` **para cualquier longitud de patrón** (aunque no
   sea múltiplo de un compás, p. ej. `flare-3c` = 3 negras), y la invariancia
   anti-deriva `frame(T) == frame(T + L)` se mantiene.
4. `HighwayScene` pinta la rejilla en una capa nueva al fondo (`gridLayer`, pools
   reutilizados, 0 reservas por fotograma): negras con `gridBeat` a 1 px,
   compases con `grid` (más apagado) a 2 px.
5. `HighwaySVG` serializa `<line class="grid-beat">` / `<line class="grid-bar">`
   antes de la curva. Los **25 golden** se regeneran (`make golden-update`): el
   diff es exactamente 12 líneas de rejilla por fichero, nada más cambia.

**Alternativas descartadas.**
- *Overlay en XFApp sin tocar XFRender:* la rejilla tiene que ir pegada al mismo
  scroll que la autopista; hacerlo en una segunda capa (SwiftUI o un 2º `SKView`)
  arriesga medio píxel de desajuste. Su sitio es el layout puro.
- *Clasificar compás por posición absoluta de sesión:* rompe `frame(T)==frame(T+L)`
  cuando `lengthTicks` no es múltiplo de `beatsPerBar·ppq`.

**Consecuencias.**
- ✅ La autopista tiene referencia de tiempo en práctica y en los previews SVG.
- ✅ 7 tests nuevos (`HighwayGridTests`), foco en la invariancia. Los 34 sellados
  siguen verdes sin tocarlos. XFRender: 41.
- ✅ Contrato ampliado, no roto: `apiVersion` sigue en 1 (solo campos nuevos con
  default). Entrada en el registro de re-sellados de `docs/MODULE_STATUS.md`.
- 📌 `beatsPerBar` es un parámetro de geometría; si algún día un patrón necesita
  otro compás, se pasa ahí sin más cambios.

## ADR-039 — Audio de la práctica rudimentaria: ruta solo-salida + base como 2º player

**Fecha:** 2026-09-01 · **Estado:** aceptada · **Afecta:** CXFAudioCore (WIP), XFApp

**Contexto.** La práctica rudimentaria (trackpad/teclado, sin mesa) tenía que
sonar: el scratch al mover el plato y una base instrumental pegada al tempo. El
motor `xf_engine` solo tenía `xf_engine_start` **dúplex** (sin tests, y en la
máquina de dev el dispositivo de salida no tiene entrada), y `xf_player` no hace
bucle.

**Decisión.**

1. **`xf_engine_start_output`**: misma AudioUnit HAL que `xf_engine_start` pero
   **sin habilitar la entrada** ni llamar a `AudioUnitRender` de captura. El
   callback pasa `NULL/NULL` al núcleo RT; el ring de entrada queda en silencio.
   Refactor: `xf_engine_start_impl(e, uid, with_input)` y dos wrappers.
2. **Base instrumental = segundo `xf_player`** dentro del motor
   (`xf_engine_load_instrumental(mono, frames, native_bpm)`), mismo patrón de
   swap atómico + 1 retiro que el sample de scratch. Se mezcla tras el
   reproductor y antes del metrónomo, con ganancia propia (0,5 por defecto).
3. **`xf_player` gana `loop`** (aditivo, por defecto 0 = se satura como el plato):
   el cabezal envuelve por módulo y la lectura sinc también, para un bucle sin
   corte perceptible salvo un glitch mínimo una vez por vuelta.
4. **Tempo-lock por resample, no time-stretch**: la base se reproduce a
   `bpm_sesión / native_bpm`. Cambia de pitch al cambiar el tempo — que es
   justo lo que pasa al tirar de un break en el plato, así que es honesto y
   cuesta cero. `native_bpm` va en el nombre del fichero (`080bpm_beat.wav`).
5. **Decodificación** (`AudioAsset`, XFApp): `AVAudioConverter` de una pasada a
   mono float 48 kHz. Se hace fuera del hilo principal al entrar en la práctica
   (un MP3 de 9 MB tarda ~5 s). Los ficheros se leen del repo vía
   `ContentLoader.url(_:)` (nuevo); en el `.app` irán en el bundle (B12a).
6. **Assets**: el `Ahh.wav` es grabación del autor; `080bpm_beat.wav` un loop
   genérico. `Audio/` está en `.gitignore` (nada de audio en el repo hasta
   resolver licencias en B12a).

**Bug encontrado.** `xf_engine_stop` llamaba `os_workgroup_leave` desde el hilo
normal, pero el `join` lo hace el hilo RT en el primer callback:
`os_workgroup_leave` **aborta con SIGILL** si no se llama desde el hilo que unió.
Era un fallo latente del `xf_engine_start` dúplex, nunca ejecutado. Arreglo: al
disponer la AudioUnit el hilo de IO desaparece y la pertenencia se limpia sola;
`stop` solo suelta la referencia del workgroup (`os_release`).

**Alternativas descartadas.**
- *Reutilizar el `xf_engine_start` dúplex en la máquina de dev:* el built-in
  output no tiene entrada; habilitar IO de entrada puede hacer fallar
  `AudioUnitInitialize`.
- *Time-stretch de la base:* complejo y fuera de alcance para algo rudimentario.
- *Audio en Swift con AVAudioEngine:* el scratch quiere el `xf_player`
  (cabezal fraccionario, antialiasing); AVFoundation programa buffers, no hace
  scrubbing sample-accurate.

**Consecuencias.**
- ✅ La práctica suena en el Mac de dev sin mesa. 9 tests nuevos del núcleo RT
  (bucle de `xf_player`, mezcla y ratio de la base) + 6 en XFApp (decodificación,
  `EngineHandle`).
- ✅ Arreglado un SIGILL latente en el `stop` del host CoreAudio.
- 📌 Sin tests del arranque real de CoreAudio (como `xf_engine_start`): se
  verifica con la app corriendo. El scaling velocidad-del-plato → pitch
  (`* 1.6`, acotado a ±8) es a ojo; se afina con la mesa.
- 📌 `EngineHandle` se crea con `maxFrames: 512` (la ruta solo-salida fuerza el
  buffer del dispositivo a ese valor).

### ADR-039 · addenda (2026-09-01, sobre feedback de uso)

- **Zumbido de fondo:** el `xf_player` con el plato casi parado sacaba una
  constante (DC) del kernel sinc quieto, no silencio. `xf_player_set_speed_gate`:
  amplitud ~ `min(1, |v| / gate)`; el motor lo pone a `0,12` para el player de
  scratch (la base instrumental sigue sin puerta). Es ademas fisicamente
  correcto: un vinilo casi parado casi no suena.
- **Lo que se oscurece es la linea, no la pantalla:** se quita el overlay negro a
  pantalla completa. En su lugar, el tramo de la traza del usuario con el fader
  cerrado se pinta apagado (`TracePoint.level = .miss`, que `HighwayScene` ya
  parte en un segmento propio), y la tira de onda baja opacidad.
- **Zoom de la tira de onda:** `visibleFraction` 0,16 -> 0,5 (menos zoom).
- **Alinear "ahora":** la aguja de la tira de onda va a `needleFraction 0,30`,
  la misma fraccion que la cabeza de lectura de la autopista, para que el "ahora"
  coincida en vertical entre las dos vistas. Al entrar en la practica el sample
  se rebobina a 0 (`xf_engine_seek_scratch`).

### ADR-039 · addenda 2 (2026-09-01)

- **La onda de abajo y la autopista comparten posicion.** Antes habia dos
  integradores: `platterPosition` (la traza de la autopista) y el cabezal del
  `xf_player` (la onda). Se separaban. Ahora `LivePracticeView` ancla el cabezal
  a `PracticeSession.normalizedPosition` (0…1 en el rango del patron) cada
  fotograma: abajo del todo = inicio del sample, arriba del todo = final. La
  velocidad se sigue enviando para el pitch/antialiasing dentro del bloque.
- **La onda no se pinta fuera del sample.** `WaveformStripView` solo dibuja
  columnas cuya fraccion cae en `[0,1)`, y la aguja va en `needleFraction`
  (0,30, la de la cabeza de lectura), no en el centro (bug: se pintaba en `w/2`).
- **Fader cerrado NO oscurece la onda**, solo el tramo de la traza del usuario
  en la autopista (`.miss`).
- **Miniatura TTM** de la celda: curva partida donde el fader cierra (hueco =
  mute) + circulo por transicion; sin la barra inferior.

### ADR-039 · addenda 4 (2026-09-01)

- **Glitches / "suena mal":** el `seekScratch` por fotograma escribia el cabezal
  del `xf_player` desde el hilo normal mientras el RT lo integraba -> carrera y
  click periodico. Quitado: solo se manda la velocidad (derivada exacta); el RT
  integra el cabezal y la onda de abajo lee ese mismo cabezal.
- **Headroom anti-clip:** scratch + base + metronomo saturaban en la suma.
  Base 0,5 -> 0,3; master 1,0 -> 0,85.
- **Buffer de audio configurable:** `AppSettings.bufferOptions =
  [64,128,256,512,1024]` (por defecto 512). El motor se crea con ese valor en
  `AppModel.boot`; cambiarlo pide reiniciar. Ajustes se guardan en un plist
  local (`UserDefaults` de suite `app.xflare.settings`) — nada sale de la maquina;
  tapa de momento el hueco del accesor de `setting` en `XFPersistence`.
- **Nombre de usuario** en Ajustes (para etiquetar estadisticas locales).
- **Arranque del plato en el centro** del recorrido (antes pegado a un extremo,
  con medio recorrido muerto). `scrollGain`/`friction` afinados para que un gesto
  normal barra el rango entero y llegue a los dos extremos.
- **Zoom de la onda:** `visibleFraction` 0,5 -> 0,9.
- **`crab` L6 -> L4** en el curriculo (`levels.json`, `exercises.json`:
  `ex-l6-crab` -> `ex-l4-crab`). La libreria agrupa por nivel de curriculo, no
  por el `level` del scratch, asi el crab sale en L4 tambien ahi.
- **Libreria:** cada fila muestra su gráfico TTM al pincharla (se expande) con
  boton Practicar. Sigue listando los 25 trucos que hay (la matriz generativa
  completa es F.0b).

### ADR-039 · addenda 3 (2026-09-01)

- **Rango util del sample:** el baby recorre solo del principio al **0,6** del
  sample (`AudioAsset.scratchUsableFraction`); la cola queda casi inaudible.
  La onda de abajo sigue mostrando el sample entero (la aguja no pasa del 60 %).
  *(Corregido en ADR-041: el pico del patron cae en `2/3` del sample
  —`scratchPatternTopFraction`— y el plato SI puede recorrer hasta el final.)*
- **Glitches:** venian de dos integradores con escalas distintas -> el
  `seekScratch` de cada fotograma daba un salto. Ahora la velocidad que se manda
  al reproductor es la **derivada exacta** de la posicion normalizada del plato
  (`PracticeSession.normalizedVelocity * usableFrames / sr`), asi el anclaje por
  fotograma es una correccion sub-muestra, sin discontinuidad.
- **Mute solo el scratch:** `xf_engine_set_scratch_gain` (0..1, suavizado ~5 ms
  en el hilo RT) escala solo el reproductor de scratch, antes de sumar la base.
  El fader cerrado / Espacio ya no toca la instrumental ni el metronomo.
- **Arranque al tempo de la instrumental:** la practica empieza a
  `instrumentalNativeBPM` (80), no al `startBpm` del ejercicio, para que suene
  cuadrado desde el primer compas.
- **BPM en saltos de 5** (flechas arriba/abajo).
- **Miniatura TTM en todo el L1** (baby, forward-cut, stab, drag).

## ADR-040 — La sombra de la autopista se parte donde el fader esta cerrado

**Fecha:** 2026-09-01 · **Estado:** aceptada · **Afecta:** XFRender (SEALED)
· **Re-sellado:** si (cambio aditivo)

**Contexto.** En notacion TTM el tramo mudo (fader cerrado) **no se dibuja** —
ausencia de linea = mute; el corte lo marcan los circulos ○/●. La miniatura de
la celda ya lo hacia (parte del feedback previo), pero la "sombra a seguir" de
la autopista dibujaba la curva del disco entera, silencios incluidos ("en el
forward cut ... deberia no dibujar los momentos de silencio").

**Decision.** Cambio **aditivo** a XFRender:

1. `HighwayFrame` gana `discSegments: [[CGPoint]]` (default `[]`): la curva del
   disco partida en un tramo por cada intervalo con el fader **abierto**.
2. `HighwayLayout.frame(...)` la construye en el mismo bucle de muestreo de la
   curva: un punto va a su tramo si `PositionSampler.faderState(wrapped) == .open`,
   si no cierra el tramo en curso. La clasificacion es por `wrapped(tick)`
   (posicion dentro del patron), asi que es **periodica con L** y
   `frame(T) == frame(T + L)` sigue cumpliendose bit a bit (misma garantia que
   la rejilla de ADR-038).
3. `HighwayScene` pinta `discSegments` (pool de nodos, 0 reservas/fotograma) si
   no esta vacio; si lo esta, la `discCurve` entera en un solo nodo (compat).
4. `HighwaySVG` emite un `<polyline class="ghost">` por tramo. Los **25 golden**
   regenerados (`make golden-update`): los 18 scratches con actividad de fader
   pasan de 1 polilinea a varias con huecos; los 7 sin fader, sin cambio.

**Alternativas descartadas.**
- *Un flag de "hueco" sobre la `discCurve` entera:* obliga a la escena y al SVG a
  saltarse rangos; mas fragil que emitir tramos ya cortados.
- *Cortar por eventos exactos en vez de por muestreo:* mas preciso pero mas
  codigo en la capa sellada; con el paso de muestreo actual (~20 ticks) los
  cortes largos (forward-cut, chirp) ya dejan hueco, y los brevisimos (flare) se
  leen igual por los circulos.

**Consecuencias.**
- ✅ La sombra de la autopista es notacion TTM correcta: mute = hueco.
- ✅ 4 tests nuevos (`HighwayGhostSegmentsTests`); los 41 anteriores (34 sellados
   + 7 de ADR-038) intactos. XFRender: 45. `apiVersion` sigue 1.
- 📌 Segunda entrada en el registro de re-sellados de XFRender (ADR-038, ADR-040).
   Ambas aditivas y de la misma familia (notacion en la autopista); no indican
   mal diseno de modulo, sino que la notacion se ha ido afinando con uso real.

### ADR-039 · addenda 5 (2026-09-01)

- **Crujidos = clipping.** El recorte duro `[-1,1]` de la salida suena a
  distorsion aspera cuando scratch + base + metronomo se pasan de 1,0 (y el
  `xf_player` sobreoscila en los cambios de direccion). Sustituido por un
  **soft-clip**: transparente hasta |s|=0,7, rodilla suave con `tanh` por
  encima. Nunca recorta duro.
- **Medidor de nivel.** `xf_engine_output_peak()` guarda el pico de la mezcla
  **antes** de limitar, con decaimiento. La practica muestra una barra a la
  derecha (verde/amarillo/rojo) con "CLIP" si pasa de 1,0: se ve si hay que
  bajar volumen.
- **Volumen por ejercicio.** Panel derecho de la practica: dos sliders
  (Sample / Instru) que llaman a `xf_engine_set_scratch_gain` /
  `_set_instrumental_gain` en vivo. *(Corregido en ADR-042: NO se persisten —
  eran la causa de "no suena nada" cuando quedaban a 0 en el plist. Son `@State`
  de sesion, arrancan ambos a 0,5.)*
- **Libreria plana.** Deja de agrupar por nivel: lista unica de todos los
  trucos, ordenada por nombre, con el buscador y el filtro de familia.
- **Loop instrumental:** el autor lo cambio a `080bpm_beat.wav`.

## ADR-041 — Hueco encima del patron en la autopista (`patternFill`)

**Fecha:** 2026-09-01 · **Estado:** aceptada · **Afecta:** XFRender (SEALED)
· **Re-sellado:** si (cambio aditivo, sin regenerar golden)

**Contexto.** En la practica, el pico del patron (p. ej. el baby) mapea a **2/3
del sample**, y el usuario puede scratchear mas alla, hasta el final. Con el
mapeo vertical actual (`positionRange` -> banda entera) esa traza extra se sale
por arriba de la autopista y no se ve.

**Decision.** `HighwayGeometry` gana `patternFill: CGFloat = 1.0` (fraccion de la
banda, medida desde abajo, que ocupa el `positionRange` del patron).
`HighwayLayout.frame()` escala su `y(forPosition:)` por `patternFill`: el patron
llena `[yBottom, yBottom + patternFill·(yTop-yBottom)]` y una posicion **por
encima** de `positionRange.upperBound` (la traza del usuario pasandose del pico)
se extrapola linealmente hacia el hueco de arriba, hasta `yTop` (final del
sample). La practica pasa `patternFill = 2/3`.

**Consecuencias.**
- ✅ El fantasma ocupa los 2/3 de abajo; el tercio de arriba es el "resto del
  sample" y la traza del usuario entra ahi al pasarse del pico.
- ✅ **Sin regenerar golden**: los golden y el resto de tests usan el default
  `patternFill = 1.0` (comportamiento identico al anterior). 1 test nuevo.
- ✅ Invariancia `frame(T) == frame(T+L)` intacta (`patternFill` es constante).
  `apiVersion` sigue 1. Tercera entrada en el registro de re-sellados de XFRender
  (ADR-038, ADR-040, ADR-041), todas de la misma familia (mapeo de la autopista).

## ADR-042 — El ancla de posicion del scratch mueve por velocidad, no a saltos

**Fecha:** 2026-09-01 · **Estado:** aceptada · **Afecta:** CXFAudioCore (WIP)

**Contexto.** ADR-039 anclaba el cabezal del player de scratch a una posicion
objetivo (`xf_engine_set_scratch_target`) corrigiendo **un 15% del error por
bloque** con `xf_player_set_playhead`. Al mover el plato, la integracion de
velocidad del player y el objetivo (que Swift refresca a 60 Hz) divergen dentro
del bloque; el salto de cabezal al final del bloque metia una **discontinuidad
de forma de onda** cada 10-20 ms -> crujido de ~50 Hz audible al scratchear.
Subir el buffer no lo quita: no es un underrun, es una discontinuidad que
metemos nosotros.

**Decision (forma final).** **La velocidad manda** — es lo que un resampler
quiere. El objetivo de posicion NO mueve el cabezal: es un **trim anti-deriva
acotado**. Nuevo `xf_player_set_target_playhead(frame)`: si `frame >= 0`, cada
muestra suma a la velocidad `(frame - cabezal)·seek_coef` (one-pole ~250 ms),
**topado a ±0.015 frames/muestra** (~1.5% de pitch). `frame < 0` lo suelta.

Historia de intentos fallidos (todos con el objetivo llegando a **escalones de
60 Hz** desde Swift):
1. **Salto de cabezal 15%/bloque** (`set_playhead`): discontinuidad de forma de
   onda cada bloque → **crujido** de ~50 Hz.
2. **Velocidad media de bloque** integrada por el player: player-glide +
   correccion = dos one-pole en cascada → **overshoot** y oscilacion.
3. **One-pole rapido per-sample sobre la posicion** (~12 ms): el cabezal
   **perseguia cada escalon de 60 Hz** de forma audible → barrido de pitch
   repetido, un **"laser"**.

El trim acotado mata las tres: la correccion nunca supera el 1.5% de pitch, asi
que ni salta, ni oscila, ni barre. La velocidad (que el player ya suaviza con su
glide de 5 ms) hace todo el trabajo real.

**Consecuencias.**
- ✅ Sin crujido, sin overshoot, sin barrido: la correccion de posicion es
  inaudible por construccion (±1.5% de pitch como mucho).
- ✅ Anti-deriva: el scratch no se separa de la posicion de la autopista a la
  larga (recupera ~720 frames/s, de sobra para la deriva real, que llega de los
  topes del recorrido).
- ✅ `xf_player_set_target_playhead` es RT-SAFE (escribe 2 campos, sin bucles);
  se llama desde `xf_engine_render`. `testElAnclaEsUnTrimAcotado` cubre las 3
  propiedades (sigue pegado con velocidad coherente / trim topado por bloque /
  soltar lo desactiva).
- ➕ **Buffer de audio en caliente:** `EngineHandle.restartOutput(maxFrames:)`
  para/destruye/recrea el motor y recarga el audio desde sus propios buffers, sin
  reiniciar la app. El panel de pruebas de la practica trae un selector que lo
  dispara (para aislar si el buffer es la causa de un crepiteo). `bufferOptions`
  llega a 2048.

## ADR-043 — Variantes cableadas a la practica + escalera de subdivision del gym

**Fecha:** 2026-09-02 · **Estado:** aceptada · **Afecta:** XFApp, `data/curriculum/variants.json`

**Contexto.**
1. Las variantes de `variants.json` (offset/amplitude/mirror/swing/subdivision)
   estaban definidas y con su UI de desbloqueo, pero **no se aplicaban al patron
   que se practica**: `AppModel.scratch(exerciseId:)` devolvia siempre la base.
   El `Catalog` ni siquiera cargaba `PrimitiveSet`.
2. Los trucos del gym deben **empezar ocupando 1 compas** (un ciclo del patron
   por compas) y subir de nivel metiendo divisiones entre 2 hasta corcheas.
3. Cambiar los `div` del catalogo base rompe goldens de XFRender y tests
   sellados (`ScoreEventsTests` fija `flare-2c-16` en div 1/16).

**Decision.**
- **`CatalogLoader` carga `PrimitiveSet`** de `data/primitives/*.json` y lo
  guarda en `Catalog` (aditivo; el `.error(...)` de arranque lo cubre si falta).
- **`VariantInfo` lleva un `Transform` tipado** (parseado de `transform`+`params`
  del JSON). **`AppModel.scratch(exerciseId:variantId:)`** lo aplica sobre la
  base: `amplitude`/`mirror`/`swing` sobre el `Scratch` ya compuesto;
  `subdivision`/`offset` recomponen desde primitivas (`Composer`). `dropout`
  (blind) no toca el patron (es logica de sesion) -> identidad aqui. Si la
  recomposicion falla, se practica la base.
- `AppRootView` pasa el `variantId` de `.practice(_, variantId)` a la vista y a
  `model.scratch(...)`. El nombre del ejercicio muestra la variante.
- **Escalera de subdivision** como **3 variantes nuevas** en `variants.json`,
  todas `transform: subdivision`: `sub-1-2` (1/2, 1 ciclo/compas, sin candado —
  el punto de entrada del gym), `sub-1-4` (1/4, 2★ en `sub-1-2`), `sub-1-8`
  (1/8, 2★ en `sub-1-4`). Cap en corcheas ("de momento"). `composeWithSubdivision`
  ya conserva la longitud musical y ajusta los ciclos.
- La **ficha del truco** (ADR ficha, Task A) arranca seleccionando `sub-1-2` si
  esta; es la lista "variantes con su puntuacion" que pidio el usuario, ahora con
  la escalera dentro.

**Por que asi y no cambiando el catalogo.** Anadir variantes es **aditivo**: el
catalogo base, los golden SVG y los tests sellados de XFNotation/XFRender quedan
intactos. `base` sigue con `unlock: null` (los tests de desbloqueo que trepan
desde `base` no se tocan). La escalera es una familia independiente.

**Consecuencias.**
- ✅ Todas las variantes hacen algo por fin (incluida `div16`, que era inerte).
- ✅ El gym tiene su rampa 1→2→4 ciclos por compas sin romper nada sellado.
- ⚠️ `subdivision` a `1/2` sobre un truco cuya base ya es `1/16` (scribble,
  hydroplane) da 1 ciclo/compas de todas formas — coherente. Su `base` a 1/16
  sigue siendo una variante mas fina, fuera del cap del gym.
- ⚠️ Falta el **avance automatico** por la escalera (como la de BPM, sellada en
  XFEngine): de momento el usuario elige el escalon en la ficha. B-posterior.

## ADR-044 — Phantom clicks en la sombra de la autopista (XFRender re-sellado)

**Fecha:** 2026-09-02 · **Estado:** aceptada · **Afecta:** XFRender (SEALED)
· **Re-sellado:** sí (cambio aditivo)

**Contexto.** El manual TTM (leído en ADR / `MATRIX_MAPPING.md §3b`) define el
*phantom click*: en los scratches de fader abierto (baby, flare, orbit), cuando
el disco cambia de sentido se para un instante y ese silencio corta el sonido
**sin mover el fader**. Un flare de 2 clicks + 2 phantom suena a 4. La autopista
no lo marcaba.

**Decisión.** `HighwayFrame` gana `phantomMarks: [CGPoint] = []`.
`HighwayLayout.frame()` los calcula: por cada copia visible del patrón, en cada
frontera de fase donde el sentido pasa de `fwd` a `rev` o al revés, si el fader
está **abierto** ahí (mirado por `wrapped`, posición en el patrón), un punto
sobre la curva. `HighwayScene` los pinta como un **tick vertical corto y
apagado** (`phantomLayer`), más discreto que el círculo del corte de fader;
`HighwaySVG` emite `<line class="phantom">`. La miniatura de XFApp
(`TTMThumbnail.phantomCuts`) hace lo mismo.

**Consecuencias.**
- ✅ Se ve dónde el sonido se corta "solo", que es media notación de un flare.
- ✅ Aditivo: campo con default, dibujado detrás de los `hitMarks`. Clasificación
  por `wrapped` ⇒ periódica con L, invariancia `frame(T) == frame(T+L)` intacta.
  `apiVersion` sigue 1.
- 🔄 25 golden SVG regenerados (solo añaden líneas `class="phantom"`).
- Cuarta entrada del registro de re-sellados de XFRender (ADR-038/040/041/044),
  todas de la misma familia (qué se dibuja en la autopista).

## ADR-045 — Llamada y respuesta: el fantasma mueve el sample

**Fecha:** 2026-09-02 · **Estado:** aceptada · **Afecta:** XFApp (`PracticeSession`, `LivePracticeView`)

**Contexto.** Hasta ahora el fantasma de la autopista era solo una guía visual;
el audio lo movía únicamente el plato del usuario. Para entrenar de oído hace
falta que **la máquina toque** la frase y tú la imites.

**Decisión.** `PracticeSession` gana un modo `crPhase: {off, listen, respond}`:

- **`listen`**: en cada paso, `platterPosition` se fija a la posición del
  **fantasma** en ese tick (`PositionSampler.position(of:atTick: wrapped)`),
  `platterVelocity` a su derivada, y `faderClosed` al estado de fader del patrón.
  Como `onAdvance` empuja el motor de audio desde `platterPosition`/`Velocity`,
  el fantasma **mueve el sample**: se oye el scratch objetivo. El input del
  trackpad/teclado se ignora.
- **`respond`**: normal — el plato lo mueves tú. El fantasma de la autopista se
  **atenúa** (`opacity 0.12`) para que imites de oído, no siguiendo la línea.
- Alterna cada `crBars` compases (la máquina toca `crBars`, tú imitas `crBars`).
  `crBars` se elige desde la vista, forzado a **par** y a `[2, 16]`.

`LivePracticeView`: el control vive en el **panel derecho** (no en la barra
superior): botón (Llamada y respuesta / Escucha… / Tu turno) + un `−/+` de
compases (`×2` / `÷2`). El gain del scratch pasa a un
`.onChange(of: session.faderClosed)`, así el mute funciona tanto si cierra el
fader el usuario como el fantasma.

**Consecuencias.**
- ✅ Práctica de oído real sin necesitar aún el scoring (`XFAnalysis`).
- ✅ Todo en XFApp, nada sellado. `PositionSampler` (XFNotation) ya daba la
  posición y el fader del patrón en cualquier tick.
- ⚠️ Sin comparación automática llamada↔respuesta todavía (eso es `XFAnalysis`).
  De momento el oído es el juez.
- Nota aparte (bugfix): la onda de la instrumental (ADR-044 previa) escalaba por
  `ancho/1000`; `HighwayScene` con `.resizeFill` **no escala** el contenido
  (redimensiona la escena), así que la tira iba desincronizada. Ahora dibuja en
  píxeles 1:1 con el mismo `playheadX`, igual que la autopista.

## ADR-046 — Analisis de tempo de la instrumental + rejilla sobre los golpes

**Fecha:** 2026-09-02 · **Estado:** aceptada · **Afecta:** XFApp

**Contexto.** La rejilla de compas de la tira de la instrumental se dibujaba
sobre un 4/4 nominal a 80 BPM fijos (`AudioAsset.instrumentalNativeBPM`). Si el
bucle no esta exactamente a ese tempo, o no empieza en el "1", la rejilla no cae
sobre los golpes. Ademas la tira iba desplazada de la autopista.

**Decision (dos partes).**

1. **Alineacion tira ↔ autopista (bugfix).** `HighwayScene` con `.resizeFill`
   hace `geometry.size = size` (ancho REAL de la vista) en `didChangeSize`, asi
   que su cabeza de lectura queda en `anchoReal · playheadFraction`, no en el
   nominal (1000·0.30). La tira usaba el nominal → offset constante. Ahora la
   tira calcula `playheadX = w · playheadFraction` (mismo `w`, misma columna).

2. **`TempoAnalyzer`** (XFApp, offline, sin dependencias):
   - **Tempo.** Si el nombre del fichero trae un BPM (`080bpm_beat.wav`,
     `TempoAnalyzer.bpmHint`) se usa ese — el usuario suele saber el tempo de su
     loop. Si no, envolvente de onset (flujo de energia RMS) → autocorrelacion,
     ponderada por un **prior de tempo** (gaussiana en log2 centrada en 120 BPM,
     estilo Ellis 2007) que resuelve la ambiguedad de octava.
   - **Fase.** Correlacion de la envolvente con un tren de pulsos al periodo
     hallado → frame del primer golpe fuerte.
   - **Bucle corto.** Si dura <= 16 s y ~un numero entero de negras, se cuadra
     el BPM a eso (`isShortLoop`). En pistas largas no.

   Al cargar la practica: se analiza la instrumental (con el hint del nombre),
   se **rota** el PCM para que empiece en el "1" (`phaseFrames`), se carga con
   ese `nativeBPM`, la sesion pasa a ese tempo (`session.setBPM`) y el reloj se
   pone a 0 (`resyncClock`) al arrancar el audio. `tick 0` = primer golpe y la
   rejilla (autopista y tira) cae sobre los golpes.

**Consecuencias.**
- ✅ La rejilla sigue el ritmo real de la cancion, no un 4/4 asumido a 80.
- ✅ Con el hint del nombre, el tempo es exacto sin depender del detector.
- ✅ Todo XFApp, nada sellado. `TempoAnalyzer` es puro y testeable (tren de
   clicks sintetico + el fichero real del repo).
- ⚠️ Sin hint, la autocorrelacion + prior puede errar la octava en material
   muy ambiguo. Sin deteccion de compas (asume 4/4) ni de cambios de tempo.
   Rotar una pista larga es una copia de ~40 MB (una vez, en background).

## ADR-047 — Visualizacion de la practica: reloj extrapolado + onda con color

**Fecha:** 2026-09-02 · **Estado:** aceptada · **Afecta:** XFApp

**Contexto.** La autopista y la tira de la instrumental daban tirones y se
descorrelacionaban con el tiempo (en captura estatica cuadraban). Y la onda de
la instrumental se veia "cuadriculada".

**Decision.**

1. **Reloj extrapolado.** Habia tres relojes independientes: el timer de
   `PracticeSession.advance` (con jitter), el timer de redibujo de la tira y el
   display link de SpriteKit. Cada uno muestreaba `currentTick` en un instante
   distinto → tirones y desfase acumulado. Ahora `PracticeSession.tick()` NO
   devuelve el crudo: extrapola con el reloj de pared
   `currentTick + (ahora - ultimoPaso)·ritmo` (acotado). La autopista y la tira
   llaman las dos a `tick()` → ven el **mismo** valor y el scroll es suave. Sin
   timer (tests) devuelve el crudo.

2. **Onda mas fina.** `WaveformColored` sustituye a `WaveformEnvelope` para la
   instrumental: ~1 tramo/ms (antes ~165 ms para una pista de 4 min) e
   **interpolacion lineal** entre tramos al pintar. Adios cuadricula.

3. **Color por frecuencia (tipo Serato).** 3 biquads RBJ (LP 180 Hz, HP 2200 Hz,
   medios = resto) → RMS por banda por tramo, normalizado, compuesto a RGB
   (grave = naranja calido, medio = verde, agudo = azul). Es analisis offline al
   cargar. xwax **no** hace esto (solo decodifica timecode + el Lissajous); es
   codigo propio, ~1 biquad.

4. **Las dos tiras son `SKScene` (addendum).** Intento 1: imagen 1:1 + `Timer`
   60 Hz → temblaba (timer no en fase con el vsync). Intento 2: `CVDisplayLink` +
   `needsDisplay` → el redibujo del `NSView` sale **diferido** 1-2 frames
   respecto al `SKView` de la autopista → la rejilla de la tira se veia
   **desfasada** de la de la autopista al desplazarse. Solucion: las dos tiras
   son ahora un `SKView` con `WaveformScene` (`.looping` / `.windowed`), asi el
   `update(_:)` corre en el MISMO reloj de frame que `HighwayScene` → cero
   desfase. La onda va como **textura pre-renderizada** (`WaveformImage`, ancho
   natural del bucle); cada frame solo se mueve el sprite. El sample
   (`WaveformStripView`) usa la misma `WaveformColored` → color por frecuencia
   tambien abajo.

5. **Bug de aislamiento de tests.** `AppSettings.allUnlocked` salia `false` en la
   app porque un test hacia `m.settings.allUnlocked = false` y el `didSet`
   persiste en el **mismo** `UserDefaults(suiteName: "app.xflare.settings")` que
   lee la app. Quitado ese mutation del test (la puerta se prueba en
   `AssemblerTests` sin tocar `settings`). Pendiente: los tests de `AppModel`
   deberian usar una suite de UserDefaults propia.

6. **Crash Metal.** La imagen de la onda de la instrumental salia a ~36 840 px
   de ancho (307 negras · 120 px/negra); el maximo de textura de Metal en la
   GPU Intel de la maquina de referencia es 16 384 → `SKTexture` aborta al
   subirla. Cap del ancho de la imagen a 16 000; el `SKSpriteNode` la escala al
   ancho real del bucle (filtrado lineal, sin perdida visible).

**Consecuencias.**
- ✅ Scroll suave (vsync) y autopista/tira siempre sincronizadas.
- ✅ Onda legible, fina y con informacion de frecuencia, arriba y abajo.
- ✅ Todo XFApp, nada sellado, sin dependencias (biquads + `CVDisplayLink` de
  CoreVideo, framework del sistema).
- ⚠️ El color es una mezcla de 3 bandas anchas, no un espectrograma. Suficiente
  para "ver" el bombo/caja/charles, no para analisis fino.


## ADR-048 — Practica rudimentaria: una sola escena (autopista + ondas)

**Fecha:** 2026-09-02
**Estado:** aceptada
**Contexto.** Con ADR-047 las dos tiras de onda pasaron a ser `SKView` con
`WaveformScene`, en el mismo reloj de frame que `HighwayScene`. Pero seguian
siendo `SKView` **separados** del de la autopista: cada uno recibe su callback de
vsync por su cuenta y, en un frame en que se dibuja uno y no el otro (frame
perdido bajo carga), la rejilla de compas de la tira de la instrumental se queda
un fotograma por detras de la de la autopista → se ve "temblar" / desfasada al
desplazarse. Ademas el usuario pidio mover la onda del sample de una tira
**inferior** a un **rail vertical a la izquierda** (como la "linea de sample" del
manual TTM): al avanzar la posicion del sample en la autopista se ve el recorrido
a traves de el.

**Decision.** Una **unica** `PracticeScene` (XFApp) dibuja las tres cosas en el
mismo `update(_:)`, leyendo el reloj UNA vez por fotograma:

1. **Autopista.** Se sigue calculando con `HighwayLayout` (publico y puro, de
   XFRender, **modulo sellado**: no se toca). `PracticeScene` solo **pinta** su
   `HighwayFrame`, replicando nodo a nodo el `render()` de `HighwayScene`
   (rejilla, curva/tramos, cabezal, carril, marcas ○/●, phantom clicks, traza
   del usuario). Reutiliza nodos (pools) → sin reservas por frame.
2. **Tira de la instrumental** (banda superior). Su contenedor esta desplazado
   por el mismo ancho de rail que el de la autopista y usa **exactamente** la
   misma formula de X que `HighwayLayout` (`playheadX + (t - now)·pxPerTick`) y
   la misma clasificacion negra/compas (`wrapped` sobre la longitud del patron).
   Como es el mismo `now` y el mismo frame, las lineas de las dos coinciden
   hasta el pixel. **Imposible** que se desfasen.
3. **Rail del sample** (columna vertical izquierda, 44 pt). La onda
   (`WaveformColored` → `WaveformImage`) se renderiza horizontal y el sprite se
   gira 90º: el inicio del sample queda abajo y el final arriba. Una aguja
   horizontal marca `EngineHandle.scratchProgress` (0…1): al mover el plato
   -o el fantasma en el call & response- la aguja recorre el sample.

`LivePracticeView` deja de usar `HighwayView` + `InstrumentalStripView` +
`WaveformStripView`; estos dos ultimos y `WaveformScene` se borran.

**Consecuencias.**
- ✅ Autopista y tira jamas se desfasan: un reloj, un frame, una escena.
- ✅ El rail vertical enseña "donde va" la reproduccion dentro del sample.
- ✅ `HighwayView`/`HighwayScene` (sellados) siguen intactos y disponibles para
  `PracticeView` (la pantalla de sesion "de verdad", aun sin cablear).
- ⚠️ `PracticeScene` **duplica** el pintado de `HighwayScene`. Es deliberado: no
  se puede meter contenido propio en una escena sellada. Si `HighwayFrame` gana
  campos, hay que replicar el pintado aqui (o, mejor, cuando exista sesion real,
  unificar en XFRender con su ADR).
- ⚠️ Mas nodos en una sola escena; en la maquina Intel de referencia va fino a
  60 fps (todo son `SKShapeNode` con path nuevo por frame, igual que ya hacia
  `HighwayScene`).

**Iterado (2026-09-02, feedback).**
- **Rejilla continua.** Las lineas de negra/compas y el cabezal ya no se dibujan
  por contenedor (dejaban un hueco visible entre la tira y la autopista): van en
  una capa a nivel de escena, de `y=0` a `y=alto de escena`, en la X de
  `HighwayFrame.beatLines/barLines` desplazada por `railWidth`. Una sola linea
  atraviesa tira + autopista.
- **Recorte.** `highwayContainer` y `stripContainer` van dentro de un
  `SKCropNode`: su contenido con X negativa (curva/traza muestreada a la
  izquierda del cabezal) ya no se pinta encima del rail del sample.
- **Aguja del rail = linea de la autopista.** La aguja del rail izquierdo ya no
  sale de `scratchProgress` (frames del sample, no cuadraba); sale de la Y de la
  linea del usuario -o del fantasma- bajo el cabezal en el `HighwayFrame`.

**Iterado (2026-09-02, feedback imagen #16/#17). Slider de amplitud.**
- El rail izquierdo ocupa **toda** la franja de la autopista (`0…hh`): es el
  sample ENTERO. No se estira ni encoge con nada.
- La **traza del usuario** tampoco tiene techo. Intento con `HighwayLayout.y()`
  (imagen #17): seguia topando a 2/3 (su `y()` mezcla `patternFill` con la
  extrapolacion n>1 de forma que el borde no cae donde toca). Solucion (imagen
  #18): `PracticeScene.renderUserTrace` dibuja la traza **aparte**, sin pasar
  por `HighwayLayout.frame(userTrace:)`, con un mapeo LINEAL propio: el rango
  entero del plato `[posLo, posLo + span/(2/3)]` ocupa toda la banda de la
  curva, de abajo del todo (inicio del sample) a arriba del todo (final). El
  mapeo de AUDIO (`normalizedPosition`) usa la constante `scratchPatternTopFraction`,
  sin amplitud. `PracticeSession` no sabe nada de amplitud.
- El slider **"Amplitud"** solo escala la **onda FANTASMA** (la que hay que
  seguir): `PracticeScene` mete la curva + marcas del fantasma en un
  `ghostContainer` con `yScale = ghostScale` alrededor del borde inferior de la
  banda (`ghostScale = 1.5·amplitud`; a 2/3 -> escala 1, pico a 2/3; a 1.0 ->
  1.5, pico arriba del todo). La traza del usuario y la rejilla NO se escalan.
- `curveInset`/`laneHeight` a 8: el fantasma y la traza arrancan casi pegados al
  borde inferior, como el rail.
- (Anula las notas de #15 -`patternFill` fijo `1.0`- y del primer intento de #16
  -amplitud tocando `posHi` y el audio-.)
- **Rejilla por negra ABSOLUTA.** `PracticeScene` ya no usa la clasificacion
  negra/compas de `HighwayFrame` (`HighwayLayout` la hace por `wrapped` sobre la
  longitud del patron, para su invariancia anti-deriva; si el patron no mide un
  numero entero de compases, los compases salen irregulares). La hace el propio
  `PracticeScene.gridLines`: una linea por negra, compas cuando el indice de
  negra ABSOLUTO es multiplo de `beatsPerBar` (el "1" es el tick 0, que
  `resyncClock()` alinea con el primer golpe). Compases regulares siempre.


## ADR-049 — Tecla P: congelar la practica sin salir

**Fecha:** 2026-09-02
**Estado:** aceptada
**Contexto.** Practicando conviene poder parar el tema en un punto para repetir
un gesto sobre esa parte del sample, sin perder la posicion ni salir de la
pantalla.
**Decision.** `P` alterna `PracticeSession.frozen`. Congelado: el reloj musical
no avanza (`advance` sale antes; `tick()` devuelve el crudo sin extrapolar) y la
traza deja de crecer -> la autopista se queda quieta "sin dibujar". Pero el
plato conserva su fisica y se sigue llamando a `onAdvance`, asi que **sigues
scratcheando el sample** sobre la imagen quieta. La instrumental y el metronomo
se paran con el transporte (`engine.setTransport(playing: !frozen)`).

Para que el transporte pare **de verdad** la base instrumental hubo que
tocar el motor (CXFAudioCore, WIP): su `render` reproducia el `xf_player` de la
instrumental incondicionalmente; ahora es `if (ip && playing)`. Al pausar no se
renderiza -> su cabezal se queda quieto y al reanudar sigue donde estaba. El
reproductor de scratch NO se toca (por eso sigues scratcheando congelado). Test
`testTransportePausadoCallaLaBasePeroNoRevienta`.
**Consecuencias.**
- ✅ Repetir un trozo concreto sin manejar el transporte a mano.
- ⚠️ `set_transport(playing:false)` ahora **silencia** la base (antes solo
  paraba el reloj musical). Es lo que queria decir "transporte parado"; ningun
  sitio dependia de lo contrario.
- ⚠️ Congelado, el `PracticeSession` sigue latiendo a 60 Hz (solo mueve el
  plato): coste nulo.


## ADR-050 — Miniatura TTM simple + variantes en pausa (feedback 2026-09-02)

**Fecha:** 2026-09-02
**Estado:** aceptada

**Miniatura TTM.** El esquema simple del manual dibuja el movimiento **continuo**
y pone un circulo donde el sonido se **corta** (se supone corto). No hay circulo
al abrir. `TTMThumbnail` pasa de `{ segments, openMarks, closeMarks, phantomCuts }`
a **`{ curve, cuts }`**: una polilinea + un `●` por evento de fader que cierra
(incluido en `t=0`: el chirp arranca cerrado). Un baby no tiene cortes. La
autopista/`HighwayScene` (sellado) NO cambia: ahi se sigue viendo el hueco de
mute y ○/● (ADR-040/044) — es la miniatura la que simplifica.

**Variantes en pausa.** `data/curriculum/variants.json` se reduce a **solo
`base`**. La maquinaria (`Composer`, `VariantInfo.Transform`, `VariantAssembler`,
`VariantPickerView`, la logica de desbloqueo de `AttemptRecorder`/`XFDatabase`)
**se queda en el codigo**, dormida. La ficha de detalle (truco suelto y familia)
ya no lista variantes: solo "Practicar" (la base). Se reintroduciran —escalera de
subdivision, offsets, amplitud, mirror, swing, blind— cuando este cerrada la
representacion y toque el bloque de puntuaciones (se valida HW primero). El set
completo esta en el historial de git (`data/curriculum/variants.json` antes de
este commit) y en `docs/VARIANTS.md`.

**Consecuencias.**
- ✅ Menos ruido: la ficha es dibujo + descripcion + "Practicar".
- ✅ La miniatura ya no "junta dos puntos" (era ○ cierre + ○ apertura + hueco).
- ⚠️ El estado `MatrixCell.mastered` y `db.isMastered` quedan inalcanzables (piden
  2★ en tres variantes). Aceptado: vuelve con las puntuaciones.
- ⚠️ `variants.count == 1` en todo el codigo; los tests de transformacion de
  patron (subdivision, mirror) se han quitado — vuelven con los datos.


## ADR-051 — Logotipo xFlare (`XFWordmark`)

**Fecha:** 2026-09-02
**Estado:** aceptada
**Contexto.** Faltaba identidad visual: ni logo ni nombre "chulo" en la app.
**Decision.** `XFWordmark` (en **XFApp**, no en XFDesign que esta SEALED): la
marca del icono —una **tapa de crossfader** de mesa de batalla, silueta de reloj
de arena, `FaderCapMark: Shape`— en color de acento + el texto "xFlare"
(`.system(weight: .heavy, design: .rounded)`, la "x" en acento). Todo `Shape` +
`Text`, sin ficheros: funciona en cualquier build. Se coloca en la barra de
navegacion (`AppRootView`, visible en todas las pantallas de menu), en el Home
(grande) y en la barra superior de la practica (`LivePracticeView`).
**Consecuencias.**
- ✅ Identidad coherente con el icono `.icns` ya existente.
- ⚠️ Si algun dia XFDesign deja de estar SEALED, `XFWordmark` deberia mudarse
  alli con su ADR de re-sellado.


## ADR-052 — Cue 1 + cargar otra instrumental (feedback imagen #18)

**Fecha:** 2026-09-02
**Estado:** aceptada

**Cue 1.** Tecla `1` -> `PracticeSession.jumpToCue()`: el plato salta al inicio
del sample (`posLo`, donde vive el cue 1 por defecto), velocidad a 0, y avisa al
motor por `onAdvance(0,0,·)` + `engine.seekScratch(0)` para que el audio vuelva
al principio. (De momento el cue 1 es fijo al inicio; guardar/mover cues sera
mas adelante.)

**Cargar otra instrumental.** Boton "Base" en el panel derecho ->
`NSOpenPanel` (wav/aiff/caf/mp3/m4a/aac). La logica de decodificar + analizar
tempo + rotar a la fase del "1" + dejar en bucle se saca de `start()` a
`loadInstrumental(url:initial:)`: al cargar una nueva **se ajusta el BPM del
EJERCICIO** al de la instrumental (`session.setBPM` + `resyncClock` +
`engine.setTransport`) y se rehace la onda de la tira. `initial` distingue el
arranque (que ademas pone en marcha la salida y el reloj de la sesion) de una
recarga en caliente.

**Consecuencias.**
- ✅ Repetir un trozo con `1` sin tocar el transporte.
- ✅ Practicar sobre cualquier instrumental, con la rejilla y el tempo cuadrados.
- ⚠️ El BPM detectado manda sobre el `startBpm` del ejercicio mientras esa
  instrumental este cargada. La escalera de BPM del curriculo se re-cableara
  cuando entren las puntuaciones.

**Iterado (feedback imagen #19).**
- **BPM plegado a 70-140.** `TempoAnalyzer.analyze` gana `preferredRange`
  (70…140 por defecto): un tempo detectado a doble/mitad -180 en vez de 90- se
  dobla/parte hasta caer en el rango (2 % de margen en el borde). El hint del
  nombre de fichero sigue mandando sin plegar.
- **÷2 / ×2** junto al nombre de la base, en el panel: NO cambian la velocidad
  de la base, solo la **rejilla**. Si el tempo se detecto al doble (180 en un
  hiphop de 90), ÷2 deja la rejilla a 90 y la base se sigue oyendo natural: se
  **reinstala** (`EngineHandle.replayInstrumental(nativeBPM:)`, cabezal a 0) con
  `nativeBPM` = el nuevo BPM de sesion, asi el ratio de reproduccion vuelve a
  ~1.0. `resyncClock()` para que rejilla y base arranquen juntas del "1".
  Debajo, el **BPM actual**.
- **◀ / ▶ "Rejilla"** en el panel: `PracticeSession.nudgeGrid(±ppq/12)` desplaza
  la rejilla respecto a la base (offset acumulado al reloj, `resetGridPhase()`
  para deshacer, invalida el cache de `tick()`). Botones con area de toque de
  verdad; el paso anterior (`ppq/48`, ~5 px) no se notaba. ▶ mueve la rejilla a
  la DERECHA (para cuadrar un golpe que va por detras de la linea).
- **Deteccion tipo Serato/Traktor (mas cerca).**
  - *Onset MULTIBANDA*: `TempoAnalyzer` ya no usa flux broadband (dominado por el
    bombo). Separa grave / medio / agudo con filtros de un polo (160 Hz /
    4 kHz), saca el flux log-comprimido de cada banda y los SUMA -> coge bombo,
    caja y charles. (Sin llegar a la FFT por banda de octava, que seria el
    siguiente paso.)
  - *Fase sub-frame*: el comb interpola lineal la envolvente y refina el pico
    por parabola; +medio hop a `phaseFrames` (el flux marca el bloque donde SUBE
    la energia, el golpe cae al centro). La rejilla iba adelantada.
- **Techo del teal, tandas 3-5.** Iteraciones: afinar friccion/ganancia (no
  bastaba); mapear el rango propio del patron a toda la banda SIN techo (asi el
  teal llega arriba y se sale, con `posHi` a `posLo+2,5·span`). Pero en "repite
  conmigo" el teal auto-generado NO caia sobre la onda gris (mapeos distintos).
  **Version final**: la traza usa el MISMO mapeo que el fantasma —
  `traceY(p) = yb + amplitud·n·(yt-yb)`, con `n = (p-lo)/span`—; la onda gris de
  `HighwayLayout` (dibujada con `patternFill = 2/3`) se escala por
  `1,5·amplitud` para caer en el mismo sitio. Coinciden en n∈[0,1]; para n>1
  (plato pasado del pico) la traza sigue subiendo y a `n = 1/amplitud` llega al
  borde y de ahi se sale. `PracticeScene.ghostScale` -> `patternAmplitude`
  (el valor crudo del slider).
- **Botones de rejilla que no se pulsaban.** Dos causas: (1) el panel a 136 px
  aplastaba los chips (target ~0) -> panel a 176 px, chips 30x22 `.fixedSize()`
  con borde; (2) `PracticeSession.nudgeGrid` mutaba `currentTick` y en la app
  no se veia el efecto (mecanismo no fiable) -> se sustituye por
  `PracticeScene.gridShift` (ticks) que se SUMA a `now` cada fotograma: mueve
  rejilla + onda fantasma + traza, NO la onda de la instrumental (que es la
  referencia). Es un `@State` de la vista -> `updateNSView` -> scene, el mismo
  camino que el resto de parametros. `nudgeGrid`/`gridPhaseOffset` fuera.
- **"Llamada y respuesta" -> "Repite conmigo"**: boton ancho en su fila,
  "Compases" en otra. La etiqueta "Empezar"/"Escucha…"/"Tu turno" ya no deforma
  la fila.
- **Buffer fuera de la practica.** El selector de buffer en caliente sale del
  panel de la practica; queda solo en Ajustes (cambia al reiniciar la app).

---

## ADR-053 — Freestyle + grabacion de linea anclada a la instrumental

**Fecha:** 2026-09-02
**Estado:** aceptada

**Freestyle en la barra de navegacion.** Nueva entrada "Freestyle" ->
`AppModel.openFreeMode()`. La pantalla `.freeMode` reutiliza `LivePracticeView`
con `freestyle: true`: sin onda fantasma (`PracticeScene.showGhost = false`, que
oculta `ghostContainer`: curva gris + marcas), sin seccion "Repite conmigo" y
sin slider "Amplitud". Mantiene plato, base instrumental, mixer y el panel
"Grabar linea". `FreeModeView` (la maqueta inerte) deja de enrutarse. Cualquier
patron sirve de rejilla base (se coge `baby`); en Freestyle no se sigue.

**Parar la grabacion visible.** El boton REC del panel "Grabar linea" cambia de
forma segun estado: `record.circle` "Grabar" -> (claqueta) `metronome`
"Claqueta…" -> (grabando) `stop.fill` rojo "Parar · Ns". El contador de segundos
vive en un `@State recSeconds` refrescado por el tick del medidor (antes un
`.id(recTick)` recreaba el panel cada 50 ms y el boton no se dejaba pulsar).

**Grabacion anclada a la instrumental** (feedback 2026-09-02: "el momento de los
scratches debe ser el mismo sitio de la instrumental; al importar debe empezar
la instrumental de nuevo con lo grabado").

- *Tiempo en TICKS musicales, no en segundos.* `PracticeSession` guarda
  `recAnchorTick` (tick al empezar a grabar) y el playback (`pbClock`, `pbLen`,
  `pbMotion.t`) pasa a ticks: la linea corre al mismo reloj que la base
  (`pbClock += step·(bpm/60)·ppq`), asi no se desfasa aunque cambie el tempo o
  el frame rate.
- *Toma cuadrada a compases enteros.* `stopRecording()` redondea HACIA ARRIBA la
  duracion de la toma a un multiplo del bucle de la instrumental
  (`setInstrumentalLoopTicks`, la fija la vista) o de un compas si no se sabe.
  Viaja en `header.notes` como `loop=<ticks>` (`parseLoopTicks` lo lee; formato
  de fichero `.xfsession` sin tocar). Cada vuelta cae sobre los mismos golpes.
- *Fase-lock al importar.* `importLine()` -> `loadPlayback` + `resyncClock()`
  (reloj musical a 0) + `engine.replayInstrumental(nativeBPM:)` (base al
  principio) + `setTransport`. La linea arranca en la fase 0 de su bucle y la
  instrumental con ella.
- *Claqueta de 1 compas.* `armRecording()` pone `recArming = true` y fija
  `recArmFireTick` en el downbeat siguiente (>= medio compas); `advance()` llama
  a `beginRecordingNow()` al llegar. La vista enciende el metronomo mientras
  `recArming` y lo restablece al terminar. `startRecording()` (sin claqueta) se
  queda para los tests y el arranque directo.

**Consecuencias.**
- ✅ Una linea grabada suena siempre cuadrada con la base, vuelta tras vuelta.
- ✅ Exportar/importar `.xfsession` entre proyectos sin que se descoloque.
- ⚠️ Si el bucle de la toma y el de la instrumental tienen distinta longitud en
  compases, coinciden de fase pero no de compas (la toma rota sobre la base).
  Es lo esperado para bucles de distinta medida.
- ⚠️ `.xfn` (patron cuantizado a rejilla, loopable de verdad) sigue pendiente:
  esto es `.xfsession` (gesto crudo con su feel).
- Formato `.xfsession`: `header.notes` pasa a llevar `key=value` (`xfl loop=<n>
  bar=<m>`) en vez de texto libre; `formatVersion` sigue en 1 (campo aditivo).

**Iterado.**
- `FreeModeView` (maqueta inerte de B11.5) borrada: `.freeMode` ya va a
  `LivePracticeView(freestyle:)`. `FreeModeRecorder` (ventana rodante de 30 s) se
  queda: es un concepto distinto ("graba siempre los últimos N s") que aún puede
  quererse.
- **Puntuar la toma (práctica rudimentaria → XFAnalysis).** Botón "Puntuar la
  toma" en el panel "Grabar línea" (no en Freestyle): `AppModel.scoreTake` monta
  un `Take` con las muestras del `.xfsession` + su `clockMap`, lo pasa por
  `DefaultScorer` y va a `ResultsView` con el diagnóstico. **No persiste** ni
  mueve estrellas/progreso: la práctica rudimentaria aún no es una sesión de
  verdad (sin cuenta atrás ni series, eso es `XFEngine`). Es el primer cable
  real "enseñar, no puntuar" sin el ciclo completo. `XFAnalysis` pasa a
  dependencia de test de `XFAppTests`.
- **Fix en `XFAnalysis` (WIP).** `MotionResampler.velocity` reventaba con SIGILL
  (resta de `UInt64` con underflow) cuando un checkpoint del patrón caía después
  del último sample de la toma —es decir, siempre que grabas menos de lo que
  dura el patrón—. Ahora clampa al extremo, igual que `MotionResampler.position`.
  Regresión: `ReplayScoringTests.testTomaMasCortaQueElPatronNoRevienta`.
- **Tecla `2` / botón "Reiniciar (2)"**: `restartInstrumental()` reinicia la
  base desde el "1" (`replayInstrumental` + `resyncClock` + `setTransport`), sin
  tocar el scratch ni el cue 1. En el panel "Base" y en `PlatterInputView`
  (`keyCode 19`).
- **CI**: `AudioAssetTests` hace `XCTSkip` si `Audio/` no está (samples con
  copyright fuera de git, CLAUDE.md §12) en vez de fallar en el runner de
  GitHub. Antes tumbaba el job "Apple Silicon · tests" en cada PR.
- **Identidad de la base en la cabecera.** `stopRecording()` añade
  `instr=<slug>` a `notes` (nombre de la instrumental sin espacios). Al importar,
  `PracticeSession.playbackInstrName` lo expone y la vista avisa en ámbar si la
  toma se grabó sobre otra base (se reproduce igual, cuadrada de fase).
- **Contador de claqueta.** `recCountBeats` (negras que faltan) para el 3·2·1;
  el botón muestra "Claqueta · N".
- **÷2/×2 y el bucle.** `retempo()` escala `instrLoopTicks` por el factor
  (mismo audio, la mitad / el doble de compases) y se lo pasa a la sesión, para
  que las tomas siguientes cuadren al bucle nuevo.

---

## ADR-054 — Comandos de práctica por MIDI (sección `[transport]`)

**Fecha:** 2026-09-03 · **Estado:** aceptada

**Contexto.** En la práctica hay comandos que hoy solo están en el teclado (cue,
reiniciar la base, congelar, grabar, BPM ±1, metrónomo, "repite conmigo", fader).
Con la mesa delante el usuario quiere dispararlos desde sus pads / botones MIDI
sin soltar los platos. La Rane 72 no expone el crossfader por MIDI (ADR-021),
pero sus pads sí mandan notas.

**Decisión.** Un decodificador puro en `XFCapture` (`MidiCommandMap`) traduce
mensajes MIDI a `PracticeCommandEvent`. El mapa base sale de una sección
`[transport]` del `.conf` de mesa (`command.cue = note:1:36`, …) y el usuario lo
pisa desde Ajustes (`AppSettings.midiCommandOverrides`, serializado
`cue=note:1:36;…`). `AppModel` es dueño de un `MidiCommandSource`, publica los
eventos por un `PassthroughSubject` y `LivePracticeView` los enruta a las mismas
acciones que el teclado. Todos los comandos son disparos discretos (Note On, o
CC ≥ 64) salvo `command.fader`, que es **momentáneo** (nota mantenida / CC
continuo → `faderClosed(Bool)`).

**Alternativas descartadas.**
- *Nudge A/D del plato por MIDI*: se dejó fuera a propósito (el plato es del
  timecode, no de un botón).
- *Solo overrides de usuario, sin sección de perfil*: obligaría a cada dueño de
  una Rane 72 a remapear a mano; mejor que el perfil traiga un punto de partida.
- *MIDI Learn en la UI*: pendiente del conector CoreMIDI real (`MidiFaderConnector`
  aún no existe); de momento la asignación es por texto en Ajustes.

**Consecuencias.** El núcleo es testeable sin hardware (`ingest(bytes:)`). Cuando
llegue el conector CoreMIDI solo hay que llamar a `midiCommands.ingest`. La
sección `[transport]` de la Rane 72 va **comentada** (números sin verificar). El
"MIDI Learn" visual queda para más adelante.

---

## ADR-055 — Miniatura TTM: curva entera coloreada, sin puntos (feedback 2026-09-03)

**Fecha:** 2026-09-03 · **Estado:** aceptada · complementa ADR-050

**Contexto.** Los ● de corte se colocaban con reglas por familia (flare en
horizontal, chirp en el vértice, resto sobre la curva). Seguían saliéndose del
cuadro en `tear-flare-1c` y `crab`, y las reglas eran frágiles. El autor propuso
otra representación: dibujar la curva entera y **colorear** los tramos en vez de
marcar puntos.

**Decisión.** `TTMThumbnail` pasa a ser una lista de `Segment` (`points` +
`sounding`). `build` muestrea el ciclo entero y parte la curva en tramos por los
cambios de fader, compartiendo el punto de unión (curva contigua, sin huecos).
`TTMThumbnailView` pinta los tramos que suenan (fader abierto) con trazo **lleno**
y claro (`XFColor.text`, 1.8) y los cortados con trazo **a rayas** en gris
(`XFColor.textMuted`, 1.2, dash `[2.5, 2.5]`). Sin ●. La `y` se normaliza con un
8 % de margen para que el trazo no toque el borde. En Home, un recuadro a la
derecha explica cómo leerlo (curva de ejemplo + clave lleno/rayas).

**Alternativas descartadas.**
- *Puntos ● con reglas por familia* (ADR-055 v1): frágil y se salían del cuadro.
- *Ocultar los tramos mudos* (ADR-050): el autor prefiere ver el silencio como
  curva, no como ausencia.
- *Solo cambio de color (mismo trazo lleno)*: a tamaño de miniatura el contraste
  entre blanco y gris apagado no se leía; las **rayas** lo dejan inequívoco sin
  depender del color. Rojo para el corte se descartó por sobrio.

**Consecuencias.** Una sola convención para todas las familias. El vértice del
movimiento siempre se ve arriba (es la curva de verdad). Nada se sale del cuadro.
`tear-flare-1c` y `crab` quedan bien sin código especial. El `Forward Cut` /
`Stab` vuelven a dibujar la vuelta, ahora en gris (corte), no como hueco.

---

## ADR-056 — El vídeo de la toma sale con la proporción de la ventana (feedback 2026-09-03)

**Fecha:** 2026-09-03 · **Estado:** aceptada · complementa ADR-026 (F.4)

**Contexto.** `TakeVideoExporter` forzaba 1080×1920 (9:16) sobre un layout de
autopista apaisado (~1000×380). El `render` escala el layout al tamaño del vídeo,
así que todo salía estirado ~5× en vertical y "se veía mal".

**Decisión.** `Options.width/height` pasan a ser opcionales. Si no se dan,
`Options.pixelSize(for:)` deriva la resolución de la geometría de la autopista
(misma proporción, lado mayor = `longSide`, 1600 por defecto), con los dos lados
redondeados a par (lo pide H.264). `PracticeScene` reporta el tamaño real de la
zona de autopista (`onHighwaySize`) y `LivePracticeView` lo usa al exportar, así
el vídeo sale con **la proporción exacta de la ventana** en ese momento.

**Alternativas descartadas.** Mantener 9:16 y encajar la autopista con barras:
desperdicia la mayor parte del cuadro y el gesto se ve diminuto. Un tamaño fijo
apaisado (p. ej. 1600×600): mejor que 9:16 pero no sigue a la ventana.

**Consecuencias.** El vídeo se parece a lo que el usuario ve. La resolución ya no
es constante entre tomas (depende de la ventana); a cambio, nada se estira. Los
tests que fijan `width`/`height` explícitos siguen valiendo.

---

## ADR-057 — El vídeo refleja los cortes de fader (feedback 2026-09-03)

**Fecha:** 2026-09-03 · **Estado:** aceptada · complementa ADR-056

**Contexto.** `TakeVideoExporter.trace(from:)` reconstruía la línea del usuario
solo del `motion` de la toma, con `level = nil` siempre, así que el vídeo salía
todo teal aunque la grabación tuviera cortes de crossfader. En la práctica en
vivo el tramo con el fader cerrado se pinta apagado.

**Decisión.** `trace(from:)` cruza cada muestra de movimiento con el carril de
fader grabado (`session.fader`) y marca los puntos con el fader cerrado como
`level = .miss`. `HighwayLayout` ya parte la traza por `level`, así que el
rasterizado recibe esos tramos aparte y los pinta en gris y **a rayas** (igual
convención que la miniatura, ADR-055), el resto teal y lleno.

**Alternativas descartadas.** Reproyectar la traza a mano en el exporter para
colorearla: duplicaría la proyección tick→píxel de `HighwayLayout` (módulo
sellado) y se desincronizaría de la curva fantasma. Reutilizar `.miss` es un
apaño pero en el render offline no hay scoring, así que `level` está libre.

**Consecuencias.** El vídeo comunica los cortes. Si algún día el export offline
puntúa de verdad, habrá que separar "fader cerrado" de "fallo" en el modelo de
la traza (hoy comparten `.miss`).

---

## ADR-058 — La pantalla de Ajustes no usa `Form` (macOS 11)

**Fecha:** 2026-09-03 · **Estado:** aceptada

**Contexto.** `SettingsView` era el único sitio de la app con `Form` de SwiftUI.
Al añadirle una sección con un `ForEach` (los comandos MIDI, ADR-054) la pantalla
**entera se quedó en blanco** en macOS 11 — un bug conocido de `Form` +
`ForEach` en Big Sur.

**Decisión.** `SettingsView` se reescribe con el patrón del resto de la app:
`ScrollView { VStack { XFCard } }`, secciones a mano con un helper `section`,
controles nativos (`Toggle`, `Slider`, `Picker`, `TextField` con
`RoundedBorderTextFieldStyle`) colocados en filas. Nada de `Form`.

**Alternativas descartadas.** Meter el `ForEach` dentro de un `VStack` en una
sola celda del `Form`: seguía en blanco. Constrañir los `Text` anchos: bajaba el
tamaño intrínseco pero no arreglaba el fondo del problema.

**Consecuencias.** Una convención de layout para toda la app. Se pierde el
estilo "ajustes del sistema" nativo del `Form`, que en tema oscuro fijo tampoco
aportaba. `docs/PLATFORM_SUPPORT.md` §4 debería listar `Form` como a evitar.

---

## ADR-059 — MIDI Learn para los comandos de práctica (feedback 2026-09-03)

**Fecha:** 2026-09-03 · **Estado:** aceptada · complementa ADR-054

**Contexto.** ADR-054 dejó la asignación de comandos MIDI como texto a mano
(`note:1:36`). El autor pidió el flujo habitual: seleccionar el comando y pulsar
un botón para que el siguiente control MIDI que se mueva quede asignado.

**Decisión.** `MidiMonitorConnector` (XFCapture) — mismo patrón que
`MidiFaderConnector` pero **genérico**: se engancha a todas las fuentes CoreMIDI
y entrega cada mensaje troceado a un bloque. `MidiLearnModel` (XFApp,
`ObservableObject`) lleva el estado: `selected`, `armed`, `lastSeen`; `start()` /
`stop()` abren y cierran el monitor y los llama `SettingsView` en
`onAppear` / `onDisappear` (solo escucha mientras Ajustes está abierto).
`MidiBinding.learned(status:data1:data2:)` traduce el mensaje a asignación (Note
On → `note`, CC → `cc`; el resto `nil`). Al aprender, `AppModel` lo guarda como
override (`settings.midiCommandOverrides`). En la UI cada comando es un radio,
hay un botón "Aprender MIDI" y se conserva el campo de texto + un botón de
limpiar por fila.

**Alternativas descartadas.** Un `MidiLearn` por fila (más botones, más ruido).
Reutilizar `MidiFaderConnector`: es específico del crossfader (filtra por CC y
canal). Escuchar CoreMIDI siempre: gasto y sorpresas fuera de Ajustes.

**Consecuencias.** El núcleo (`MidiBinding.learned`, `MidiLearnModel.handle`) se
prueba sin hardware; el monitor CoreMIDI no (como sus hermanos). Si no hay
dispositivo, la sección sigue funcionando a mano.

---

## ADR-060 — Instrumental subida = bucle de N compases con BPM derivado (feedback 2026-09-03)

**Fecha:** 2026-09-03 · **Estado:** aceptada · sustituye el `keepExerciseBPM` de la iteración anterior

**Contexto.** El autor quería subir un loop y que sonara infinito y cuadrado con
la rejilla. El primer intento dependía de `TempoAnalyzer`: si detectaba tempo lo
usaba (y a veces lo erraba, con lo que la base derivaba contra el metrónomo); si
no, sonaba a velocidad natural pero con el BPM del ejercicio, que no tenía nada
que ver con el loop. Además, al "reiniciar la base" el metrónomo (que va con
`e->tick` del motor, no con el reloj de la sesión) no se rearmaba y se descuadraba.

> **Corrección (2026-09-03, misma jornada).** "Siempre" era demasiado: tratar
> una **pista larga** (una canción de 3 min) como un loop de N compases rompía la
> detección de tempo y la alineación de rejilla que antes funcionaba. Ahora el
> "modo loop" solo se aplica cuando el fichero **parece** un loop —
> `TempoAnalyzer` lo marca `isShortLoop`, o no detecta tempo en absoluto. Una
> pista larga con tempo claro (suba el usuario o sea el asset) va por la
> detección normal: BPM detectado + rotación de fase para alinear el "1",
> `loopTicks` de la duración. Sin botones −/+ (no es un loop).

**Decisión.** Un fichero que sube el usuario **y que parece un loop** (corto o sin
tempo detectable) se trata como un bucle de `N` compases a **velocidad natural**
(nunca se estira el audio). El BPM de la rejilla se **deriva**:
`bpm = N · compases/compás · 60 / duración`. Así el metrónomo y las líneas de
compás quedan clavados al bucle pase lo que pase con la detección.
`InstrumentalLoop` (puro) hace el cálculo: `guess(...)` adivina `N` de
las negras del análisis (o ~2 s/compás sin él) y parte/dobla hasta que el BPM cae
en 70…180; `locked(...)` lo fija a mano. En el panel Base, botones **−/+** para
corregir los compases (recalcula el BPM). Todas las rutas que reinician la base
(`restartInstrumental`, `retempo`, importar línea, cargar otra base) hacen ahora
`engine.seek(tick: 0)` además de `session.resyncClock()`, que rearma el metrónomo
en el "1".

**Alternativas descartadas.** Fiarse de `TempoAnalyzer` (erra medios/dobles
tiempos). Estirar el audio al BPM del ejercicio (un loop de scratch NO se
time-stretch; suena fatal). BPM fraccionario en `PracticeSession` (toca media
app; el resample de ~0,3 % entre BPM derivado y redondeado es inaudible y deja la
rejilla perfecta).

**Consecuencias.** `InstrumentalLoop` se prueba sin audio (6 tests). El "modo
loop" solo aplica a ficheros del usuario; el asset por defecto (`080bpm_beat`)
sigue con la detección normal. Rotar el PCM a la fase del "1" se omite para loops
(se asume que empiezan en su "1", como todo loop bien hecho) — así no se mete una
costura en el punto de wrap.

> **Añadido (2026-09-03).** Como la detección "afina pero no clava", el BPM de la
> base se remata a mano: botón **TAP** (`TapTempo`, puro y testeado) que promedia
> los últimos intervalos, y pinchar el número lo abre para escribirlo. Ambos van
> por `setInstrumentalBPM`, que reinterpreta la rejilla como ÷2/×2 pero a un
> valor cualquiera y realinea metrónomo y "1"; en modo loop lo traduce al nº de
> compases entero más cercano.

---

## ADR-061 — EQ de 3 bandas sobre el sample de scratch + limpieza del hilo RT (2026-09-03)

**Fecha:** 2026-09-03 · **Estado:** aceptada

**Contexto.** El autor pidió (a) que el motor de audio fuera "lo más ligero
posible" y (b) una EQ Lo/Mid/Hi para el sample, como el kill-EQ de una mesa.

**Decisión — optimización.** El bucle más caliente es `xf_player_render` (sinc de
32 taps, dos veces por bloque: scratch + base). Cambios que NO alteran el
comportamiento (los tests espectrales siguen en verde con sus tolerancias):
acumular la convolución en `float` en vez de `double` (error ~1e-6, el doble de
rápido); un camino contiguo sin ramas cuando la ventana de 32 taps cae entera
dentro del sample (el 99 % de las muestras), dejando los bordes y el envoltorio
del bucle para el camino lento; `floor()` → truncado a `int64_t` (el cabezal
siempre es ≥ 0); un **flush a cero** de la velocidad cuando es denormal (el
one-pole nunca llega a 0 del todo y una velocidad denormal dispara el modo
denormal de la FPU, ~100× más lento en Intel); y **saltarse los 32 taps solo con
el plato EXACTAMENTE parado** (`av == 0`, plato en reposo: idle, fase de "escucha"
del repite-conmigo) — deja el coste del scratch en reposo casi a 0.

> **Corrección (2026-09-03).** El primer intento saltaba los taps con un umbral
> de banda (`amp < 1e-4`); al scratchear despacio la velocidad cruza esa banda
> muchas veces y el audio se cortaba a trozos ("tirones"). Ahora el salto es solo
> con `av == 0` exacto (tras el flush) y la ganancia de la puerta hace el fundido
> de forma continua; el ahorro en reposo es el mismo.

**Decisión — EQ.** `xf_eq` (módulo propio, testeable): low-shelf 200 Hz, peaking
1 kHz (Q 0,9), high-shelf 4 kHz (fórmulas RBJ), en biquads **forma directa II
traspuesta**. Se aplica **solo al reproductor de scratch** (la base instrumental
y el metrónomo no se tocan). `xf_engine_set_sample_eq(low_db, mid_db, high_db)`
corre en el hilo normal y diseña los coeficientes (usa sin/cos/sqrt — NO RT-safe)
publicándolos por **doble buffer torn-free** (mismo patrón que el swap de
`xf_player` en `xf_engine`). El hilo RT hace una **rampa de ~20 ms** de los
coeficientes en uso hacia el objetivo (una interpolación por bloque, no por
muestra): así mover un mando de golpe no mete un click. Ganancias en dB acotadas
a [-24, +12]; con 0/0/0 el objetivo es "plano" y, cuando la rampa llega, el
filtrado se salta entero (coste 0 por defecto). En la UI, tres sliders Lo/Mid/Hi
(−24…+6 dB, con "plano") en el panel Mezcla; no se persisten (como los volúmenes).

**Alternativas descartadas.** Calcular los coeficientes en el hilo RT al mover el
mando (sin/cos en el callback: el proyecto es estricto con §7). Interpolar los
coeficientes por muestra (coste innecesario para un suavizado de 20 ms). Un
crossfade entre dos cadenas de biquads (el doble de filtrado durante el cambio).
EQ sobre la mezcla entera (el autor quería moldear el **sample**, no la base).
`double` en la convolución "por si acaso" (medido: no aporta nada audible y
cuesta el doble).

**Consecuencias.** `xf_eq` se prueba sin hardware (7 tests de respuesta en
frecuencia + no-click; 1 test de integración en `xf_engine`). El `module.modulemap`
de `CXFAudioCore` incluye ahora `xf_eq.h`. No cambia la puerta de latencia
(B4.5); si acaso, baja el coste. El sellado de `CXFAudioCore` (B4.6) sigue
pendiente de las mediciones en hardware.

---

## ADR-062 — Menú "Librería" de medios (Trucos + Instrumentales + Samples) y slots de sample por MIDI (feedback 2026-09-03)

**Fecha:** 2026-09-03 · **Estado:** aceptada

**Contexto.** El navegador de la matriz de scratches se llamaba "Librería", pero
el autor quería reservar ese nombre para una biblioteca de **medios** (sus
instrumentales y sus samples), y que:
- las instrumentales/loops queden **pre-analizadas** dentro de la carpeta de la
  app, para que cargarlas en la práctica sea instantáneo;
- los samples se puedan **asignar a botones MIDI** y cambiar entre 4 en mitad de
  una sesión, sin ratón;
- en Trucos cada scratch se vea con su **notación TTM** al lado, en tarjetas.

**Decisión.**
1. **Renombrado.** El navegador de scratches pasa a llamarse **Trucos**
   (`LibraryView`, reescrito a `LazyVGrid` de tarjetas con `TTMThumbnailView` a la
   derecha). El nombre **Librería** queda para el nuevo `MediaLibraryView`
   (`Screen.mediaLibrary`), con pestañas **Instrumentales** y **Samples**.
2. **Persistencia** (`AppSettings`, plist local, sin nube): `instrumentalLibrary:
   [String]` (rutas, tope 200) y `sampleSlots: [String]` (**siempre 4**, `""` =
   vacío). Se añaden ficheros por `NSOpenPanel` (ficheros o **una carpeta** con
   casilla "subcarpetas") o **arrastrando y soltando**; aviso `NSAlert` si entran
   ≥ 20 pistas de golpe (analizar tarda ~1 s por pista).
3. **Pre-análisis** (`InstrumentalAnalysisCache`, fase 2): al añadir una
   instrumental se analiza el tempo/fase/compases **una vez** en segundo plano
   (`qos: .utility`) y se cachea en
   `~/Library/Application Support/xFlare/instrumental-analysis.json`
   (`CachedAnalysis: Codable`, invalidado por tamaño/mtime del fichero y por la
   sample rate del motor). En la práctica `loadInstrumental` lee del caché →
   carga instantánea; `TempoAnalyzer.Result` es ahora `Codable`.
4. **Slots de sample por MIDI** (fase 3): `PracticeCommand.sample1…sample4`
   (XFCapture, `command.sample_1`…`_4` en `[transport]`), disparos discretos. En
   la práctica `LivePracticeView.loadSlot(i)` hace `cue` + carga el fichero del
   slot `i` (si está vacío o no existe, no hace nada). Se mapean desde Ajustes ›
   MIDI o el `.conf` como cualquier otro comando.
5. **Selector de instrumental de la práctica → `Menu`**: lista las instrumentales
   analizadas de la librería (carga al instante) + la base por defecto +
   "Cargar otra…".

**Alternativas descartadas.** Analizar la instrumental cada vez que se carga (lo
que había: 1-2 s de espera con la práctica congelada). Un único "sample activo"
recordado (`lastScratchSamplePath`) sin slots (no permite cambiar en vivo).
Guardar el análisis dentro del propio fichero de audio (metadatos frágiles, y
xFlare no debe escribir en los ficheros del usuario). Meter los medios en la
misma pantalla que Trucos (mezcla dos conceptos: catálogo de ejercicios vs.
ficheros del usuario).

**Consecuencias.** `MediaLibraryView`, `InstrumentalAnalysisCache`,
`InstrumentalLoop`, `TapTempo` son piezas nuevas de XFApp, todas con tests puros.
`AppSettings` gana dos campos con su ida y vuelta. El caché vive fuera del
sandbox del repo (App Support), copiable por el usuario (soberanía, `CLAUDE.md`
§3). No toca el hilo de audio.

---

## ADR-063 — Los ajustes se guardan en un fichero JSON, no solo en UserDefaults (feedback 2026-09-03)

**Fecha:** 2026-09-03 · **Estado:** aceptada

**Contexto.** El autor reportó que "las canciones y la configuración no se
guardan de una vez a otra". Los ajustes vivían solo en
`UserDefaults(suiteName: "app.xflare.settings")`. `UserDefaults` en macOS lo
vacía a disco `cfprefsd` de forma diferida (~30 s + al terminar limpio); si la
app se cierra de golpe (crash, `killall`, parar desde Xcode) los cambios
recientes se pierden. Además el autor quería **un fichero de configuración**
visible y copiable (`CLAUDE.md` §3).

**Decisión.** `SettingsStore` (XFApp): `AppSettings.raw` (`[String:String]`) se
serializa a **JSON con sangría y claves ordenadas** en
`~/Library/Application Support/xFlare/settings.json`, escrito **atómicamente en
cada cambio** (`Data.write(to:options:.atomic)` desde el `didSet` de
`AppModel.settings`). `loadSettings()` prefiere el fichero; si no existe pero hay
un plist viejo, lo lee y **migra** (escribe el fichero una vez); si tampoco,
`AppSettings.defaults`. El `UserDefaults` se mantiene como **espejo** por
compatibilidad, pero ya no es la fuente de verdad.

**Alternativas descartadas.** Llamar a `UserDefaults.synchronize()` (obsoleto y
no garantiza el vaciado inmediato). `NSUserDefaultsController`. Un `.plist`
propio en vez de JSON (menos legible para editar a mano). Guardar en la BBDD
SQLite (ya hay un accesor `setting` ahí, pero es un fichero binario, no
copiable-editable a ojo, y añade dependencia de GRDB al arranque de ajustes).

**Consecuencias.** El fichero es texto plano, versionable y copiable entre
máquinas. Escritura atómica: nunca queda a medias. `SettingsStore` se prueba
sin hardware (ida y vuelta + que sea JSON legible). No toca el hilo de audio.

> **Corrección (2026-09-04).** El fichero funcionaba, pero `SettingsView`
> guardaba **todo** el `AppSettings` en un `@State` sembrado una sola vez. En una
> visita posterior a Ajustes ese `@State` estaba viejo (si mientras tanto otra
> pantalla había tocado `AppModel.settings` — p. ej. añadir instrumentales a la
> Librería) y el **primer** cambio en Ajustes lo subía entero con `onChange`,
> **pisando la librería de instrumentales** (se vaciaba). Arreglo: `SettingsView`
> re-siembra el `@State` desde la copia entrante (`.onChange(of:)` + `.onAppear`).
> Además `AppModel.recoverInstrumentalLibraryIfNeeded` recupera **una sola vez**
> las instrumentales que se llegaron a analizar (`instrumental-analysis.json`) y
> siguen en disco pero cayeron de la lista, con un flag `libraryRecovered` para
> no repetirlo ni resucitar borrados.

---

## ADR-064 — Reorganización de la pantalla de práctica + BPM con decimal + tope del sample + números de rejilla (feedback 2026-09-03)

**Fecha:** 2026-09-03 · **Estado:** aceptada

**Contexto.** El panel derecho de la práctica había acumulado demasiado. El
autor pidió: (a) a la izquierda de la onda del sample, el selector de sample +
la asignación MIDI de los 4 slots + el meter + la EQ + los volúmenes; (b) abajo,
un selector desplegable de instrumentales de la Librería, con los controles de
tempo/rejilla a su derecha, que **se minimiza al cargar** a una fila con lo
básico (desplegar, reiniciar, ÷2/×2, ◀/▶, TAP, BPM); (c) **BPM con un decimal**,
también en el TAP; (d) un sample más largo que el `Ahh` "se va todo"; (e)
números de compás.subdivisión ("1.1", "1.2"…) sobre la rejilla, discretos, que
sigan al desplazamiento.

**Decisión.**
1. **Columna izquierda** (`leftColumn`, 176 px, pegada al rail del sample):
   secciones "Sample" (selector, **slots MIDI**, cue A/B, aviso de loop) y
   "Mezcla" (meter, volumen de sample e instrumental, EQ Lo/Mid/Hi). El panel
   derecho se queda con "Repite conmigo", "Grabar línea" y "Ajuste rápido".
2. **Zona inferior** (`bottomBar`): fila compacta siempre visible —
   `[desplegar] nombre · [↻][÷2][×2][◀][▶][TAP][BPM]` (tempo y rejilla a la
   derecha) — y, al desplegar, el panel `instrLibraryPanel` con la lista de
   instrumentales **ya analizadas** de la Librería (nombre + "≈ BPM · compases"
   del caché), "Cargar otra…" y, en modo loop, el ajuste de compases. Al cargar
   una base se minimiza sola.
3. **Slots MIDI en la práctica**: `sampleSlotsRow` en la columna izquierda —
   4 filas, cada una con un botón-número que dispara `loadSlot(i)` en caliente y
   un menú para asignarle un fichero (de la biblioteca o del disco). Persiste vía
   `onSampleSlotsChanged` → `AppSettings.sampleSlots`.
4. **BPM con un decimal**: `PracticeSession.bpm` pasa de `Int` a `Double`
   (`setBPM` redondea a 0,1); `TapTempo.tap()` devuelve `Double?` (media de 4-8
   golpes, a 0,1); toda la UI de BPM formatea con `%.1f` y la edición a mano
   acepta coma o punto. La rejilla va enganchada a la base: si la base es 120,5 y
   la rejilla fuera entera se separarían.
5. **Tope del sample de scratch**: `AudioAsset.scratchMaxSeconds` = 2,0 s;
   `capScratch(_:sampleRate:)` recorta la carga. El movimiento del plato mapea a
   una fracción del sample entero, así que un fichero de 1 min barría minutos de
   audio con un gesto; con el tope, cualquier sample se scratchea como el `Ahh`.
6. **Números de rejilla**: `PracticeScene.gridLabels(...)` (puro, testeable) da
   "compás.subdivisión" para cada línea de negra visible (el "1" absoluto = tick
   0 → compás 1, negra 1; sin etiquetas antes del "1"). `moveGridLabels` los
   pinta arriba del todo de la autopista, pequeños (`fontSize` 8, α 0,5). Usan el
   mismo `now` desplazado por `gridShift`, así siguen a los botones ◀/▶.

**Alternativas descartadas.** Mantener todo en el panel derecho con más scroll
(el autor lo ve saturado). BPM entero y un "fino" aparte (la rejilla se
desengancharía de la base). Recortar el sample largo con un *fade* o buscar el
"mejor" fragmento (no aporta: el autor quiere que se comporte como el `Ahh`;
puede recortarlo él en F.3). Dibujar los números en XFRender (sellado) — se
hacen en `PracticeScene` (XFApp), sin tocar el módulo sellado.

**Consecuencias.** `PracticeSession.bpm: Double` es un cambio de API dentro de
XFApp (no sellado); `PlatterInputView.onBPM`/`currentBPM` pasan a `Double`; los
tests de `PracticeSession`/`TapTempo` se actualizan. `LivePracticeView` gana el
callback `onSampleSlotsChanged` (cableado en `AppRootView`). Sin cambios en el
hilo de audio ni en la puerta de latencia.

---

## ADR-065 — Pasada de optimización: menos coste por fotograma (feedback 2026-09-04)

**Fecha:** 2026-09-04 · **Estado:** aceptada

**Contexto.** El autor pidió "revisar todo el código y optimizarlo para que vaya
más ligero". El hilo de audio ya se pulió en ADR-061; esta pasada mira el resto
del coste recurrente en el Intel de 2015 (el bucle a 60 fps de `PracticeScene`,
el timer a 60 Hz de `PracticeSession`, el sondeo a 20 Hz de `LivePracticeView`) y
un resto de libm en la capa RT. **Cambios sin cambio de comportamiento** — los
638 tests siguen en verde sin tocarlos.

**Decisión.**
1. **`SKLabelNode.text` de los números de rejilla**: cambiar el texto re-tesela
   el glifo (caro). Ahora solo se asigna si de verdad cambió — el texto de una
   línea solo cambia al cruzar una negra, no cada fotograma. Igual con
   `isHidden` de las líneas verticales (solo se escribe al cambiar).
2. **Sin `malloc` por fotograma en la rejilla**: `gridLines` / `gridLabels`
   ganan una variante que **rellena** buffers reservados (`removeAll(keepingCapacity:)`
   + `append`) en lugar de devolver arrays nuevos. La variante que aloca se
   mantiene para los tests. Las etiquetas "1.1"…"9.9" caben en la representación
   *inline* de `String` (sin heap).
3. **`renderUserTrace` sin arrays intermedios**: antes troceaba la traza en
   `[(Bool, [CGPoint])]` (un array por tramo, cada fotograma). Ahora cuenta los
   tramos en una pasada y pinta cada uno con `move`/`addLine` sobre los índices,
   sin copiar puntos.
4. **`PracticeSession.traceBuffer`**: `reserveCapacity(512)` al crear; la poda
   del prefijo caducado cuenta los puntos fuera de ventana y hace un solo
   `removeFirst(k)` en vez de recorrer todo el array con el predicado de
   `removeAll(where:)`.
5. **Telemetría a 20 Hz fuera del `body` grande** (`ClipMeterView`): el medidor
   de pico y la corrección de deriva del metrónomo tenían su `.onReceive` en
   `LivePracticeView`, cuyo `body` (enorme) se re-evaluaba 20 veces/s aunque la
   práctica estuviera parada. Ahora viven en su propia vista con su propio timer;
   el `body` grande solo se toca mientras se **graba** una línea (contador de
   segundos, y guardado contra escrituras iguales).
6. **`xf_player_render` (RT)**: el `fmod` de la vuelta del bucle (base
   instrumental) se cambia por un par de sumas/restas — `|v|` es <<< `frames`
   porque el ratio de la base está acotado, así que el resultado es idéntico y
   se ahorra una llamada a libm **por muestra**.

**Alternativas descartadas.** Podar `traceBuffer` en lotes dejando puntos fuera
de ventana (rompía el contrato `trace()` sin historia vieja y el test que lo
fija). Reescribir el bucle RT entero o fusionar sus pasadas (riesgo alto, ganancia
nula: cabe en L1). Cachear el `HighwayFrame` entre fotogramas (ya hay early-out
por `now` sin cambios). Meta/`CAMetalLayer` en vez de SpriteKit (es la vía de
escape de ADR-036 si el profiling lo exige; no lo exige).

**Consecuencias.** `ClipMeterView` es una pieza nueva de XFApp. Sin cambios de
API pública ni de comportamiento observable; los goldens y los 638 tests quedan
igual. El sellado de `CXFAudioCore` sigue pendiente de las mediciones en
hardware (B4.5/B4.6), que son las que dirían cuánto se ha ganado de verdad.

---

## ADR-066 — `XFTestKit` deja de ser andamiaje: fuentes falsas + señales sintéticas centralizadas

**Fecha:** 2026-09-04 · **Estado:** aceptada

**Contexto.** `XFTestKit` existía desde B0.1 pero solo tenía `Golden` (comparación
de goldens, ADR-028) y un marcador de andamiaje. Su descripción prometía
"fixtures, fuentes falsas, helpers de golden" y no estaban. Mientras tanto cada
target de test se inventaba lo suyo: el generador de **timecode de cuadratura
sintético** está duplicado *verbatim* en `CXFTimecodeTests` y `XFCaptureTests`, y
el truco de `#filePath` → raíz del repo se reescribe en `AnalysisFixtures`,
`RenderFixtures`, `XFNFixtures`… con un número fijo de `deletingLastPathComponent`.

**Decisión.** `XFTestKit` recoge lo reutilizable de test que no es específico de
un módulo:
- **`Signals`** — `sine` / `silence` (PCM mono float) y `quadratureTimecode`
  (estéreo int16; `carrierHz` = velocidad, `secondaryPhaseDeg` = sentido), con la
  misma fórmula que ya usaban los tests de timecode.
- **`FakeMotionSource` / `FakeFaderSource`** — implementaciones de mentira de los
  protocolos de `XFCapture` (modo *script* o *valor fijo*, conteo de
  `start()`/`stop()`, `startError`).
- **`RepoFiles`** — `root()` / `url(_:)` / `data(_:)` / `text(_:)`; sube desde el
  `#filePath` del que llama (expandido en el sitio de la llamada) hasta encontrar
  `Package.swift`, en vez de contar carpetas.
- **`Golden`** se queda como estaba y estrena tests propios.

`XFTestKit` gana dependencia de `XFPrimitives` y un target `XFTestKitTests` (18).
`scaffoldingVersion` **no se toca** (sigue en 0): lo asegura un smoke test de
`XFEngineTests`, módulo sellado.

**Alternativas descartadas.** Migrar ya `AnalysisFixtures` / `RenderFixtures` /
`XFNFixtures` a `RepoFiles` — la mayoría son tests de módulos **sellados** y sus
tests son inmutables; los nuevos tests (y el trabajo pendiente de `B6.7` / `B8.5`,
que necesita fuentes falsas y `.xfsession`) ya lo usan, y los viejos se pueden
migrar cuando toque abrir esos targets por otra razón. Un paquete de test
aparte (los helpers son pequeños y encajan en el módulo que ya existe).

**Consecuencias.** Los tests futuros que consuman captura no vuelven a necesitar
hardware ni a duplicar el generador de timecode. `XFTestKit` no es sellable (no
entra en el binario); su "estado" en `MODULE_STATUS.md` es **UTIL**.

---

## ADR-067 — Editor de instrumental: tempo/rejilla, cues y loops de una parte (feedback 2026-09-04)

**Fecha:** 2026-09-04 · **Estado:** aceptada

**Contexto.** El autor pidió, en la Librería de instrumentales, "un mini editor
donde ajustar la rejilla y el tempo antes de entrar en los ejercicios", "poner
puntos Cue para practicar sobre partes" y "hacer partes loops infinitos". Hasta
ahora eso se hacía a mano y en caliente durante la práctica (TAP, ◀/▶, ÷2/×2), y
el bucle de la base era siempre el fichero entero.

**Decisión.**
1. **RT — bucle de una región** (`xf_player`): campos `loop_start` / `loop_end`
   (frames); con `loop` activo el cabezal y la lectura sinc envuelven dentro de
   `[loop_start, loop_end)` — el bucle de una parte es tan continuo como el del
   fichero entero. Por defecto `0..frames` = comportamiento de siempre.
   `xf_player_set_loop_region` (NO-RT); la región se lee **una vez por bloque** y
   se **sanea** en `xf_player_render` (acota `[rlo, rhi)` a `[0, frames)`), así
   una lectura rasgada de los dos `int64` sin candado nunca da acceso fuera de
   rango. `xf_engine_set_instrumental_loop_region` +
   `xf_engine_seek_instrumental` (para pinchar la onda en el editor) →
   `EngineHandle.setInstrumentalLoopRegion(start:end:)` / `seekInstrumental(fraction:)`.
2. **Datos** — `InstrumentalEdit` (puro, `Codable`): `bpm?`, `downbeatSeconds?`,
   `beatsPerBar`, `cues: [Cue]`, `loops: [LoopRegion]`, `activeLoopID?`. Todo
   opcional: lo que esté `nil` cae a la detección de `TempoAnalyzer`.
   `InstrumentalEditStore` (`ObservableObject`, JSON en
   `~/Library/Application Support/xFlare/instrumental-edits.json`, por ruta).
   `AppModel.instrumentalEdits`.
3. **Editor** — `InstrumentalEditorView` (`Screen.instrumentalEditor(path:)`,
   se abre con el botón de ajustes de cada fila de la Librería). Reproduce de
   verdad (engancha `EngineHandle`): play/pausa, pinchar la onda para saltar,
   activar una región para **oír el loop** mientras se ajusta. Onda +
   rejilla de compases con números arriba (SwiftUI, macOS 11 → sin `Canvas`).
   Controles: BPM + TAP + ÷2/×2 + "fijar el 1 aquí" + compás; cues (añadir en el
   cabezal, renombrar, saltar, borrar); regiones (crear 4 compases, nudge de
   inicio/fin, activar, borrar). Al guardar, `InstrumentalEdit` por fichero.
4. **En la práctica** — `loadInstrumental` mira si hay `InstrumentalEdit`: si
   trae `bpm` / `downbeatSeconds`, mandan sobre la detección (rama "instrumental
   editada", pista larga, rota al "1", rejilla a ese BPM); si hay región de loop
   activa, se traduce a coords rotadas y se aplica con
   `setInstrumentalLoopRegion` tras cargar.

**Alternativas descartadas.** Editor solo visual sin sonido (el autor pidió
reproducción). Loop de región aproximado en Swift vigilando el cabezal y
saltando (jitter; el sitio correcto es el RT). Rotar la pista por el downbeat y
recalcular las regiones cada vez que se toca el tempo (frágil); en su lugar la
región activa se fija al cargar. Meter `beatsPerBar` por instrumental en la
rejilla de la práctica (la geometría es fija; el editor lo guarda pero la
práctica sigue en 4/4 de momento).

**Consecuencias.** `xf_player` gana 2 campos + 1 setter; el caso por defecto no
cambia (68→74 tests, los espectrales igual). `InstrumentalEdit` /
`InstrumentalEditStore` / `InstrumentalEditorView` nuevos en XFApp.
`LivePracticeView` gana `instrumentalEdit` (cableado en `AppRootView`).
**Pendiente (v2):** re-aplicar la región de loop tras ÷2/×2/reiniciar la base;
regiones que crucen el "1". *(Los puntos Cue en la propia práctica se cerraron en
la iteración 2, más abajo.)*

> **Iteración (2026-09-04).** Feedback del autor sobre el editor:
> - **Play no sonaba** al abrir el editor "en frío" (sin venir de una práctica):
>   `startEngine` no arrancaba la salida de audio. Ahora llama a
>   `engine.startOutput()` (idempotente: si ya suena, no-op).
> - **Zoom de la onda**: `zoom` (1…64×) + `viewStart`; botones `−`/`+`, y con
>   zoom un arrastre horizontal hace *pan* y un toque salta. La ventana sigue al
>   cabezal al reproducir. Rejilla, cues, regiones y cabezal se mapean por la
>   ventana visible.
> - **Regiones de loop con ÷2 / ×2**: `scaleLoop` dobla/mitad la duración
>   dejando el inicio fijo, recortado al fichero; la fila muestra
>   "N s · M compases".
>
> **Iteración 2 (2026-09-04).**
> - **La onda se re-renderiza al hacer zoom**: antes se estiraba una imagen del
>   fichero entero (borroso). Ahora `renderWindow` dibuja **solo el tramo
>   visible** del PCM a resolución alta (2400 px) en segundo plano, con un
>   contador de generación que descarta resultados que llegan tarde. Se llama al
>   cargar, al cambiar el zoom, al terminar un *pan* y cuando la ventana sigue al
>   cabezal.
> - **Los Cue de la instrumental se disparan por MIDI**:
>   `PracticeCommand.instrCue1…4` (`command.instr_cue_1…4`). En la práctica
>   `jumpInstrCue(i)` salta la base al Cue `i` del `InstrumentalEdit` cargado y
>   **re-cuadra** la rejilla y el metrónomo ahí (ese punto pasa a ser el "1", como
>   "reiniciar la base" pero desde el cue). También hay botones en la zona
>   inferior. Los cues activos se siembran en `loadInstrumental` desde
>   `edit?.cues`.
> - **Ajustes › MIDI por categorías**: `PracticeCommand.Category`
>   (`global` / `sample` / `instrumental`); `SettingsView.midiTab` pinta cada
>   grupo con su cabecera en vez de una lista plana.
>
> **Iteración 3 (2026-09-04).**
> - **El cue caía descentrado**: la línea del marcador iba centrada bajo su
>   etiqueta (VStack). Ahora la **línea** se pinta en la X exacta de `atSeconds`
>   y la etiqueta va a su derecha.
> - **Cue exacto al añadir**: `addCue`/`addLoop` usan `exactHeadSeconds` (posición
>   del cabezal leída **directa del motor**, no el `headFraction` a 30 Hz que va
>   medio frame por detrás).
> - **Cues arrastrables**: cada cue tiene una zona de agarre de 16 px con un
>   `DragGesture` de prioridad alta que mueve su `atSeconds` (mapeado por la
>   ventana visible / zoom); al soltar se re-ordenan.

---

## ADR-068 — Editor de samples: elegir inicio y duración (feedback 2026-09-04)

**Fecha:** 2026-09-04 · **Estado:** aceptada

**Contexto.** El autor pidió, como el editor de instrumental (ADR-067), un
**editor de samples**: "para que funcionen bien deben tener un máximo de tiempo;
se debe poder escoger el inicio y que se ajuste el tiempo del sample a usar".
Hasta ahora el sample se recortaba solo con `SampleTrim` (punto cero por RMS,
F.3) + `AudioAsset.capScratch` (tope de 2 s).

**Decisión.**
1. **Datos** — `SampleEdit` (puro, `Codable`): `startSeconds` + `lengthSeconds`,
   con `lengthSeconds` **acotado a `AudioAsset.scratchMaxSeconds`** (2 s) y
   mínimo 50 ms. `frameRange(frameCount:sampleRate:)` da el rango en frames ya
   acotado al fichero. `SampleEditStore` (`ObservableObject`, JSON en
   `~/Library/Application Support/xFlare/sample-edits.json`, por ruta).
   `AppModel.sampleEdits`.
2. **Editor** — `SampleEditorView` (`Screen.sampleEditor(path:)`, botón de
   ajustes en cada fila de la pestaña Samples de la Librería). Onda con zoom
   (mismo patrón que el editor de instrumental: `renderWindow` redibuja solo el
   tramo visible). Una **ventana de recorte** con dos asas arrastrables (inicio /
   fin); arrastrar el interior mueve toda la ventana. Fuera de la ventana la
   onda va oscurecida. Botones `◀/▶` para el inicio y la duración, "usar todo",
   y **"Escuchar el recorte"** — lo reproduce en bucle usando el reproductor de
   la BASE (`EngineHandle.previewLoop` a 120 BPM nativo = velocidad natural).
3. **En la práctica** — `loadScratchSample` mira si hay `SampleEdit` para la
   ruta: si lo hay, usa `pcm[frameRange]` tal cual (más `capScratch`); si no,
   `SampleTrim` como antes.

**Alternativas descartadas.** Editar sobre el reproductor de scratch (solo suena
con velocidad; la audición lineal necesita el de la base). Guardar el recorte
como un fichero nuevo (xFlare no escribe los ficheros del usuario; el `SampleEdit`
es un puntero + rango). Meterlo en el mismo store que los `InstrumentalEdit`
(conceptos distintos, fichero aparte más claro).

**Consecuencias.** `SampleEdit` / `SampleEditStore` / `SampleEditorView` nuevos
en XFApp. `EngineHandle` gana `previewLoop` / `stopPreview` (reutilizan el
reproductor de la base; la práctica lo recarga al volver a entrar).
`LivePracticeView` gana `sampleEdit` (cableado en `AppRootView`). `MediaLibraryView`
gana `onEditSample` y el botón de editar aparece también en las filas de sample.
**Pendiente (v2):** ganancia / fade del recorte; forma de onda del sample con el
punto cero marcado.

---

## ADR-069 — Cues/loops de la instrumental visibles en la práctica + navegación (feedback 2026-09-04)

**Fecha:** 2026-09-04 · **Estado:** aceptada

**Contexto.** Tras los editores (ADR-067/068), el autor señaló tres cosas:
1. En el editor de samples, poner el inicio "a raíz de" los transitorios y luego
   afinar a mano.
2. Los cues y las regiones de loop programados en el editor de instrumental **no
   se veían** al cargar la base en un ejercicio o en Freestyle.
3. Faltaban botones —mapeables a MIDI— para **saltar al loop / loop siguiente /
   anterior**, y lo mismo para los cues.

**Decisión.**
- **Transitorios (editor de samples).** `TransientDetector` (puro, XFApp): sin
  FFT — envolvente de **log-energía** en tramos de ~5 ms, **flujo positivo**
  (subidas de energía), **umbral adaptativo** con la media local · factor
  (`sensitivity` lo modula) y **separación mínima** de 40 ms. `SampleEditorView`
  pinta las marcas (amarillo) sobre la onda y añade "inicio ◀ / al más cercano /
  ▶"; el `◀/▶` de Inicio baja de 20 a **5 ms** para el ajuste fino.
- **Pintado en la práctica.** `PracticeScene` gana `instrumentalCues`
  (`[Double]`, fracción 0…1 del bucle) e `instrumentalLoopRegion`
  (`(start,end)` fracciones), dibujados sobre la **tira superior** —cue = línea
  vertical amarilla, loop = banda de acento con sus bordes— en 3 copias, igual
  que los sprites de la onda, para que sigan al bucle en cada vuelta.
  `LivePracticeView` guarda `instrDownbeatSec` (el desfase con el que se rotó el
  fichero al "1") y con él mapea `atSeconds` del fichero a la tira ya rotada
  (`loopFraction`).
- **Navegación + MIDI.** `PracticeCommand` +5: `instrCuePrev` / `instrCueNext`
  (cue relativo al cabezal, en círculo) y `loopJump` / `loopPrev` / `loopNext`
  (recorren las regiones del editor y las **aplican en caliente** con
  `EngineHandle.setInstrumentalLoopRegion`, saltando a su inicio y re-cuadrando
  la rejilla). Todas categoría `.instrumental` → aparecen solas en Ajustes ›
  MIDI. La aritmética de bordes (dar la vuelta, sin activa, epsilon para no
  re-disparar el cue actual) va en `InstrumentalNav` (puro, testeado); la vista
  solo la usa.

**Alternativas descartadas.** Onset por flujo espectral (necesita FFT; para un
sample de scratch —una frase con pocos ataques— la energía basta y es más
barata y legible). Dibujar los cues/loops en la autopista en vez de la tira (la
tira ES la instrumental; ahí es donde el autor los espera). Un estado "loop
apagado" al ciclar (los botones recorren solo las regiones definidas; apagar el
loop es otro gesto). Reaprovechar `instrCue1…4` con módulo (el autor pidió
explícitamente "anterior/siguiente", que es relativo al cabezal, no un índice).

**Consecuencias.** XFApp: `TransientDetector`, `InstrumentalNav` nuevos;
`PracticeScene` / `PracticeSceneView` / `LivePracticeView` / `SampleEditorView`
tocados. XFCapture (WIP): `PracticeCommand` +5 casos con su `confKey`, `label` y
`category`. Ajustes › MIDI no cambia (ya itera por categoría). **Límite (v1):**
una región de loop que cruce el "1" se ignora al pintarla y al aplicarla (igual
que ya hacía el audio). Tests: `TransientDetectorTests` (5), `InstrumentalNavTests`
(7), `PracticeCommandMidiTests` +1 → 686 en verde.

> **Iteración (2026-09-04, mismo día).**
> - **El loop no sonaba.** La región solo se aplicaba al motor en la rama
>   "instrumental editada" (`edit.bpm != nil || edit.downbeatSeconds != nil`).
>   Si el usuario solo había marcado un loop, `loadInstrumental` caía en la rama
>   de detección y **no** llamaba a `setInstrumentalLoopRegion`: se veía la zona
>   sombreada pero la base sonaba entera. Ahora la región activa del `edit` se
>   aplica **tras el cascade de ramas**, en cualquiera, y además
>   `seekInstrumental` deja la base **dentro** del loop (su inicio = el "1").
> - **Interruptor de loop** en la práctica (ejercicio y Freestyle): `loopToggle`
>   en la fila "Loops" del panel y —para tenerlo a mano sin desplegar— en la
>   fila compacta de la base. On = repite la región; off = base entera
>   (`applyLoopRegion(0)` / `applyLoopRegion(nil)`). Si el editor dejó una
>   región activa, arranca **encendido**.
> - **Aviso al cargar otra base.** `loadInstrumental` no-inicial: se **mutea**
>   la base actual (`setInstrumentalGain(0)`) y sale un cartel "Cargando N…"
>   hasta que la nueva está lista (una pista larga tarda ~1-2 s decodificando y
>   antes no había ninguna señal). `instrLoadGen` descarta una carga si ya
>   empezó otra posterior.

---

## ADR-070 — Logo: subir de tono las partes oscuras (feedback 2026-09-04)

**Fecha:** 2026-09-04 · **Estado:** aceptada

**Contexto.** Sobre el tema oscuro de la app (y del icono en el Dock/Finder en
modo oscuro), las zonas casi negras del logo —parte baja de la placa
(`#10141A`), la ranura del fader (`#080A0D`), el borde y el surco del cap
(`#06201B` / `#06231E`)— se fundían con el fondo: se veía una mancha verde sin
canto ni detalle. Feedback repetido del autor ("cambiando de color las partes
oscuras").

**Decisión.** Recolorar todo lo que iba casi negro a **tonos medios / claros**,
manteniendo el orden de lecturas:
- `icon/xflare.svg`: placa `#3B4551→#262E38` (antes `#333C49→#10141A`), ranura
  `#2C343E` (antes `#080A0D`), borde del cap **claro** `#EAFBF7`@0.55 (antes
  `#06201B`), surco del cap verde **medio** `#0F6F62` (antes `#06231E`), sombra
  del cap 0.28→0.20. Marcas y labios de la ranura, un punto más claros.
- `XFWordmark.mark`: **rediseñado como miniatura del icono** (placa + riel +
  tapa fantasma + tapa viva con borde claro + surco de agarre verde medio
  `#0F6F62`). Antes era una silueta plana con un corte que, en pantalla, seguía
  leyéndose como una mancha verde; ahora tiene el mismo lenguaje que el icono.

**Alternativas descartadas.** Un logo distinto (el motivo —cap de crossfader en
planta— se mantiene, solo cambia la paleta). Poner el logo sobre un chip claro
en la barra (parche, no arregla el icono del sistema).

**Consecuencias.** Solo activos de diseño: `icon/xflare.svg` (+ `xflare.icns` /
PNGs regenerados con `sh icon/build-icns.sh`) y `Sources/XFApp/XFWordmark.swift`.
Sin código nuevo, sin tests.

---

## ADR-071 — Descomposición mano / fader en la práctica (F.23)

**Fecha:** 2026-09-04 · **Estado:** aceptada

**Contexto.** Así se enseña un flare con un profesor delante: se separan las
manos. Primero el giro del disco solo, con el fader abierto; luego el corte del
fader solo, con el disco quieto o en modo automático; y cuando cada mano va sola,
se juntan. Ningún entrenador de scratch (Melodics, los DVS) ofrece esto — y
xFlare ya tenía toda la maquinaria: el fantasma del "repite conmigo"
**ya mueve las dos capas** (`ghostPosition` + `ghostFaderOpen` en
`PracticeSession.advance`).

**Decisión.** Un modo `AssistMode` en `PracticeSession` con tres casos:
`both` (práctica normal, tú llevas las dos), `hand` (tú el disco, la máquina
corta el fader clavado al patrón), `fader` (la máquina mueve el disco sobre el
patrón, tú cortas). La máquina lleva **la capa que tú sueltas**, muestreada de la
misma curva del patrón que usa la escucha, en `currentTick + gridPhaseTicks`.

El modo es **ortogonal al "repite conmigo"**: durante la fase `listen` la máquina
toca las dos capas pase lo que pase (`machineDrivesDisc`/`machineDrivesFader`
son `crPhase == .listen || …`); `assist` solo manda en tu turno y en la práctica
libre. `setFaderClosed` (input) se ignora cuando la máquina lleva el fader; las
rutas internas usan un `applyFaderClosed` privado que no mira quién manda.
`scrollBy`/`nudge` se ignoran cuando la máquina lleva el disco (misma guarda que
ya tenía la escucha).

UI: sección **"Manos"** en el rail derecho de la práctica (también en Freestyle),
tres botones; insignia ámbar en la barra superior mientras el modo no es `both`;
comando MIDI `assist_cycle` (categoría global) que recorre los tres.

**Alternativas descartadas.** Reutilizar la escucha del call & response para esto
(son cosas distintas: la escucha es "mira y escucha", esto es "toca una capa
mientras yo llevo la otra"). Un cuarto modo "ninguna" (la práctica libre ya lo
es). Botones separados por capa en vez de un ciclo para MIDI (un solo botón de
mesa basta y sobra).

**Consecuencias.** `PracticeSession` gana `AssistMode`, `assist`, `setAssist`,
`cycleAssist`, `machineDrivesDisc`/`machineDrivesFader` y el split
`setFaderClosed` / `applyFaderClosed`. `LivePracticeView` gana la sección
"Manos", la insignia y el caso `.assistCycle` en `handleCommand`. XFCapture
(WIP): `PracticeCommand.assistCycle`. `docs/CURRICULUM.md` debería, más adelante,
recomendar el modo por nivel de truco. Tests: `PracticeSessionTests` +7,
`PracticeCommandMidiTests` +1 → 693 en verde.

---

## ADR-072 — Primera tanda de "tacto": latencia del gesto y frenado del plato (F.01/F.03/F.04/F.08)

**Fecha:** 2026-09-04 · **Estado:** aceptada

**Contexto.** Leyendo `xf_player.c` / `xf_engine.c` / `PracticeSession` /
`PlatterInputView` para responder a "que vaya mejor la sensibilidad y el tacto":
el presupuesto de latencia de `CLAUDE.md` mide el camino del **audio**, pero el
camino del **gesto** tenía dos tramos grandes sin contar (~24 ms de media) y un
bug de inercia. El `glide` de 3 ms, el único mando que había, es la porción más
pequeña — por eso tocarlo se nota tan poco.

**Decisión.** Cuatro cambios, todos en XFApp, que se refuerzan:

- **F.03 — ignorar la inercia del trackpad.** `PlatterInputView.scrollWheel`
  descarta los eventos con `momentumPhase != []` (los que macOS sigue mandando
  tras levantar los dedos). Sin esto el plato recibía empujones de una mano que
  ya no estaba **y** la sesión le aplicaba su fricción: inercia doble, el disco
  se escapaba justo al querer pararlo. Es un bug.
- **F.01 — velocidad al motor a ritmo de evento.** El `onScroll`/`onNudge` de
  `LivePracticeView` empuja la velocidad al `EngineHandle` **en el instante del
  evento** (`pushPlatterVelocity()`), sin esperar al siguiente paso de 60 Hz de
  `PracticeSession` (0–16,7 ms de espera). El reloj de sesión sigue integrando a
  60 Hz para la traza dibujada y el ancla de posición (`onAdvance`), que son
  correcciones lentas. Misma conversión que `onAdvance`.
- **F.04 — buffer de arranque 512 → 128.** `AppSettings.defaultBufferFrames`
  (nuevo) = 128 (2,7 ms). Antes `defaults` enviaba 512 (10,7 ms) mientras el
  asistente de calibración proponía 64 y ADR-024 presupuesta 1,33. Recorta ~16 ms.
  La subida automática al detectar overloads sigue pendiente (B1.6); mientras
  tanto se sube a mano en Ajustes.
- **F.08 — frenado con rozamiento seco.** `PracticeSession.decayPlatterVelocity`
  añade al decaimiento exponencial un término de **Coulomb** (`coulombFriction`,
  deceleración constante) que para el plato **en firme** cerca de cero, en vez de
  arrastrarse asintóticamente. Es la detención corta y seca de un slipmat real.
  Sustituye el corte a `1e-4` que había.

**Alternativas descartadas.** Bajar a 64 frames de golpe (128 es el compromiso
seguro del Intel de 2015 sin la lógica adaptativa de B1.6). Tocar la frontera
C↔Swift para F.01 (no hace falta: `setVelocity` es un store atómico, se puede
llamar desde el hilo de UI en el evento). El modelo de **posición** en vez de
impulso (F.02): cambia cómo se *siente* el gesto, no cuánto tarda — mejor
hacerlo cuando la latencia ya esté baja, para poder juzgarlo. Un slider de
Coulomb en Ajustes › Debug (el valor por defecto es sensato; se expone si
alguien lo quiere afinar).

**Consecuencias.** `PlatterInputView` (+1 guarda), `LivePracticeView`
(`pushPlatterVelocity`, `onScroll`/`onNudge`), `PracticeSession`
(`coulombFriction`, `decayPlatterVelocity`), `AppSettings`
(`defaultBufferFrames`, el fallback de `bufferFrames` ya no es 512 literal).
Nada de RT en C. **La primera vez que la app arranca tras esto, corre a 128
frames**: si el Intel de 2015 crepita, subir en Ajustes › Audio. Tests:
`PracticeSessionTests` +1 (`testElRozamientoSecoParaElPlatoEnFirme`) → 694 en
verde. El resto del cuaderno del tacto (F.02, F.05–F.10, I.01–I.10) queda en
FUTURIBLES.

> **Iteración — F.44, modelo de posición (mismo día).** El trackpad deja de
> usar el modelo de **impulso** (`scrollBy`: `velocity += Δx·ganancia`, un
> volante que acumula momento) y pasa a **control de posición**: mientras tienes
> los dedos en el cristal, `velocity = Δx/Δt · scrubGain · sensibilidad` — la
> velocidad del plato ES la de tu mano. `PlatterInputView` distingue "mano
> puesta" (`event.phase` .began/.changed/.stationary → `onScrub(puntos/s)`) de
> "mano fuera" (.ended/.cancelled → `onScrubEnd`), sacando la velocidad del
> `Δ event.timestamp` entre eventos (acotado a [1/240, 1/30] s). `PracticeSession`
> gana `scrub(pointsPerSecond:)` / `endScrub()` / `scrubbing` (+ auto-soltado a
> los 80 ms sin eventos, por si no llega el `.ended`) y `coastPlatter(step:)`
> que **no aplica fricción mientras `scrubbing`**. Consecuencia clave: parar la
> mano **sin levantarla** (`Δx≈0`) para el plato **en seco** — como sujetar el
> vinilo —, algo que el modelo de impulso no podía. La rueda de ratón (sin
> `phase`) sigue con `scrollBy` (impulso). `scrubGain` (0,02) y `coulombFriction`
> (3,0) son `public var` con default sensato; la "Sensibilidad trackpad" y la
> "Fricción" de Ajustes › Debug ya los modulan (sliders propios: follow-up).
> Tests: `PracticeSessionTests` +4 → 698 en verde.

> **Iteración — F.45, más cubos de ratio de resampling (mismo día).**
> `xf_player.c`: `XF_PLAYER_RATIOS` pasa de 7 cubos elegidos a ojo
> (`{1, 1.5, 2, 3, 4, 6, 8}`, con saltos grandes entre los altos — 6→8 = +33 %,
> que se oían como un escalón de brillo al barrer la velocidad — y sin ningún
> cubo por encima de 8×, así que un scribble o crab que se pasaba de ahí se
> quedaba con el kernel de 8×, filtrando de más de lo necesario) a **24 cubos
> espaciados LOGARÍTMICAMENTE de 1× a 16×** (salto relativo constante, ~12,7 %,
> en todo el rango). Coste: la tabla de kernels crece de 7×512×32 a 24×512×32
> floats (~1,5 MB), calculada **una sola vez** en `xf_player_create`
> (`NO RT-SAFE`, ya lo era). El render (`xf_player_render`) no cambia una
> línea: sigue siendo una búsqueda acotada (`xf_player_ratio_index`) sobre una
> tabla más larga — coste RT igual de barato. La garantía "se filtra de más,
> nunca de menos" (nunca aliasing) se mantiene igual para velocidades por
> encima de 16× (usan el cubo 16×, como antes usaban el de 8×). Test:
> `testAliasingSuprimidoPorEncimaDelTechoAntiguoDe8x` (v=12, fuera del rango
> viejo) → 699 en verde.

---

## Plantilla para nuevas entradas

```markdown
## ADR-0NN · Título breve

**Fecha:** AAAA-MM-DD · **Estado:** propuesta | aceptada | sustituida por ADR-0MM

**Contexto.** Qué problema hay que resolver.

**Decisión.** Qué se ha decidido, en una frase.

**Alternativas descartadas.** Qué más se valoró y por qué no.

**Consecuencias.** Qué gana, qué pierde, qué queda condicionado.
```
