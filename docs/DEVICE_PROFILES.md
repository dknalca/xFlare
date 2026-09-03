# Perfiles de dispositivo (`.conf`)

> Un fichero por modelo de mesa. La comunidad los aporta, la app los trae de fabrica.
> Estado: v0.3. Modulo responsable: `XFProfiles`.

## 1. El problema real (leelo antes que nada)

Hay un hallazgo que condiciona todo este sistema:

> **El crossfader de una mesa de battle probablemente NO emite MIDI.**
> En la Rane Seventy-Two (MK1, el hardware de referencia) el MAG FOUR es un
> componente de audio por hardware, cableado a la ruta de senal. El mapeo MIDI de
> la mesa esta pensado para pads y para Serato, no para exponer la posicion del
> crossfader a terceros.

Esto no es un detalle de configuracion: es **el riesgo tecnico numero dos del
proyecto** despues de la latencia. Y es exactamente por eso que el perfil de
dispositivo no puede ser "una lista de numeros CC". Tiene que declarar, para cada
mesa, **por que via se captura cada cosa**.

### Los tres metodos de captura del crossfader

| Metodo | Como | Cuando |
|---|---|---|
| `midi` | La mesa emite CC con la posicion | Lo ideal. Controladores y algunas mesas |
| `audio_return` | Se captura el master de la mesa por USB y se deduce el corte | Mesas de battle con fader hardware |
| `hid` | Protocolo propietario por USB | Ultimo recurso, requiere ingenieria inversa |

**`audio_return` con tono piloto** es la apuesta para la Rane 72 y hay que validarla
en el bloque B1: xFlare mezcla en su salida un tono inaudible (por ejemplo 19,5 kHz
a -40 dBFS), captura el retorno del master de la mesa por USB, y mide la presencia
de ese tono. Si el tono desaparece, el fader esta cerrado. Ventajas: funciona con
cualquier mesa que tenga retorno USB, y no depende de que el fabricante quiera.
Inconveniente: anade la latencia del bucle, que se mide en calibracion y se resta.
Es un **desfase constante y conocido**, no ruido — y para puntuar por compas eso es
perfectamente asumible.

**Ninguno de los valores concretos de los perfiles que se entregan esta verificado
contra hardware real.** Todos van con `verified = false`. Ver seccion 7.

## 2. Formato

INI plano, sin dependencias externas (ADR-019). Parseable con 150 lineas de Swift,
editable por un DJ sin saber programar, y con diffs legibles en un pull request —
que es justo lo que necesitas si quieres que la gente aporte.

```ini
[profile]
id       = rane-seventy-two
name     = Rane Seventy-Two
vendor   = Rane
schema   = 1
revision = 1
author   = tu-nombre
verified = false

[match]
midi.port    = *Seventy-Two*
audio.device = *Seventy-Two*

[audio]
samplerate        = 48000
timecode.deck1.ch = 3,4
timecode.deck2.ch = 5,6
output.main.ch    = 1,2
return.ch         = 7,8

[crossfader]
method          = audio_return
pilot.frequency = 19500
pilot.level_db  = -40
cut_in.left     = 0.05
cut_in.right    = 0.95
hysteresis      = 0.03
reverse_default = true
```

## 3. Claves

### `[profile]`
| Clave | Tipo | Obligatoria | Descripcion |
|---|---|---|---|
| `id` | slug | si | Identificador unico, minusculas y guiones |
| `name` | texto | si | Nombre visible |
| `vendor` | texto | si | Fabricante |
| `schema` | entero | si | Version del formato. Hoy `1` |
| `revision` | entero | si | Version de este perfil. Subir al editarlo |
| `author` | texto | no | Quien lo aporto |
| `verified` | bool | si | `true` solo si se ha probado con el aparato |
| `extends` | id | no | Hereda de otro perfil |
| `notes` | texto | no | Una linea |

### `[match]` — autodeteccion
`midi.port`, `audio.device` (admiten `*` como comodin), `usb.vid`, `usb.pid`.

### `[audio]`
`samplerate`, `timecode.deckN.ch`, `output.main.ch`, `return.ch`, `buffer.frames`.

### `[crossfader]`
| Clave | Valores | Notas |
|---|---|---|
| `method` | `midi` `audio_return` `hid` `none` | |
| `midi.channel` `midi.cc` `midi.min` `midi.max` `midi.invert` | | si `method = midi` |
| `pilot.frequency` `pilot.level_db` | Hz, dBFS | si `method = audio_return` |
| `hid.vendor_id` `hid.product_id` | hex o decimal | si `method = hid` (para casar el dispositivo) |
| `hid.usage_page` `hid.usage` | hex | opcional, afina el emparejado IOHID |
| `hid.report_id` | int | 0 si el dispositivo no usa report IDs |
| `hid.byte_offset` | int | posición del valor del fader en los **datos** del report (sin el byte de report ID) |
| `hid.byte_length` | `1` o `2` | 8 o 16 bits |
| `hid.big_endian` | bool | orden de bytes si `byte_length = 2` (por defecto `false`) |
| `hid.min` `hid.max` | int | rango del valor crudo → se normaliza a 0..1 |
| `hid.invert` | bool | invierte la posición |
| `cut_in.left` `cut_in.right` | 0..1 | Valor **por defecto**, se recalibra por usuario |
| `hysteresis` | 0..1 | Anti-rebote |
| `reverse_default` | bool | Hamster de fabrica |

> **`method = hid`** es la ruta de respaldo de ADR-021: si la mesa (Rane 72,
> DJM-S11) no expone el crossfader por MIDI, muchas hablan HID con Serato. Los
> valores `hid.*` salen de leer el descriptor HID del aparato (asistente de §8, o
> `hidutil`/`ioreg`). La lectura la implementa `XFCapture.HIDFaderSource`.

### `[linefader.deckN]`, `[pads]`
Misma logica. Los controles se escriben `tipo:canal:numero`, por ejemplo
`cc:1:24` o `note:1:0x30`.

### `[transport]` — comandos de practica por MIDI

Asigna una nota o un CC a cada comando de la sesion de practica (los mismos que
el teclado). Formato del valor: `tipo:canal:numero`, con `tipo` = `note` | `cc`,
`canal` 1-16 (o `0` = cualquiera) y `numero` 0-127 (acepta hex, `0x30`).

| Clave | Comando | Disparo |
|---|---|---|
| `command.cue` | Cue: el sample vuelve al inicio | Note On, o CC ≥ 64 |
| `command.restart_base` | Reinicia la instrumental desde el "1" | Note On, o CC ≥ 64 |
| `command.freeze` | Congela / descongela | Note On, o CC ≥ 64 |
| `command.record` | Arranca / para la grabacion de linea | Note On, o CC ≥ 64 |
| `command.bpm_up` | BPM +1 | Note On, o CC ≥ 64 |
| `command.bpm_down` | BPM −1 | Note On, o CC ≥ 64 |
| `command.fader` | **Momentaneo**: pulsado = crossfader cerrado | Note On/Off, o CC (≥ 64 cerrado) |
| `command.metronome` | Toggle del metronomo | Note On, o CC ≥ 64 |
| `command.call_response` | Toggle de "Repite conmigo" | Note On, o CC ≥ 64 |

Todos son disparos discretos salvo `command.fader`, que sigue el estado del
control (nota mantenida / CC continuo). El usuario puede pisar cualquiera de
estas asignaciones desde Ajustes → *MIDI · comandos* sin tocar el `.conf`: con
**MIDI Learn** (selecciona el comando, pulsa "Aprender MIDI", mueve el control)
o escribiendo la nota/CC a mano.

### `[quirks]`
Claves relevantes para arquitectura, ademas de las de la propia mesa:

| Clave | Significado |
|---|---|
| `arm64_driver_unknown` | El driver USB no se ha verificado en Apple Silicon |
| `arm64_driver_missing` | Confirmado: el fabricante no da driver arm64 |

Un kext Intel **no carga** en Apple Silicon y Rosetta no traduce drivers, asi que un
perfil puede funcionar en Intel y no en un Mac M sin culpa de xFlare.

Rarezas conocidas. Claves libres booleanas mas un `text` de una linea. Esto es oro
para el siguiente que compre esa mesa.

## 4. Herencia

```ini
[profile]
id      = rane-72-casa
extends = rane-seventy-two
[crossfader]
cut_in.left = 0.08
```

Solo escribes lo que cambia. Evita que cada usuario mantenga una copia entera que
se queda obsoleta cuando se corrige el perfil oficial.

## 5. Orden de carga

1. Perfiles de fabrica (dentro del bundle, solo lectura)
2. `~/Library/Application Support/xFlare/profiles/*.conf`
3. El perfil activo elegido en Ajustes
4. **Calibracion medida del usuario** (en la base de datos, no en el `.conf`)

## 6. Perfil vs calibracion — separacion importante

El `.conf` describe **el modelo de mesa**: que canales, que metodo, que CC.
La calibracion describe **tu unidad concreta y tu mano**: tu cut-in real, tu
latencia medida, tu punto cero. Eso vive en `XFPersistence`, por usuario y
dispositivo, y **nunca** se escribe en el `.conf`.

Si se mezclan, la gente acaba compartiendo perfiles con su calibracion personal
dentro y el sistema se envenena. Es el error clasico de este tipo de sistemas.

## 7. La insignia `verified`

- `verified = true` → probado contra el aparato fisico por una persona identificable.
- `verified = false` → estructura correcta, valores por confirmar.

La UI lo muestra siempre: **"Perfil sin verificar — puede que algun control no
responda"**, con un boton para completarlo con el asistente. Sin esto, el sistema
comunitario se llena de perfiles a medias y nadie se fia de ninguno.

## 8. Asistente de aprendizaje MIDI/HID

Pantalla `Ajustes → Mi mesa → Crear perfil`. Guiado, control a control:

1. Elegir punto de partida: perfil existente para heredar, o desde cero.
2. **Escucha**: la app muestra en crudo todo lo que llega por MIDI y HID.
   Ya solo con esto el usuario ve si su crossfader emite algo o no.
3. **Aprender**: "mueve el crossfader de izquierda a derecha, despacio". Captura
   canal, numero, rango, direccion y resolucion. Si no llega nada en 5 segundos,
   propone cambiar a `audio_return` y lo explica.
4. Repetir para cada control que quiera mapear. Todos son opcionales menos el
   crossfader.
5. **Probar**: barras en vivo para confirmar que responde.
6. **Guardar** como `.conf` en la carpeta del usuario, con `verified = true` local.
7. **Aportar**: boton que abre el fichero y las instrucciones del pull request.
   Sin subida automatica ni telemetria.

## 9. Aportar un perfil

1. Crearlo con el asistente y probarlo de verdad.
2. `python3 tools/xf_profile.py --check profiles/mi-mesa.conf`
3. Pull request con: el `.conf`, modelo y firmware exactos, y que has comprobado.
4. Los perfiles se publican bajo **CC0-1.0** (dominio publico), no GPL. Son datos
   de interoperabilidad; que sean libres del todo evita cualquier friccion legal y
   permite que otros proyectos los usen. Ver `profiles/LICENSE`.

## 10. Lo que NO se hace

- Nada de subida automatica ni de "compartir anonimamente tu configuracion".
  Sin cuenta y sin telemetria, ya se decidio.
- No se ejecuta codigo desde un `.conf`. Es datos, y se valida antes de cargar.
- No se incluyen perfiles inventados marcados como verificados. Nunca.
