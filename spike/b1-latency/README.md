# spike B1.1 — passthrough de CoreAudio a 64 frames

> **Prototipo DESECHABLE.** No entra en `Package.swift`, no es parte de la app.
> Se borra entero cuando el bloque B1 cierre. El motor de audio de verdad es el
> módulo `CXFAudioCore` y se escribe en B4 (con su ring buffer SPSC lock-free).

## Para qué es

Primera puerta de viabilidad del proyecto (`PLAN.md`, Hito A). Responde a una
pregunta y solo una:

> ¿Puede tu hardware hacer entrada → salida de audio con un buffer de **64 frames
> a 48 kHz** durante **5 minutos sin un solo corte**?

Si la respuesta es no y no se puede arreglar subiendo el buffer, el plan se para
y se abre un ADR con el plan B **antes de escribir más código** (tarea B1.3).

## Cómo se usa

```sh
./build.sh                      # compila (universal x86_64 + arm64)
./passthrough --list            # ver los dispositivos y sus canales

# la prueba oficial de B1.1, con tu mesa de batalla:
./passthrough --in-out "Rane" --frames 64 --seconds 300
```

- `--in-out <substr>` elige el dispositivo (el mismo para entrada y salida) cuyo
  nombre contenga esa cadena. Tiene que ser **dúplex** (`in>0` y `out>0` en
  `--list`). Tu Rane 72 lo es.
- Sin `--in-out` usa la salida por defecto del sistema; como el altavoz interno
  no tiene entrada, verás `render_err` subiendo. Eso es normal sin `--in-out`.
- `--adaptive` (tarea **B1.6**, ADR-024): si aparecen ≥3 overloads, sube el
  buffer del dispositivo a 128 frames al vuelo (con un microcorte) y sigue. El
  resumen distingue `PASS` (aguantó a 64) de `PASS CON RESERVA` (solo a 128).
- `Ctrl-C` para parar antes de tiempo.

> El otro spike de B1, `spike/b1-pilot-fader/`, valida la captura del crossfader
> por tono piloto (B1.4 / ADR-021).

**Antes de la prueba oficial:** en *Configuración de Audio MIDI* pon el
dispositivo a **48 000 Hz**. El spike no fuerza el sample rate; si está a 44,1
kHz te lo avisa pero mide igual.

**Permiso de micrófono:** al abrir la entrada, macOS pedirá acceso al micrófono
**para la Terminal** (la primera vez). Hay que concederlo o no habrá señal de
entrada. Si lo deniegas: *Ajustes → Privacidad y seguridad → Micrófono → Terminal*.

## Qué mirar

| Señal | Qué significa |
|---|---|
| `overloads` | Tiene que quedarse en **0**. Cada overload es un corte que se oye. |
| `render_err` | Tiene que quedarse en **0** (con `--in-out`). Si sube, la entrada no llega. |
| `gap[min/max]` | Tiempo real entre callbacks. A 64@48k lo esperado es ~1,33 ms. Un `max` disparado = el hilo se está quedando sin tiempo. |
| el oído | Que **suene** la entrada en la salida, limpio, sin clicks, los 5 minutos enteros. |

Al terminar imprime `PASS` / `FAIL` / `INCOMPLETO`.

## Después de correrlo

1. Anota el resultado (dispositivo, buffer real, overloads, duración) en
   `docs/TIMECODE.md` §4.
2. La medida de latencia round-trip por loopback es la tarea siguiente (**B1.2**),
   con `tools/measure_latency.py`. Este spike solo prueba que el stream aguanta;
   no mide cuántos ms tarda el ida y vuelta.
3. Si hubo cortes irreparables a 64 y a 128 frames → ADR con el plan B (B1.3).

## Notas de implementación

- Una sola `AudioUnit` HAL (`kAudioUnitSubType_HALOutput`) con entrada y salida
  habilitadas sobre **el mismo dispositivo**. Al compartir reloj, el passthrough
  se hace dentro del propio callback (`AudioUnitRender` del bus de entrada +
  `memcpy` a la salida) **sin ring buffer**. El ring buffer es necesario cuando
  entrada y salida son dispositivos distintos; eso es B4, no esto.
- El callback ya respeta las reglas del hilo de audio (`CLAUDE.md` §7): sin
  `malloc`, sin locks, sin `printf`. Se comunica con el hilo `main` solo por
  atómicas (`stdatomic.h`). El spike también sirve para coger ese hábito.
- Formato cliente: `Float32` no entrelazado, `min(canales_in, canales_out)`.
