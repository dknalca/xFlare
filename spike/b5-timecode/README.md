# spike B5.5 — sonda de timecode con vinilo real

> **Prototipo DESECHABLE.** No entra en `Package.swift`. Se borra cuando B5
> cierre. La captura de verdad es `TimecodeMotionSource` en `XFCapture` (B6.3),
> que ya existe; esto solo evita escribir un banco de pruebas el día que llegue
> el vinilo.

## Para qué es

Cerrar **B5.5** — sellar `CXFTimecode`. El wrapper `xf_timecoder` (B5.2–B5.4) ya
está y pasa sus tests con **señal de cuadratura sintética**. Falta pasarle un
**vinilo de timecode real** y ver que engancha, que la escala de velocidad es
correcta y que se recupera de un dropout.

El spike abre la **entrada** de audio de la mesa (el deck al que llega el vinilo
de control), se la pasa a `xf_timecoder` y enseña en vivo lo que decodifica.

## Conexión

```
  plato con vinilo de timecode  --->  deck de la Rane 72
  Rane 72  --entrada USB (el deck enrutado)-->  ordenador
```

## Uso

```sh
./build.sh
./tcprobe --list                                   # elegir el dispositivo de entrada
./tcprobe --in-out "Seventy-Two" --seconds 60
./tcprobe --in-out "Seventy-Two" --def serato_2a --reverse
```

- `--def` — definición de timecode: `serato_2a` (por defecto), `serato_cd`,
  `traktor_a`, `mixvibes_v2`… (las que trae xwax). Usa la del vinilo que tengas.
- `--reverse` — hamster: invierte el sentido.
- `--hz N` — líneas por segundo en pantalla (10 por defecto).
- `--ch N` — primer canal de ENTRADA a leer (1-based; lee N y N+1 en estéreo).
  Por defecto 1 (canales 1-2). La Rane 72 tiene 14 canales de entrada (varios
  decks + retornos) y `profiles/rane-seventy-two.conf` declara el par del
  deck 1 **sin verificar** (`timecode.deck1.ch = 3,4`, una suposición). Si con
  `--ch 1` no engancha, prueba `--ch 3`, `--ch 5`, etc. hasta encontrar el par
  correcto, y anota el que funcione en el perfil.

**Permiso de micrófono:** la primera vez macOS lo pide **para la Terminal**. Si
no lo concedes, `callbacks` se queda en 0 y el resumen te lo dice.

## Qué mirar

| Prueba | Esperado |
|---|---|
| Plato a **33⅓** estable | `vel` media ≈ **1.00** (`~33 rpm`) |
| Plato a **45** | `vel` ≈ **1.35** |
| Invertir el sentido (scratch hacia atrás) | `vel` cambia de signo, `dir` pasa a `REV` |
| `--reverse` (hamster) | el signo se invierte respecto a la corrida normal |
| **Levantar la aguja** | `conf` → ~0 y `vel` → 0 **sin colgarse**; al bajarla, re-engancha |
| `drops` | **0**. Si sube, el bucle de `main` va lento: baja `--hz`. |
| `engancho bitstream` en el resumen | `SI` con señal limpia de un vinilo de verdad (con ruido/sintético suele quedarse en "solo por RMS") |

## Después de correrlo

1. Anota enganche / escala / dirección / dropout en `docs/TIMECODE.md` §3.
2. `make seal M=CXFTimecode`, escribe/actualiza `Sources/CXFTimecode/README.md`,
   pon `docs/MODULE_STATUS.md` → `CXFTimecode` **SEALED**.
3. Marca **B5.5** en `TODO.md` y `data/backlog.json`.

Procedimiento completo (con los demás pasos de hardware) en
`docs/HW_BRINGUP.md`.

## Notas de implementación

- Una `AudioUnit` HAL **solo entrada** (`EnableIO` input elem 1, output elem 0
  deshabilitado) sobre el dispositivo elegido. Mismo patrón que `spike/b1-latency`.
- El callback (hilo RT, `CLAUDE.md` §7) hace `AudioUnitRender`, convierte el
  float `[-1,1]` no entrelazado a **int16 interleaved** y lo mete en un **ring
  SPSC lock-free** (int16, capacidad potencia de 2). Sin `malloc`/locks/`printf`.
- `main` drena el ring, llama a `xf_timecoder_submit` (NO RT) e imprime. La
  conversión y el submit fuera del hilo de audio, como en la app real.
- `build.sh` enlaza `Sources/CXFTimecode/xf_timecode.c` + el xwax vendorizado
  (`timecoder.c`, `lut.c`) **directamente, sin tocarlos**. `-Wall -Wextra` sin
  `-Werror` por los `-Wshorten-64-to-32` conocidos de xwax (`docs/TIMECODE.md` §2).
- Universal `x86_64 + arm64` (ADR-028), aunque no se distribuye.
