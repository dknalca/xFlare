# spike B4 — banco de pruebas del motor de audio

> **Prototipo DESECHABLE.** No entra en `Package.swift`. Sirve para *sentir* el
> motor antes de tenerlo en serio (`CXFAudioCore`, bloque B4). Se borra cuando B4
> esté hecho.

Simula el timecode con el **trackpad** y el corte del **crossfader** con una
tecla, y suena: una instrumental de fondo + un sample scratcheado por el "plato".

> **Estado (2026-09-01):** probado en la máquina de referencia (MacBook Pro 2015,
> macOS 12.7). Suena, el trackpad y la tecla responden en tiempo real, se siente
> razonable. Valida el reparto Swift (UI) + C (callback RT) + atómicas de puente
> antes de escribir `CXFAudioCore` en serio.

## Uso

```sh
spike/b4-audio-sandbox/build.sh
spike/b4-audio-sandbox/sandbox            # ejecútalo desde la raíz del repo
```

Abre una ventana:

| Control | Efecto |
|---|---|
| **Trackpad** (scroll 2 dedos / arrastrar) | mueve el plato. Adelante → el sample avanza; atrás → suena al revés. Al soltar, **frena** (como con la mano encima del disco). |
| **Espacio** (mantenido) | corta el crossfader mientras lo pulsas |
| **R** | rebobina el sample de scratch |
| **Esc** / cerrar ventana | salir |

El HUD muestra velocidad del plato, posición en el sample, estado del fader y un
meter de salida.

Si no encuentra el audio, pásale las rutas:
```sh
spike/b4-audio-sandbox/sandbox "ruta/scratch.mp3" "ruta/instrumental.mp3"
```

## Qué mirar

- Que el scratch **responde en tiempo real** al trackpad, sin lag perceptible ni
  clicks al cambiar de dirección.
- Que el **corte del fader** (espacio) es limpio, sin pop (hay una rampa de ~2 ms).
- Que la instrumental sigue sonando de fondo mientras scratcheas.
- Si notas el trackpad al revés, cambia el signo en `sandbox.swift`
  (`scrollWheel`). Sensibilidad y fricción: `Platter` en el mismo fichero.

## Qué NO es

- No hay ring buffer, ni timecode real, ni prioridad de hilo RT explícita, ni
  workgroup de audio. La resamplificación es **lineal** (sin antialiasing serio;
  a velocidades altas se oirá aliasing).
- El callback **sí** respeta las reglas de `CLAUDE.md` §7 (C puro, sin
  malloc/locks/printf, atómicas para hablar con la UI) — es el reparto real del
  proyecto: Swift arriba, C en el hilo de audio.

## Audio

Usa los mp3 de `Audio/` (los pusiste tú). **Tienen copyright de terceros**
(`ahh-fresh`, un tema comercial): `Audio/` está en `.gitignore` y esos samples
**no pueden ir en la app** (CLAUDE.md §12). El banco de fábrica de xFlare será de
material libre de derechos (Hito F).
