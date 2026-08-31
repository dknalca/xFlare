# DECISIONS.md — xFlare

> Registro de decisiones de arquitectura (ADR). Cada entrada explica **qué** se
> decidió, **por qué**, **qué se descartó** y **qué cuesta**.
>
> Regla: toda decisión técnica no trivial que se tome durante el desarrollo se
> añade aquí. Si dudas de si merece una entrada, la merece.

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

## Plantilla para nuevas entradas

```markdown
## ADR-0NN · Título breve

**Fecha:** AAAA-MM-DD · **Estado:** propuesta | aceptada | sustituida por ADR-0MM

**Contexto.** Qué problema hay que resolver.

**Decisión.** Qué se ha decidido, en una frase.

**Alternativas descartadas.** Qué más se valoró y por qué no.

**Consecuencias.** Qué gana, qué pierde, qué queda condicionado.
```
