// SPDX-License-Identifier: GPL-3.0-only
//
// XFClock — CAPA 1. Reloj musical: ticks, PPQ 480, transporte, conversion
// tick <-> ms <-> hostTime. Puro: sin UI, sin I/O, sin hardware.
//
// Este fichero es el espacio de nombres del modulo y define la unidad de
// tiempo. Se agrupan aqui `XFClock` (enum-namespace) y el alias `Tick` porque
// un alias no es un tipo con estado; el resto de tipos van en su propio fichero
// (Tempo, TimeSignature, HostClock, ClockMap, Transport).

/// Posicion o distancia en **tiempo musical**, medida en ticks (PPQ 480).
///
/// Es `Int` con signo a proposito: una posicion es >= 0, pero un desfase o la
/// cuenta atras del transporte pueden ser negativos. La conversion a
/// milisegundos o a `hostTime` depende del `Tempo` y se hace en un unico sitio
/// (ADR-016: el patron se guarda en ticks, el BPM es un parametro de reproduccion).
public typealias Tick = Int

/// Espacio de nombres del modulo y constantes del dominio musical.
public enum XFClock {

    /// Pulsos por negra (*pulses per quarter note*). Convencion MIDI.
    /// Todo el proyecto usa 480 (ADR-016). No se cambia sin ADR: hay datos en
    /// `data/scratches/` serializados con este valor.
    public static let ppq: Int = 480

    /// Version del contrato publico de XFClock. Sube cuando cambie la API de
    /// forma incompatible (y entonces hace falta un ADR y re-sellar).
    public static let apiVersion: Int = 1
}
