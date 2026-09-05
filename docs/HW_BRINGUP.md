# HW_BRINGUP.md — puesta en marcha con hardware

> **El día que conectes la Rane 72 + platos + vinilo de timecode.**
>
> Este documento junta en un solo sitio, y en orden de dependencia, todo lo que
> hay que correr con el hardware delante: el comando exacto, el número que hay
> que leer, dónde se anota y la puerta de decisión de cada paso. Hasta ahora
> estaba repartido entre `TODO.md` (B1, B4.5, B5.5, B6.7), `docs/TIMECODE.md`
> §4, `docs/PLATFORM_SUPPORT.md` §7 y los tres `spike/*/README.md`.
>
> Nada de esto necesita cambios de código: todo lo que se puede adelantar sin
> hardware ya está hecho. Esto es ejecución + medición + anotar.
>
> Última revisión: 2026-09-02. Los tres spikes compilan a día de hoy
> (`spike/b1-latency`, `spike/b1-pilot-fader`, `spike/b4-audio-sandbox`).

---

## 0. Qué tiene que estar conectado

| Para | Necesitas |
|---|---|
| B1.1 / B1.2 / B1.4 / B4.5 | Rane 72 por USB, con el **retorno del máster** enrutado a una entrada del ordenador |
| B1.2 / B1.5 (latencia) | Un **loopback físico**: cable salida→entrada del interface, o el retorno USB del máster |
| B1.4 (piloto) | Salida del ordenador → entrada de línea de la mesa que gobierna el crossfader; retorno USB del máster → entrada del ordenador |
| B5.5 (timecode) | Un plato con **vinilo de timecode** (Serato CV02 / Traktor MK2 / MixVibes) sobre la Rane, y el deck enrutado a la entrada del ordenador |
| B1.5 fila "máquina de referencia" | Un segundo Mac (macOS 12+). Si solo hay el MacBook Pro 2015, esa fila se queda pendiente y se documenta como tal |

---

## 1. Preparación (una vez)

1. **Sample rate.** *Configuración de Audio MIDI* → la Rane 72 a **48 000 Hz**.
   Los spikes no lo fuerzan; si está a 44,1 kHz avisan pero miden igual.
2. **Permiso de micrófono.** Al abrir la entrada, macOS pide acceso al micrófono
   **para la Terminal** (la primera vez). Concédelo. Si lo deniegas:
   *Ajustes → Privacidad y seguridad → Micrófono → Terminal*.
   (La app empaquetada ya declara `NSMicrophoneUsageDescription` en su
   `Info.plist` vía `make app`.)
3. **Entorno de `tools/`** (solo para `measure_latency.py`):
   ```sh
   cd tools && python3 -m venv .venv && source .venv/bin/activate
   pip install -r requirements.txt
   ```
4. **Compila los spikes** (por si acaso; a 2026-09-02 compilan los tres):
   ```sh
   (cd spike/b1-latency    && sh build.sh)
   (cd spike/b1-pilot-fader && sh build.sh)
   ```

---

## 2. Secuencia (en este orden)

### Paso 1 — B1.7 · el driver enumera

```sh
spike/b1-latency/passthrough --list
```

**Lee:** que la **Rane Seventy-Two** aparezca con `in > 0` **y** `out > 0`
(dúplex) y su sample rate.
**Anota:** marca B1.7 en `TODO.md`.
**Puerta:** si no aparece o no es dúplex → problema de driver en Monterey; no se
sigue hasta resolverlo.

---

### Paso 2 — B1.1 + B1.6 · el stream aguanta 5 min a 64 frames

```sh
spike/b1-latency/passthrough --in-out "Seventy-Two" --frames 64 --seconds 300
# y, por separado, la variante adaptativa (B1.6, ADR-024):
spike/b1-latency/passthrough --in-out "Seventy-Two" --frames 64 --seconds 300 --adaptive
```

Escucha los 5 minutos: la entrada tiene que sonar en la salida **limpia**.
**Lee:** `overloads` (debe ser **0**), `render_err` (debe ser **0**),
`gap[min/max]` (~1,33 ms; un `max` disparado = el hilo se queda sin tiempo).
Al final imprime `PASS` / `FAIL` / `INCOMPLETO`; con `--adaptive`, además
`PASS` (aguantó a 64) vs `PASS CON RESERVA` (solo a 128).
**Anota:** rellena la fila en `docs/TIMECODE.md` §4.1 (dispositivo, buffer real,
overloads, duración, resultado). Marca B1.1 y B1.6 en `TODO.md`.
**Puerta:** cortes irreparables a 64 **y** a 128 → ADR con el plan B, antes de
seguir (es parte de B1.3).

---

### Paso 3 — B1.2 + B1.5 · round-trip por loopback

Con el cable de loopback puesto (salida→entrada, o retorno USB del máster):

```sh
cd tools && source .venv/bin/activate
python3 measure_latency.py --list                 # elegir device
python3 measure_latency.py --device "Seventy-Two" --fs 48000 --frames 64 --reps 20
```

**Lee:** la mediana del round-trip, el jitter (σ) y el **veredicto** (DENTRO /
FUERA de la puerta de 10 ms) que imprime el propio script, más la línea lista
para pegar.
**Anota:** rellena la fila del MacBook Pro 2015 en **`docs/TIMECODE.md` §4.2**
y en **`docs/PLATFORM_SUPPORT.md` §7** (son la misma tabla). Repite con
`--frames 128` para la fila de 128. Si hay un segundo Mac, repite allí para la
fila "máquina de referencia"; si no, anótala como *pendiente — máquina única*.
Marca B1.2 y B1.5.
**Puerta:** este número **es el número del proyecto** (`PLATFORM_SUPPORT.md`
§7). Si no se baja de 15 ms a 128 frames, se documenta como limitación conocida
y la calibración de la app lo dice.

---

### Paso 4 — B1.4 · el crossfader por MIDI (corrige ADR-021, ya hecho)

**Ya validado (2026-09-03), no hace falta repetirlo salvo que quieras más
confianza.** Se confirmó por CoreMIDI, aislado y en vivo, que el crossfader de
la Rane 72 manda **CC8 en canal MIDI 16** (15313/15317 mensajes limpios en 5
min): ver ADR-021 (corregida) y B1.4 en `TODO.md`.

Pendiente, no bloqueante — confirmar en el asistente de calibración cuando
exista (paso "Fader" del wizard, hoy stub, bloqueado por B4.2):
- Extremos exactos del barrido (¿0 y 127 limpios en los topes del recorrido?).
- Sentido (`midi.invert`) — con el contour en la posición de uso real.
- **Jitter** de la propia entrega MIDI: cronometra cortes rítmicos (a un
  metrónomo, como hacía `pilot_fader`) y mide la desviación típica de los
  intervalos vs el mismo criterio de **< 5 ms**. CoreMIDI entrega con
  `hostTime` de alta resolución, así que se espera que pase con holgura, pero
  no se ha medido formalmente — no hay todavía una herramienta para esto en
  el repo (a diferencia de `measure_latency.py` para B1.2). Si hace falta,
  se escribe entonces.

**Respaldo (tono piloto, ADR-021 original)** — solo si algún día una mesa NO
expone el crossfader por MIDI:
```sh
spike/b1-pilot-fader/pilot_fader --in-out "Seventy-Two" --selfcheck        # calibra umbrales
spike/b1-pilot-fader/pilot_fader --in-out "Seventy-Two" --seconds 60 --on -68 --off -80
```
Con el `--selfcheck` hecho, en la corrida de 60 s **abre y cierra el crossfader
al ritmo del metrónomo**. **Lee:** `--selfcheck` → `min` del tono (si < −70
dBFS el piloto no sobrevive: sube `--level-db` o revisa cableado). Corrida →
`flancos vistos` y la **desviación típica de los intervalos**. **Puerta:** σ
**< 5 ms** → PASA; si no, ADR con el plan C (fader MIDI externo barato en
paralelo) antes de construir nada encima. **Anota:** fila en
`docs/TIMECODE.md` §4.3 si se llega a usar.

---

### Paso 5 — B1.3 · DECISIÓN documentada

Con los números de los pasos 2–4 en la mano, una entrada nueva en
`docs/DECISIONS.md` (ADR): **seguir** si round-trip ≤ 10 ms (≤ 15 en el 2015 a
128) y σ del fader < 5 ms; si no, el plan B / C correspondiente **antes de
escribir nada más**. Marca B1.3. Bloque B1 cerrado → se pueden borrar los
`spike/b1-*`.

---

### Paso 6 — B5.5 · sellar `CXFTimecode` con vinilo real (HECHO 2026-09-04)

```sh
spike/b5-timecode/build.sh
spike/b5-timecode/tcprobe --list
spike/b5-timecode/tcprobe --in-out "Seventy-Two" --seconds 60 --def serato_2a --ch N
```

**El canal no era el que asumía el perfil.** `timecode.deck1.ch = 3,4` no
enganchaba, ni ningún otro de los 7 pares posibles (se barrieron todos:
1-2 hasta 13-14) — el medidor de la mesa sí se movía con el plato, así que la
señal llegaba pero no dábamos con el canal USB. Se resolvió preguntándole a la
propia Rane 72 el nombre de cada canal por CoreAudio
(`kAudioObjectPropertyElementName`, no hay flag para esto en `tcprobe`, es una
consulta CoreAudio aparte) — reportó `1-2 Analog 1` `3-4 Analog 2` `5-6 Mix`
`7-8 Deck 1` `9-10 Deck 2` `11-12 Session In` `13-14 Mic 1/2`. Contraintuitivo:
el canal literalmente etiquetado **"Deck 1" (7-8) no llevaba la señal real**
(un pico aislado de confianza, probablemente falso enganche); la señal real
estaba en **"Analog 1" (1-2)**, confirmado también en Ableton Live. Si esto le
pasa a otra mesa: `tcprobe --ch N` (nuevo) deja probar cualquier par sin
recompilar; no te fíes del nombre que reporta el driver, compara contra el
medidor físico de la mesa.

Con el canal correcto (`--ch 1` en la Rane 72):

- **Enganche / escala:** a 33⅓ estable, `vel` media ≈ **1.00** (a 45 rpm ≈ 1.35)
  → confirmado, media 0.9999.
- **Dirección / scratch:** al invertir el sentido, `vel` cambia de signo y `dir`
  pasa a `REV`. `--reverse` (hamster) invierte el signo → confirmado.
- **Dropout:** levanta la aguja → `conf` cae a ~0 y `vel` decae a 0 **sin
  colgarse** → confirmado (decae suave en ~1,5 s, `position` se congela).
- `drops` debe ser 0; `render_err` 0 → confirmado en las tres corridas.

Resultados completos en `docs/TIMECODE.md` §3. `profiles/rane-seventy-two.conf`
corregido. `make seal M=CXFTimecode` hecho, `README.md` del módulo y
`docs/MODULE_STATUS.md` → SEALED. B5.5 marcada en `TODO.md`.

---

### Paso 7 — B6.4 / B6.4b / B6.7 · sellar `XFCapture`

**MIDI, ya confirmado con el aparato real (2026-09-05):** `MidiMonitorConnector`
(CoreMIDI clásico, un solo cliente para toda la sesión, F.61) alimenta
`MidiFaderSource` en producción — no un `MidiFaderConnector` dedicado, que se
planeó al principio pero nunca llegó a instanciarse en la app y se borró como
código muerto. Con el aparato real: 15313/15317 mensajes CC8/canal16 limpios
en una captura aislada de 5 min (ADR-021 corregida), y F.61 confirmó que el
mismo `MidiMonitorConnector` reparte correctamente comandos discretos Y
crossfader en la práctica real. `profiles/rane-seventy-two.conf` ya declara
`method = midi`. El IOHIDManager (`HIDFaderConnector`) sigue **sin tests: solo
hace falta si una mesa que de verdad no exponga MIDI lo necesita** — no
bloquea sellar el método primario.

- **audio_return (respaldo):** `AudioReturnFaderSource` (B6.4b) queda como
  método de reserva para mesas que de verdad no expongan el crossfader por
  MIDI — no hace falta para la Rane 72, pero el código no se retira.
- **HID (respaldo 2, sin usar todavía):** lee el descriptor HID del aparato
  (`hidutil list` / `ioreg -p IOUSB`), rellena el bloque `hid.*` **comentado**
  de `profiles/rane-seventy-two.conf` y prueba `HIDFaderConnector` — solo si
  una mesa futura lo necesita de verdad.
- Pendiente, no bloqueante: confirmar en el asistente de calibración los
  extremos exactos del barrido (0/127 en los topes) y `midi.invert` — el
  asistente ya lo aprende con "Aprender MIDI del fader" (F.67), falta
  persistirlo para la práctica real (`DeviceCalibration`, XFPersistence).
- Smoke test de `TimecodeMotionSource` con el vinilo (solapa con el paso 6).

**Anota:** `verified = true` en `profiles/rane-seventy-two.conf` cuando los
canales de audio y el método estén confirmados. `make seal M=XFCapture`,
`README.md`, `MODULE_STATUS.md` → SEALED. Marca B6.4 / B6.4b / B6.7.

---

### Paso 8 — B4.2 + B4.5 + B4.6 · el callback RT definitivo y su puerta

`CXFAudioCore` ya tiene el `xf_engine` (núcleo testeable), el ring buffer SPSC
(B4.1), el player y el metrónomo. Falta:

- **B4.2:** el host CoreAudio definitivo del engine con el ring buffer y
  prioridad RT (`thread_policy_set` con `THREAD_TIME_CONSTRAINT_POLICY`) **y**
  unión al *workgroup* del dispositivo (obligatorio en Apple Silicon). El spike
  `spike/b4-audio-sandbox/` ya validó el reparto Swift(UI) + C(callback) +
  atómicas en la máquina de referencia; B4.2 es la versión de producción.
- **Verificación:** *Instruments → Audio System Trace*. Buscar **0 overloads**
  del hilo RT y **0 `malloc`/locks** dentro del callback en 5 min.
- **B4.5 (puerta):** round-trip plato→altavoz **≤ 10 ms** (≤ 15 en el 2015),
  **0 overloads en 5 min**, medido y anotado en `docs/TIMECODE.md`. Misma medida
  que B1.5 pero sobre el engine real, no el passthrough.

**Anota:** `make seal M=CXFAudioCore` cuando B4.2–B4.5 estén. Marca B4.2 / B4.5
/ B4.6.

---

## 3. Dónde va cada número

| Medida | Fichero / sección |
|---|---|
| Estabilidad passthrough 5 min | `docs/TIMECODE.md` §4.1 |
| Round-trip por loopback (2 máquinas × 2 buffers) | `docs/TIMECODE.md` §4.2 **y** `docs/PLATFORM_SUPPORT.md` §7 |
| σ del crossfader por piloto | `docs/TIMECODE.md` §4.3 |
| Decisión seguir / plan B / plan C | `docs/DECISIONS.md` (ADR nuevo, cierra B1.3) |
| Enganche / dirección / dropout del vinilo | `docs/TIMECODE.md` §3 |
| Puerta de latencia del engine real | `docs/TIMECODE.md` §4.2 (fila del engine) |
| Estado de módulos al sellar | `docs/MODULE_STATUS.md` + `README.md` de cada módulo |
| Marcar tareas hechas | `TODO.md` + `data/backlog.json` (`make status`) |

---

## 4. Resumen de puertas (go / no-go)

1. **B1.1** — 0 overloads 5 min a 64 (o 128 con `--adaptive`). No → plan B.
2. **B1.2 / B1.5** — round-trip ≤ 10 ms (≤ 15 en el 2015 a 128). No → limitación
   documentada + aviso en calibración.
3. **B1.4** — σ del fader < 5 ms. No → plan C (fader MIDI externo).
4. **B4.5** — engine real ≤ 10/15 ms, 0 overloads 5 min, 0 malloc/locks en
   Instruments. No → no se sella `CXFAudioCore`.

Cualquier "no" se documenta con un ADR **antes** de construir encima.
