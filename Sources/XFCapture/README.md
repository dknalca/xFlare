# XFCapture

**Capa 1 · Swift · depende de XFPrimitives, XFClock, CXFTimecode, XFProfiles ·
SEALED (2026-09-05)**

Fuentes de entrada: vinilo de timecode, crossfader (MIDI / retorno de audio /
HID), teclado, y grabación/reproducción de sesión. No hace análisis ni UI —
solo entrega `MotionSample`/`FaderSample` (`XFPrimitives`) a quien las pida.

## Protocolos de frontera (B6.1)

```swift
public protocol MotionSource: AnyObject {
    var isConnected: Bool { get }
    func start() throws
    func stop()
    func latest() -> MotionSample?
}

public protocol FaderSource: AnyObject {
    var isConnected: Bool { get }
    func start() throws
    func stop()
    func latest() -> FaderSample?
}
```

La app nunca habla con el hardware directamente: habla con esto. Cada fuente
tiene identidad (`AnyObject`) — un puerto MIDI, un fichero, un timecoder.

## Fuentes de movimiento

- **`TimecodeMotionSource`** — envuelve `xf_timecoder` (`CXFTimecode`, B5.2-B5.4).
  `submit(pcm:frames:hostTime:)` decodifica fuera del hilo de audio. Validado
  con **vinilo Serato CV02 real** sobre la Rane 72 (B5.5): vel media 0.9999 a
  33⅓, confianza 0.92-1.00, dirección y dropout (dirección invierte
  signo/`dir`; levantar la aguja hace caer la confianza sin colgarse)
  confirmados. El canal correcto en una interfaz multicanal no es el que
  parece — el conector no adivina, hay que decírselo (`AudioDeviceList`, XFApp).
- **`KeyboardMotionSource`** — un baby scratch con el teclado, para desarrollar
  sin mesa (CLAUDE.md §3.5: el teclado es solo para eso).
- **`ReplayMotionSource`** — reproduce un `.xfsession` grabado, determinista
  (`seek(toHostTime:)` sobre el reloj de audio).

## Fuentes de fader (crossfader)

Tres métodos, en orden de preferencia real (ADR-021, corregida 2026-09-03):

1. **MIDI (`MidiFaderSource` + `MidiCrossfaderConfig`)** — el método
   **primario** para la Rane 72: su crossfader MAG FOUR sí manda CC por MIDI
   (confirmado con el aparato: 15313/15317 mensajes CC8/canal16 limpios en una
   captura aislada de 5 min). La conexión CoreMIDI real vive en
   `MidiMonitorConnector` (`XFApp`, F.61) — un cliente único para toda la
   sesión que reparte cada mensaje a `MidiFaderSource` Y a `MidiCommandSource`
   a la vez; validado en producción moviendo solo el crossfader con la mesa
   delante. (El `MidiFaderConnector` dedicado que se planeó al principio nunca
   llegó a instanciarse y se borró como código muerto — ver ADR-021.)
   **`MidiFaderLearner`** (F.67, puro) descubre qué `(canal, cc, rango)` es el
   crossfader observando el tráfico mientras se mueve de tope a tope, para
   mesas/perfiles que no lo declaren (o lo declaren mal).
2. **`audio_return` (`AudioReturnFaderSource`)** — respaldo: tono piloto de
   19,5 kHz sobre el retorno del máster, Goertzel + `FaderBinarizer`. No hace
   falta para la Rane 72 (tiene MIDI), pero el código se queda para mesas que
   de verdad no expongan el crossfader por ningún otro medio. **Sin
   confirmar con hardware real** (probado con piloto sintético).
3. **HID (`HIDFaderSource` + `HIDFaderConnector`)** — respaldo 2, IOHIDManager
   por vendor/product. **Sin confirmar con hardware real** — ningún
   dispositivo lo ha necesitado todavía; el bloque `hid.*` de los perfiles
   queda comentado hasta que haga falta.

`FaderBinarizer` (B6.5, ADR-017) es compartido por los tres: disparador de
Schmitt alrededor de un `cutIn` calibrado con banda de histéresis — **0
eventos fantasma** verificado con 60.000 lecturas ruidosas.

## `.xfsession` (B6.6)

Formato JSON Lines: cabecera de calibración + muestras. Los floats se
serializan como **string** (`"\(x)"`), no como `Double` binario — el
`JSONEncoder` de esta toolchain no re-parsea bit a bit el mismo valor
(ADR-028). Una sesión grabada se reproduce **bit a bit igual**
(`ReplayMotionSource`/`ReplayFaderSource`); `clockMap` reconstruye el
`ClockMap` de la toma.

## Comandos de práctica por MIDI (`PracticeCommandMidi`, ADR-054)

Decodificador puro nota/CC → `PracticeCommandEvent`, con overrides de usuario
por encima de lo que declare el perfil (`[transport]`). `MidiBinding.learned(...)`
traduce un mensaje a asignación para "MIDI Learn" (Ajustes).

## Lo que queda sin confirmar con hardware real

- **`AudioReturnFaderSource`** (tono piloto) y **`HIDFaderConnector`** (IOKit
  HID): la decodificación está probada con señales sintéticas; la conexión con
  el sistema, no. Son **respaldos documentados** (ADR-021) para mesas que no
  tengan el crossfader por MIDI — no bloquean el método primario, que sí está
  confirmado extremo a extremo con la Rane 72.
- Los extremos exactos del barrido MIDI (¿0 y 127 limpios en los topes?) y
  `midi.invert` se confirman en el asistente de calibración
  (`MidiFaderLearner`, F.67); lo aprendido ahí vive solo en la sesión de
  calibración por ahora, no se persiste todavía en `XFPersistence` para la
  práctica real.

## Tests

90 tests. Protocolos, teclado, `TimecodeMotionSource` (con y sin señal real —
B5.2-B5.5), `MidiFaderSource`/`MidiCrossfaderConfig` (parseo, filtrado por
canal, binarización, troceo de `MIDIPacketList` con running status/SysEx),
`MidiFaderLearner` (F.67), `AudioReturnFaderSource` (Goertzel sintético),
`HIDFaderSource`/`HIDCrossfaderConfig`, `FaderBinarizer` (0 fantasmas),
`.xfsession`/replay (ida y vuelta value-equal, re-encode estable),
`PracticeCommandMidi`.
