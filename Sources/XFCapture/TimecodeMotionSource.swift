// SPDX-License-Identifier: GPL-3.0-only

import CXFTimecode
import XFPrimitives

/// Fuente de movimiento a partir de un **vinilo de timecode** decodificado por
/// xwax en modo relativo (ADR-004/005): solo velocidad y sentido de giro, sin
/// posicion absoluta de la aguja. Es el ciudadano de primera de xFlare
/// (CLAUDE.md §3, §5); el teclado y el replay son la muleta, esto es lo real.
///
/// Reparto de hilos (CLAUDE.md §7). El callback de audio en C captura el PCM del
/// retorno USB y lo mete en un ring buffer; un consumidor de **prioridad
/// normal** lo drena y llama a `submit(...)` desde aqui. Este codigo Swift NO
/// corre nunca dentro del callback. `xf_timecoder_submit` es RT-safe, pero se
/// invoca fuera del hilo de audio a proposito: el decode (2 ms del presupuesto)
/// no tiene por que vivir en el callback.
///
/// Como `KeyboardMotionSource` y `ReplayMotionSource`, no mira ningun reloj:
/// quien la alimenta le pasa el `hostTime` del bloque de audio que capturo ese
/// PCM, para que la muestra quede en el dominio de reloj de CoreAudio/CoreMIDI.
public final class TimecodeMotionSource: MotionSource {

    /// Ajustes del decoder. Se fijan al construir la fuente; para cambiarlos hay
    /// que `stop()` + `start()` (crear el decoder de xwax es NO RT-SAFE).
    public struct Config: Sendable {
        /// Nombre del formato de xwax: "serato_2a", "traktor_a", "mixvibes_v2"...
        /// Debe existir en la tabla de xwax o `start()` lanza.
        public var format: String
        /// Frecuencia de muestreo del dispositivo de captura, en Hz.
        public var sampleRate: UInt32
        /// Hamster / reverse (ADR-008): invierte el signo de la velocidad. El
        /// autor corta en reverse, asi que esto se usa de verdad.
        public var hamster: Bool

        public init(format: String = "serato_2a",
                    sampleRate: UInt32 = 48_000,
                    hamster: Bool = false) {
            self.format = format
            self.sampleRate = sampleRate
            self.hamster = hamster
        }
    }

    /// `start()` falla si xwax no puede crear el decoder: formato inexistente,
    /// `sampleRate` a 0, o sin memoria.
    public enum StartError: Error, Equatable {
        case decoderCreationFailed(format: String, sampleRate: UInt32)
    }

    private let config: Config

    // Puntero opaco al `xf_timecoder` de C. `nil` mientras la fuente esta
    // parada; se crea en `start()` y se libera en `stop()` / `deinit`.
    private var decoder: OpaquePointer?

    private var current: MotionSample?

    public init(config: Config = .init()) {
        self.config = config
    }

    deinit {
        // Red de seguridad: si alguien suelta la fuente sin `stop()`, no se fuga
        // el decoder de C.
        if let decoder { xf_timecoder_destroy(decoder) }
    }

    public var isConnected: Bool { decoder != nil }

    /// Crea el decoder de xwax. NO RT-SAFE: llamar antes de arrancar el audio.
    /// Idempotente: si ya habia un decoder, lo tira y crea uno limpio.
    public func start() throws {
        stop()
        // `withCString` mantiene viva la cadena C durante la llamada; xwax copia
        // lo que necesita del nombre de formato, no se queda con el puntero.
        let created: OpaquePointer? = config.format.withCString { namePtr in
            xf_timecoder_create(namePtr, config.sampleRate)
        }
        guard let tc = created else {
            throw StartError.decoderCreationFailed(format: config.format,
                                                   sampleRate: config.sampleRate)
        }
        xf_timecoder_set_reversed(tc, config.hamster)
        decoder = tc
        current = nil
    }

    /// Libera el decoder. Idempotente. NO RT-SAFE.
    public func stop() {
        if let decoder { xf_timecoder_destroy(decoder) }
        decoder = nil
        current = nil
    }

    public func latest() -> MotionSample? { current }

    // MARK: - alimentacion

    /// Entrega un bloque de PCM **estereo intercalado de 16 bits** (L,R,L,R...)
    /// capturado en `hostTime`, lo decodifica y actualiza `latest()`.
    ///
    /// - Parameters:
    ///   - pcm: primer sample del bloque. Debe haber al menos `frames * 2`.
    ///   - frames: numero de frames estereo (la mitad de la longitud del buffer).
    ///   - hostTime: instante de captura de este bloque, en el reloj del sistema.
    ///
    /// Si la fuente esta parada o `frames <= 0`, no hace nada.
    public func submit(pcm: UnsafePointer<Int16>, frames: Int, hostTime: UInt64) {
        guard let decoder, frames > 0 else { return }
        xf_timecoder_submit(decoder, pcm, frames)
        // xwax mantiene el estado (filtro alfa-beta de pitch, integral de
        // posicion) dentro del decoder; aqui solo leemos el resultado ya
        // filtrado y lo sellamos con el hostTime del bloque.
        current = MotionSample(
            hostTime: hostTime,
            position: xf_timecoder_position(decoder),
            velocity: xf_timecoder_velocity(decoder),
            confidence: xf_timecoder_confidence(decoder)
        )
    }

    /// Version comoda para PCM que ya vive en un `Array` (tests, y el consumidor
    /// del ring buffer si copia a un buffer propio).
    public func submit(_ pcm: [Int16], hostTime: UInt64) {
        pcm.withUnsafeBufferPointer { buf in
            guard let base = buf.baseAddress else { return }
            submit(pcm: base, frames: buf.count / 2, hostTime: hostTime)
        }
    }

    /// Pone a 0 la posicion acumulada (p. ej. al empezar un ejercicio, para que
    /// la autopista y el disco arranquen alineados). NO RT-SAFE.
    public func resetPosition() {
        guard let decoder else { return }
        xf_timecoder_reset_position(decoder)
    }
}
