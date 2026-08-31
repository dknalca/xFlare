# spike B1.4 — detección del crossfader por tono piloto

> **Prototipo DESECHABLE.** No entra en `Package.swift`. Se borra cuando B1
> cierre. La implementación de verdad vive luego en `XFCapture` (tarea B6.4b,
> `AudioReturnFaderSource`).

## Para qué es

Validar el método `audio_return` de **ADR-021**. El crossfader MAG FOUR de la
Rane 72 (y el de la DJM-S11) **no expone su posición por MIDI** a terceros. Sin
esa posición, xFlare no puede puntuar clicks, que es el núcleo del producto.

El plan de ADR-021: xFlare mezcla en su salida un **tono piloto inaudible**
(~19,5 kHz a −40 dBFS), captura el **retorno del máster** de la mesa por USB y
mira si el tono llega. Tono presente = fader abierto. Ausente = cerrado.

> **Pregunta que responde (B1.4):** ¿se detecta abrir/cerrar el crossfader con
> **jitter < 5 ms**? Si no → ADR con el plan C (un fader MIDI externo barato en
> paralelo) **antes de seguir**.

## Conexión

```
  ordenador  --salida-->  entrada de línea de la mesa (al canal que gobierna el XF)
  mesa  --retorno USB del máster-->  entrada del ordenador
```

Con `--selfcheck` basta un cable salida→entrada del propio interface, sin mesa:
sirve para calibrar los umbrales y confirmar que el piloto sobrevive el viaje.

## Uso

```sh
./build.sh
./pilot_fader --list
./pilot_fader --in-out "Rane" --selfcheck          # 3 s, sugiere --on / --off
./pilot_fader --in-out "Rane" --seconds 60 --on -68 --off -80
```

Durante la detección: abre y cierra el crossfader **a ritmo del metrónomo**. El
spike imprime cada flanco (`ABRE` / `cierra`) con el tiempo transcurrido desde el
anterior, y al final la **desviación típica de los intervalos**. Para pasar B1.4,
esa desviación debe quedar por debajo de 5 ms.

Parámetros finos: `--freq`, `--level-db`, `--hop` (muestras por análisis, define
la resolución temporal: 64 → 1,33 ms), `--on` / `--off` (umbrales de histéresis
en dBFS).

## Qué mirar

| Señal | Qué significa |
|---|---|
| `--selfcheck` → `min` del tono | Si es < −70 dBFS el piloto no sobrevive el viaje: sube `--level-db` o revisa el cableado. |
| `flancos vistos` | Debe coincidir con las veces que moviste el fader. De más = rebotes (sube la separación `--on`/`--off`). De menos = umbral mal puesto. |
| `dispersión (desv. típica)` | El número de B1.4. < 5 ms → PASA. Si no → plan C. |
| resolución por hop | Suelo físico del jitter medible. Con `--hop 64` es 1,33 ms. |

## Notas de implementación

- Una `AudioUnit` HAL dúplex sobre el mismo dispositivo (como el spike B1.1). El
  callback **genera** el piloto en la salida (desde una tabla de 1 s precalculada
  en el arranque; a 48 k/19,5 k son 19500 ciclos exactos → sin junta) y
  **analiza** la entrada.
- Detección: **Goertzel** de un solo bin a `--freq` sobre cada hop de `--hop`
  muestras → nivel en dBFS. Histéresis de dos umbrales (`--on` / `--off`) para no
  rebotar. Cada flanco se encola con su instante en un **ring SPSC** (productor
  RT, consumidor `main`); el hilo `main` lo drena e imprime.
- El callback respeta `CLAUDE.md` §7: aritmética acotada, sin `malloc`/locks/
  `printf`, comunicación por atómicas y ring lock-free. `sin`/`cos`/`log10` son
  `libm` (no syscalls); en producción se sustituyen por una LUT.
