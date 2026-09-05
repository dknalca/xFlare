# Plan: acabar con el "sticker drift"

> Estado (actualizado 2026-09-05, misma tarde): **Fases 0, 1 y 2 hechas**,
> más un cierre de la Fase 2 que el plan original ya anticipaba (punto 4,
> "detección de salto de aguja"). Fase 3 (servo del audio) y Fase 4
> (fixtures grabados) **pendientes** — la 4 necesita hardware real, no se
> puede avanzar más sin él. Detalle abajo, en cada fase.
>
> Redacción original: 2026-09-05 por la mañana. Contexto: F.70/F.74/F.75
> (ADR-076/078/079) atacaron el síntoma tres veces y el problema seguía.
> Este documento cambió el enfoque: primero medir, después arreglar la
> raíz — y así se hizo.

---

## 0. El síntoma, en las palabras del autor

> "Conforme avanza el tiempo el sonido empieza en un lugar diferente. Si
> empieza a las 12:00 del vinilo luego está a las 11, luego a las 10, y en la
> onda tampoco coincide."

Traducido a números: una hora del reloj del vinilo = **1/12 de vuelta = 30° =
150 ms** de sonido a 33⅓ rpm. Y **crece de forma monótona**. Eso no es ruido
ni redondeo: es una **pérdida sistemática y acumulativa** de movimiento. Algo
en la cadena está tirando movimiento real del vinilo a la basura, una y otra
vez, siempre en el mismo sentido.

---

## 1. Aclaración importante: modo relativo ≠ renunciar a la posición absoluta

El autor recuerda, con razón, que xFlare usa **modo relativo** (CLAUDE.md,
glosario: "sólo velocidad y dirección"). Eso es y sigue siendo correcto: el
sample **no** debe engancharse a la posición física de la aguja en el disco.

Pero hay una confusión de fondo que ha costado tres iteraciones:

> **Modo relativo describe el COMPORTAMIENTO, no la fuente de datos.**

El vinilo de timecode lleva grabado un **bitstream de posición absoluta**, y
xwax **ya lo está decodificando ahora mismo** en xFlare. Usar ese dato como
*regla de medir* no convierte la app en modo absoluto — el punto de inicio del
sample sigue siendo donde el usuario lo puso. Solo cambia **cómo medimos
cuánto se ha movido el disco**: en vez de sumar estimaciones (que acumulan
error), restamos dos lecturas absolutas (que no lo acumulan).

Esto es exactamente lo que hacen Serato y Traktor internamente en modo
relativo. **La posición absoluta es la cura del drift, no lo contrario.**

---

## 2. Diagnóstico: los cinco canales de pérdida (con fichero y línea)

Investigados sobre el código actual, no supuestos.

### A. El bitstream absoluto se decodifica y **se tira** — `xf_timecode.c:98`

```c
double when;
bool locked = (timecoder_get_position(&x->tc, &when) >= 0);
x->conf = locked ? 1.0f : rms_conf;
```

`timecoder_get_position()` devuelve la **posición absoluta** en el disco. Se
llama, se compara con `>= 0`… y el valor **se descarta**: solo se usa como un
booleano para la confianza. `when` (hace cuánto se leyó) también se ignora.

Resolución disponible que estamos tirando: la definición `serato_2a` tiene
`resolution = 1000` → **1 unidad = 1 ms nominal = 1/1800 de vuelta ≈ 0,2° de
vinilo**. Es decir: tenemos a mano una regla 150 veces más fina que la deriva
que sufre el autor, y no la usamos.

B5.5 ya confirmó con el vinilo Serato CV02 real sobre la Rane 72:
`engancho bitstream: SI`. **El dato está ahí y funciona.**

### B. La posición se **integra**, y la integración acumula — `xf_timecode.c:87`

```c
x->vel = timecoder_get_pitch(&x->tc);
x->pos += x->vel * (double)nframes / x->sr;
```

`pos` es la suma de estimaciones de velocidad. `timecoder_get_pitch` sale de un
filtro alfa-beta: **retrasa** y **sesga** durante la aceleración — y un scratch
es aceleración pura, todo el rato. Cualquier sesgo, por pequeño que sea, se
integra hasta el infinito. Un sesgo del 0,1 % da 30° de deriva en 5 minutos.

Nota: F.74 (ADR-078) ancló `PracticeSession` a este `pos`. Fue una mejora real
—quitó un integrador de la cadena— pero ancló a una regla que **ella misma
deriva**. De ahí que el síntoma siguiera.

### C. El gate de confianza **descarta movimiento real** — `LivePracticeView.swift:1539`

```swift
guard captureRealTimecode, sample.confidence >= 0.6, ... else { return }
```

Y en `xf_timecode.c:95`:

```c
if (fabs(x->vel) > 4.0) rms_conf *= 0.3f;   // -> conf <= 0.3 -> DESCARTADA
```

Con el bitstream enganchado `conf = 1.0` pase lo que pase. Pero en un scratch
rápido el bitstream **se desengancha** (`valid_counter` se resetea en xwax) y
entonces `conf ≤ 0.3` → **la muestra se tira entera**.

Traducción: *cuanto más rápido scratcheas, más movimiento se pierde.* Es
precisamente el gesto que el autor hace todo el rato.

### D. El watchdog de F.70 **borra la referencia** — `PracticeSession.swift:357`

```swift
if timecodeDriving, CACurrentMediaTime() - lastTimecodeAt > 0.08 {
    timecodeDriving = false
    platterVelocity = 0
    realMotionAnchorRevolutions = nil        // <- suelta el ancla
    realMotionAnchorPlatterPosition = nil
}
```

El comentario dice que arrastrar el ancla vieja "sí sería sticker drift". **Es
al revés.** Cuando la señal vuelve, la siguiente muestra fija un ancla NUEVA en
la `platterPosition` actual — o sea, damos por hecho que el vinilo **no se
movió** durante el hueco. Pero se movió: el usuario estaba scratcheando, que es
justo por lo que se perdió el enganche.

Combinado con **C**: un scratch rápido de >80 ms rompe el enganche, se
descartan las muestras, salta el watchdog, y **todo ese movimiento desaparece
de la contabilidad**. Cada gesto rápido se come un trozo de referencia. Este
es, con diferencia, el sospechoso principal del "12:00 → 11:00 → 10:00".

### E. El ring buffer pierde frames en silencio y **nadie lo mira**

- Capacidad: `xf_engine.c:132` → `block_bytes * 32`. Con buffer de 128 frames
  son ~4096 frames = **85 ms**.
- Consumidor: `AppModel.swift:174` → un `Timer` a **30 Hz en el hilo
  principal**, compitiendo con SwiftUI y SpriteKit a 60 fps.
- Productor: `xf_ring_write` **trunca en silencio** si está lleno
  (`xf_ring.c:60`).

Cualquier tirón del hilo principal de más de 85 ms (reconstruir una vista,
renderizar una onda, abrir un menú, cargar un sample) → frames descartados →
movimiento perdido para siempre.

Y lo más revelador de todo:

```c
if (wrote < want) atomic_fetch_add(&e->input_ring_drops, 1);   // xf_engine.c:464
```

**El contador existe, se incrementa… y no hay ni un getter. Nadie lo lee
jamás.** Llevamos tres rondas de arreglos a ciegas con un medidor de pérdidas
ya instalado en el motor y apagado.

---

## 3. La causa de fondo del *proceso*, no solo del código

F.70, F.74 y F.75 siguieron el mismo patrón: síntoma → hipótesis → arreglo →
"pruébalo en la mesa" → sigue igual. Tres veces.

El motivo es que **la deriva nunca se ha medido**. Sin un número no se puede
saber si un cambio mejoró un 90 % o un 3 %, ni cuál de las cinco causas pesa
más. "Sigue habiendo mucho drift" y "quedan 4 ms tras 3 minutos" exigen
respuestas distintas, y con el oído no se distinguen.

**Por eso la fase 0 no es opcional y no es código de producto.** Es lo que
convierte este problema de una discusión en una medición.

---

## 4. Arquitectura objetivo

Hoy hay **tres integradores independientes**, cada uno con su propio error:

```
xwax pos  ──(F.74 ancló)──▶  platterPosition  ──(trim lento)──▶  xf_player.playhead
 (integra)                     (ahora esclavo)                    (integra otra vez)
```

Objetivo: **una sola verdad, medida y no acumulada**, y todo lo demás esclavo
de ella por POSICIÓN (no por velocidad):

```
bitstream absoluto (Δ exactos, error acotado a ±1 ms para siempre)
        │
        ├──▶ platterPosition   (traza teal)
        └──▶ playhead de audio (servo de tasa, no integrador libre)
```

La regla de oro que hoy se incumple en tres sitios:

> **La velocidad sirve para el TONO. La posición sirve para la POSICIÓN.**
> Nunca se obtiene la posición integrando la velocidad si hay una medida
> directa disponible.

---

## 5. Plan por fases

Cada fase es independientemente verificable y deja el producto en un estado
mejor que el anterior. **No se pasa de fase sin un número que lo justifique.**

### Fase 0 — Hacer visible la deriva  ·  *sin esto, no seguimos* ✅ HECHA

**F.76 (ADR-080)**, con una corrección el mismo día (el medidor daba
"−136567 ms" la primera vez — bug del cálculo, no deriva real; ver el
addendum de ADR-080). El paso Timecode del asistente enseña Deriva/
Enganchado/Frames perdidos en vivo. Sin el punto 4 (volcado a CSV) — no
hizo falta: el panel en pantalla bastó para decidir cada fase siguiente.

**No toca el comportamiento del producto.** Solo instrumenta.

1. Getter de `input_ring_drops` (+ resetear al arrancar la captura).
2. Exponer del decoder, además de lo que ya sale: posición absoluta del
   bitstream, `when`, y si está enganchado.
3. **Medidor de deriva** en la práctica (detrás del toggle de Debug):
   - `deriva = pos_integrada − pos_absoluta`, en **ms y en grados de vinilo**.
   - % de tiempo con bitstream enganchado.
   - muestras descartadas por confianza · veces que saltó el watchdog ·
     frames perdidos del ring.
4. Volcado a CSV de esas series para poder mirarlas en frío (`tools/`).

**Criterio de aceptación:** el autor scratchea 3 minutos y puede leer "la
deriva es de X ms y sube en escalones de Y cada vez que hago un crab". A
partir de ahí dejamos de adivinar.

**Coste estimado:** pequeño. Es el mejor retorno de todo el plan.

### Fase 1 — Cerrar las hemorragias (C, D, E) ✅ HECHA

**F.77 (ADR-081)**: el ring se drena en su propia cola a 100 Hz, fuera del
hilo principal — frames perdidos bajó de 977-1433 a un ~74 fijo de
arranque (confirmado con números reales de la Rane 72). El gate de
confianza (C) y el watchdog (D) se resolvieron distinto de como los
planteaba este documento: en vez de "el gate elige estrategia", **F.78
(ADR-082)** hizo que `PracticeSession` prefiriera directamente la posición
absoluta cuando hay enganche — ver Fase 2, que en la práctica absorbió
ambos puntos. `hostTime` correcto (punto 4) sigue sin tocarse — no hizo
falta para resolver el síntoma, pendiente si aparece necesidad concreta.

Baratas, de bajo riesgo, y probablemente se llevan la mayor parte del problema.
Se hacen **antes** que la fase 2 porque son sencillas y porque la fase 0 ya
permite medir cuánto aporta cada una.

1. **El gate de confianza deja de tirar movimiento.** La confianza pasa de ser
   un filtro de "acepto/descarto" a elegir *estrategia*:
   - enganchado → posición absoluta (fase 2);
   - sin enganche pero con señal → integrar velocidad (lo de ahora), marcando
     el tramo como "estimado";
   - sin señal de verdad → congelar.
   Nunca se descarta una muestra que trae movimiento.
2. **El watchdog distingue dos casos distintos** que hoy trata igual:
   - *el vinilo se ha parado* (hay señal, velocidad ≈ 0) → congelar, correcto;
   - *hemos perdido la señal* (sin señal / sin enganche) → **conservar el
     ancla** y reconciliar cuando vuelva, en vez de borrar la referencia.
3. **El ring deja de perder frames:** drenar fuera del hilo principal (cola
   propia de alta prioridad) y subir la capacidad a ~0,5 s. Con el contador de
   la fase 0 se verifica que baja a cero.
4. **`hostTime` correcto:** hoy `pollTimecode` sella la muestra con
   `HostClock.now()` (cuando se *drena*), no con el instante de captura —
   hasta 85 ms tarde y con jitter. Latente hoy, veneno para cualquier cálculo
   temporal futuro.

### Fase 2 — La posición absoluta como verdad  ·  **el arreglo de raíz** ✅ HECHA

**F.76/ADR-080** expuso la posición absoluta del wrapper (con el ADR y
permiso del autor para tocar `CXFTimecode`/`XFCapture` SEALED, aditivo).
**F.78/ADR-082** hizo el primer intento de usarla para corregir — tenía un
defecto (reanclaba en cada transición enganche↔sin enganche, congelando el
sesgo acumulado en los huecos); el autor lo detectó en la Rane 72
("impracticable") y **F.81/ADR-085** lo corrigió con un desplazamiento
FIJO en vez de reanclar. El punto 4 de aquí abajo ("detección de salto de
aguja") se implementó como **F.82/ADR-086**: una puerta de plausibilidad
que suaviza (no rechaza) una corrección grande en vez de teletransportar
de golpe — investigado contra el código real de xwax y de Mixxx antes de
implementarlo (ver ADR-086 para el porqué). Objetivo de deriva acotada:
**pendiente de confirmar con números reales tras F.82** — el autor todavía
no ha vuelto a probar en la Rane 72 desde este último cambio.

1. Ampliar el wrapper `xf_timecoder` (sin tocar xwax vendorizado) para exponer
   la posición absoluta ya compensada por `when`:
   `abs_pos_ahora ≈ abs_pos_leída + velocidad · when`.
2. **Avanzar el plato por DELTAS de posición absoluta**, no por integración:
   ```
   Δ = abs_pos(ahora) − abs_pos(anterior)      // error NO acumulativo
   platterPosition += Δ                        // comportamiento relativo intacto
   ```
   Cada lectura es una medida independiente: el error se queda acotado en
   ±1 ms **para siempre**, en vez de crecer sin límite.
3. **Reconciliación al recuperar el enganche:** mientras no hay bitstream se
   integra la velocidad (inevitable); en cuanto vuelve el enganche, el delta
   absoluto corrige de golpe todo el error acumulado en ese hueco. Un scratch
   que rompe el enganche 200 ms deja 200 ms de error, no error permanente.
4. **Detección de salto de aguja:** si el delta absoluto es incompatible con el
   tiempo transcurrido (nadie mueve el disco a 50×), es que han levantado y
   dejado caer la aguja → re-anclar, no aplicar el delta.

**Criterio de aceptación (medible, no de oído):** con el medidor de la fase 0,
la deriva tras 5 minutos de scratch continuo se queda **acotada** (no crece).
Objetivo: < 5 ms ≈ 1° de vinilo, frente a los 30° y subiendo de hoy.

### Fase 3 — Un solo integrador: el audio esclavo de la misma verdad ⏳ PENDIENTE (solo el ajuste, no la arquitectura)

**Corrección (2026-09-06):** revisando `xf_player.c` línea por línea, el
mecanismo que pide esta fase **ya existe**, construido en F.42/ADR-042 y
hecho afinable en F.75/ADR-079 — no hay que construir nada nuevo:

```c
// xf_player.c:301, dentro del render RT
double trim = (p->target_playhead - p->playhead) * p->seek_coef;
/* acotado a ±p->seek_max_trim */
v += trim;   // v = velocidad_timecode + k · (objetivo − cabezal)
```

Es EXACTAMENTE `tasa_efectiva = velocidad + k · (objetivo − cabezal)` — el
servo de tasa que describe esta fase, con `k = seek_coef` y el tope de
`seek_max_trim`, ambos ya tunables desde Ajustes › Debug
(`scratchSeekTrimMs`/`scratchSeekMaxTrim`, F.75). Lo único que falta es
**subir el valor de `k`** ahora que el objetivo es exacto (F.81/F.82,
antes era un `platterPosition` que podía derivar) — el barrido que
ADR-042 temía solo aparecía porque el objetivo de entonces era malo. Pero
esto es una decisión de OÍDO en la mesa real (el propio ADR-079 ya dejó
los valores conservadores a propósito por esto mismo): no se cambia el
default sin poder escucharlo. Pendiente: el autor prueba valores de
`scratchSeekTrimMs`/`scratchSeekMaxTrim` más agresivos en la Rane 72 y, si
encuentra uno que cierra el hueco "se ve la onda y no suena" sin sonar a
barrido, ese pasa a ser el nuevo default.

Hoy el cabezal de audio (`xf_player`) integra su propia velocidad y solo se
corrige con un trim lento (ADR-042; F.75 lo hizo afinable). Es el tercer
integrador y la causa de "se ve la onda y no suena, y suena donde no hay onda".

Con una posición objetivo ya exacta (fase 2), el trim puede convertirse en un
**servo de tasa** de verdad:

```
tasa_efectiva = velocidad_timecode + k · (posición_objetivo − posición_cabezal)
```

Con el objetivo exacto el término de error es diminuto, así que `k` puede ser
mucho más agresivo que hoy **sin que se oiga**: el barrido que ADR-042 temía
solo aparecía porque el objetivo era malo. Basura entra, basura sale.

Esto es lo que hace que "la onda cuadre perfecto con el teal" sea cierto **por
construcción**, no por ajuste manual de sliders.

### Fase 4 — Que no vuelva nunca: test de regresión con señal real ⏳ PENDIENTE — necesita hardware

`Fixtures/sessions/` sigue vacío. Como paliativo SIN hardware (2026-09-05)
se añadió un test sintético de estrés en `PracticeSessionTests`
(`testSesionLargaConEngancheIntermitenteNoAcumulaDerivaAlLargoPlazo`):
cientos de muestras alternando enganche/sin-enganche con sesgo sintético
en la integral, comprobando que la deriva total se queda acotada durante
toda la sesión simulada — no sustituye a un fixture con ruido/bitstream
real (eso solo lo puede grabar el autor con la mesa delante), pero cubre
la lógica de la fusión sin depender de él.

Sin esto, cualquier cambio futuro puede reintroducir la deriva en silencio.

1. Grabar un `.wav` del timecode real de la Rane 72 con un gesto **conocido**:
   p. ej. 60 s de scratch variado y devolver el sticker exactamente a las
   12:00. Va a `Fixtures/`. **Esto lo tienes que capturar tú** (hace falta el
   hardware); yo preparo la herramienta de captura.
2. Test *offline* que mete ese wav por la cadena de decodificación y afirma:
   `|posición_final − posición_inicial| < N ms`.
3. Un segundo fixture con dropouts provocados (levantar la aguja a mitad) para
   fijar el comportamiento de reconciliación.

Este es el paso que convierte "arreglado hoy" en "arreglado de una vez por
todas".

---

## 6. Cómo cambia la forma de trabajar (la parte de "mejorar el desarrollo")

Lo que ha fallado no es solo el código; es el bucle de trabajo.

| Antes | A partir de ahora |
|---|---|
| Síntoma → hipótesis → arreglo → "pruébalo" | Síntoma → **medir** → localizar la causa con el número → arreglar → **volver a medir** |
| Verificación de oído / de vista | Verificación numérica; el oído solo para lo que de verdad es subjetivo (el "tacto") |
| El hardware es un cuello de botella (solo tú puedes probar) | **Fixtures grabados**: tú capturas una vez, yo itero mil veces sin la mesa |
| Contadores de error escritos y nunca leídos | Si un contador merece existir, merece salir en el HUD de Debug |
| Cada ronda toca producción | Fase 0 es instrumentación pura: cero riesgo de regresión |

Tres reglas concretas:

1. **Ningún arreglo de deriva sin un número antes y después.** Si no se puede
   medir, primero se hace medible.
2. **Nunca descartar datos de entrada en silencio.** Un `guard ... else
   { return }` sobre movimiento real es una fuga. Si hay que ignorar algo, se
   cuenta y se enseña.
3. **La posición nunca se obtiene integrando velocidad** si existe una medida
   directa.

---

## 7. Orden recomendado y decisiones que necesito de ti

| Fase | Qué | Riesgo | Estado |
|---|---|---|---|
| 0 | Instrumentación + medidor de deriva | Ninguno (no toca producto) | ✅ F.76/ADR-080 |
| 1 | Cerrar fugas (confianza, watchdog, ring, hostTime) | Bajo | ✅ F.77/ADR-081 (hostTime sin tocar, no hizo falta) |
| 2 | Posición absoluta como verdad | Medio | ✅ F.76/F.78/F.81/F.82 (ADR-080/082/085/086) |
| 3 | Servo del cabezal de audio | Bajo (el mecanismo ya existe, F.42/F.75) | ⏳ Pendiente solo el AJUSTE de `k` — necesita oído real en la Rane 72 |
| 4 | Fixtures + test de regresión | Ninguno | ⏳ Pendiente — **necesita que grabes el fixture con la Rane 72**; hay un test sintético de estrés como paliativo |

~~**Recomendación:** hacer **0 y 1 juntas** y medir.~~ Hecho — resultó que 0
y 1 no bastaron por sí solas (la Fase 2 hizo falta de verdad, el autor lo
confirmó con números reales: la deriva empeoraba durante el scratch
mientras los frames perdidos se quedaban planos).

**Pendiente de decidir:**

1. ¿Merece la pena la Fase 3 (servo de audio) ahora, o esperamos a probar
   F.81/F.82 en la Rane 72 primero para ver si hace falta?
2. Grabar el fixture de la Fase 4 en cuanto estés delante de la mesa.
3. ¿Te encaja grabar el fixture de audio de la fase 4 cuando tengas la mesa?
