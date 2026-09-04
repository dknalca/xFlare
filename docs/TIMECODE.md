# Timecode — decoder de vinilo (CXFTimecode)

> Notas del decoder. xwax vendorizado + el wrapper propio `xf_timecode`.
> Estado: v0.1 (andamiaje B0.1 + vendorizado B5.1).

## 1. xwax vendorizado

| | |
|---|---|
| Versión | **xwax 1.10** (mayo 2026), descargada de https://xwax.org/releases/xwax-1.10.tar.gz |
| Licencia | **GPL-3.0** (xwax se relicenció de GPLv2 a GPLv3 en la 1.8 — ver ADR-030) |
| Ubicación | `Sources/CXFTimecode/vendor/xwax/` |
| Regla | **INTACTO.** No se modifica ni una línea. Si hace falta adaptar algo, va en `xf_timecode.c` y se documenta aquí. |

Ficheros vendorizados (los mínimos para compilar `timecoder.c` y `lut.c`):

```
timecoder.c   timecoder.h    <- el decoder
lut.c         lut.h          <- lookup table de la señal
debug.h                      <- macros de debug que usa timecoder.c
pitch.h                      <- filtro de pitch (header-only) que incluye timecoder.h
```

Sus cabeceras conservan el copyright original de Mark Hills y el aviso GPLv3. **No
se les añade la línea `SPDX` propia de xFlare.**

## 2. Compilación

`Package.swift` añade `vendor/xwax` al `headerSearchPath` del target `CXFTimecode`.
SwiftPM compila `vendor/xwax/timecoder.c` y `vendor/xwax/lut.c` automáticamente
junto con `xf_timecode.c`.

- **Universal:** compila en `x86_64` **y** `arm64`. xwax 1.10 **no** usa
  intrínsecos SSE (`xmmintrin.h`, `__m128`, `_mm_*`) ni flags `-msse` → no hay
  nada que condicionar por arquitectura. Cierra la tarea B0.7.
- **Warnings conocidos (de xwax, no se tocan):**
  - `timecoder.c:438` y `:439` — `implicit conversion loses integer precision:
    'long long' to 'int' [-Wshorten-64-to-32]`. Aparecen solo en la build de
    release (que activa ese warning). Inofensivos; son estilo del upstream.

## 3. Wrapper `xf_timecode`

El wrapper expone el decoder en **modo relativo** (ADR-004): solo velocidad y
dirección, sin posición absoluta.

**Estado (B5.2–B5.4, hecho):** `xf_timecoder` opaco sobre `struct timecoder` de
xwax. `create(def_name, sample_rate)` / `submit(pcm16 estéreo)` / `velocity()`
(con signo, del filtro α-β `pitch_current`) / `position()` (relativa) /
`confidence()` / `forwards()`. Header público **sin** `timecoder.h`
(module-safe, como `xf_ring.h`). Hamster/reverse por `set_reversed(true)`
(intercambia canales antes de decodificar). `confidence` = RMS de entrada
recortado, o 1.0 si xwax engancha el bitstream. 7 tests con **señal de
cuadratura sintética** (validan el modo relativo contra el contrato de xwax).

**Hecho (B5.5, 2026-09-04, hardware real):** validado con la Rane 72 + vinilo
Serato CV02 real (plato girando de verdad, no señal sintética), usando
`spike/b5-timecode/tcprobe --def serato_2a`. Antes hubo que encontrar el canal
correcto: el perfil asumía `timecode.deck1.ch = 3,4` sin verificar, y ni ese
par ni ningún otro de los 7 posibles (barridos 1-2 hasta 13-14) enganchaban —
el medidor de la propia mesa sí se movía, así que la señal llegaba a la Rane
pero no dábamos con el canal USB correcto. Se resolvió consultando los
**nombres de canal que la propia Rane 72 reporta por CoreAudio**
(`kAudioObjectPropertyElementName`): `1-2 Analog 1` `3-4 Analog 2` `5-6 Mix`
`7-8 Deck 1` `9-10 Deck 2` `11-12 Session In` `13-14 Mic 1/Mic 2`. Contra toda
lógica, el canal etiquetado **"Deck 1" (7-8) NO lleva la señal real** del
deck 1 (solo dio un pico aislado de confianza, probablemente un falso
enganche); la señal real está en **"Analog 1" (canales 1-2)**, confirmado
también de forma independiente abriendo el dispositivo en Ableton Live. Con el
canal correcto:
- **Enganche + escala:** 60 s a 33⅓ estable → `vel` media **0.9999**
  (min 0.9967, max 1.0033), `conf` sostenida 0.92–1.00 todo el minuto,
  `engancho bitstream: SI`.
- **Dirección:** al scratchear, `vel` cambia de signo en cada pasada
  (hasta ±1.8-2.0 en movimientos rápidos) y `dir` pasa a `REV` en
  sincronía, sin perder confianza (se mantuvo en 1.00 durante todo el
  scratch).
- **Dropout:** al levantar la aguja, `conf` decae suavemente
  1.00 → 0.61 → 0.26 → 0.11 → 0.05 → 0.02 → 0.01 → 0.00 en ~1,5 s y `vel`
  cae a 0; `position` se queda congelada (no deriva ni se corrompe)
  **sin colgarse**. No se capturó el re-enganche al bajar la aguja de nuevo
  dentro de la ventana de la prueba (se acabó el tiempo), pero el
  comportamiento hasta ahí es exactamente el esperado.
- `drops` = 0, `render_err` = 0 en las tres corridas (60 s + 60 s + 30 s).

**Corrección de perfil:** `profiles/rane-seventy-two.conf` →
`timecode.deck1.ch = 1,2` (confirmado). `deck2.ch` sigue **sin verificar**
(no se probó el segundo plato), pero por el mismo patrón ("Analog N" ≠ la
etiqueta "Deck N") la hipótesis de partida para cuando se pruebe es
`3,4` ("Analog 2"), no `5,6` como decía antes.

Módulo **SEALED** (`make seal M=CXFTimecode`).

## 4. Latencia y estabilidad del stream (bloque B1)

> El **procedimiento completo con hardware** (qué correr, en qué orden, qué
> número leer y dónde va) está en `docs/HW_BRINGUP.md`. Aquí solo viven las
> tablas de resultados.

### 4.1 B1.1 — passthrough a 64 frames (estabilidad, no latencia)

Prototipo desechable en `spike/b1-latency/` (fuera de `Package.swift`). Prueba
que el stream entrada→salida aguanta 5 min a 64 frames / 48 kHz **sin overloads**.
No mide milisegundos de ida y vuelta; eso es B1.2.

| Máquina | Dispositivo | Buffer real | Duración | Overloads | render_err | Resultado |
|---|---|---|---|---|---|---|
| MacBook Pro 2015 (Monterey) | _(pendiente: correr con la Rane 72)_ | | | | | |
| Máquina de referencia | _(pendiente)_ | | | | | |

> Estado 2026-08-31: spike escrito y compilado (universal). En la máquina de
> desarrollo no hay dispositivo dúplex, así que la corrida real la hace el autor
> con la mesa. Con `Built-in Output` (sin entrada) el stream sí sostiene 64
> frames a 44,1 kHz con 0 overloads y gap 1,2–1,7 ms; falta la prueba dúplex de
> verdad. El flag `--adaptive` (subida 64→128 al detectar overloads, ADR-024 /
> B1.6) también está en ese spike, pendiente de corrida real en el Intel de 2015.
>
> Actualización 2026-09-03 (ADR-061): el coste de CPU del hilo RT bajó — la
> convolución de `xf_player_render` va en `float` con camino rápido sin ramas y
> se salta entera cuando el plato está parado. La EQ del sample (`xf_eq`) solo
> cuesta cuando no está en plano. Al correr la medición de overloads en hardware,
> el margen debería ser mayor que el estimado antes de este cambio.

### 4.2 B1.2 / B1.5 / B4.5 — round-trip por loopback

Herramienta: `tools/measure_latency.py` (deps en `tools/requirements.txt`). Manda
un chirp por la salida, graba la entrada a la vez, saca el desfase por correlación
cruzada. Necesita un loopback físico (cable salida→entrada o el retorno USB del
máster). Rellenar con los números de las dos máquinas — misma tabla que
`docs/PLATFORM_SUPPORT.md` §7:

| Máquina | Buffer / sr | Round-trip (mediana) | Jitter (σ) | Veredicto |
|---|---|---|---|---|
| MacBook Pro 2015 (Monterey) | _(pendiente)_ | | | |
| Máquina de referencia | _(pendiente)_ | | | |

### 4.3 B1.4 — detección del crossfader por tono piloto (ADR-021)

Prototipo desechable en `spike/b1-pilot-fader/`. Piloto de 19,5 kHz a −40 dBFS en
la salida, Goertzel + histéresis sobre el retorno del máster. El número que
importa es la **desviación típica de los intervalos entre flancos** al abrir y
cerrar a ritmo de metrónomo: debe quedar **< 5 ms**. Si no → ADR con el plan C
(fader MIDI externo).

| Máquina + mesa | Piloto (dBFS en retorno) | Flancos | σ intervalos | Veredicto |
|---|---|---|---|---|
| MacBook Pro 2015 + Rane 72 | _(pendiente)_ | | | |
