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

## 3. Wrapper `xf_timecode` (pendiente, bloque B5.2)

El wrapper expone el decoder en **modo relativo** (ADR-004): solo velocidad y
dirección, sin posición absoluta. Aquí se documentará su API y cualquier
adaptación necesaria sobre el timecoder de xwax (que consume mono, mientras que la
captura llega en estéreo, etc.).

## 4. Latencia y estabilidad del stream (bloque B1)

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
