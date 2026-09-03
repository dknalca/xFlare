// SPDX-License-Identifier: GPL-3.0-only

import Foundation
import CXFAudioCore

/// Envoltorio Swift seguro del motor de audio en C (`xf_engine`, B4.2). Gestiona
/// el ciclo de vida (RAII), copia el sample de scratch a un buffer estable (el
/// motor no lo copia), y expone el nucleo RT (`renderBlock`) para poder probar
/// el cableado sin hardware. Quien lo usa es `AppModel`.
public final class EngineHandle {

    // `engine` y `maxFrames` no son `let`: `restartOutput` los cambia para poder
    // reabrir el motor con otro tamano de buffer sin reiniciar la app.
    private var engine: OpaquePointer
    private let sampleRate: Double
    private var maxFrames: Int

    /// Tamano de buffer (frames) con el que esta creado el motor ahora mismo.
    public var currentMaxFrames: Int { maxFrames }

    // Se guardan para poder recargar la base al recrear el motor.
    private var instrumentalFrameCount = 0
    private var instrumentalNativeBPM = 0.0

    // Dos buffers para el sample: el actual y el que se acaba de retirar (el
    // motor puede tenerlo un bloque mas). Rotan en `loadSample`.
    private var currentSample: UnsafeMutableBufferPointer<Float>?
    private var retiredSample: UnsafeMutableBufferPointer<Float>?

    // Mismos dos slots para la base instrumental.
    private var currentInstrumental: UnsafeMutableBufferPointer<Float>?
    private var retiredInstrumental: UnsafeMutableBufferPointer<Float>?

    public init?(sampleRate: Double = 48_000, maxFrames: Int = 64) {
        guard let e = xf_engine_create(sampleRate, UInt32(maxFrames)) else { return nil }
        self.engine = e
        self.sampleRate = sampleRate
        self.maxFrames = maxFrames
    }

    deinit {
        xf_engine_stop(engine)
        xf_engine_destroy(engine)
        currentSample?.deallocate()
        retiredSample?.deallocate()
        currentInstrumental?.deallocate()
        retiredInstrumental?.deallocate()
    }

    // MARK: - copias del PCM cargado (para el render offline de F.4)

    /// Copia del sample de scratch cargado, o `nil`.
    public func scratchPCMCopy() -> [Float]? {
        currentSample.map { Array($0) }
    }
    /// Copia de la base instrumental cargada, o `nil`, con su tempo nativo.
    public func instrumentalPCMCopy() -> (pcm: [Float], nativeBPM: Double)? {
        guard let buf = currentInstrumental, instrumentalNativeBPM > 0 else { return nil }
        return (Array(buf), instrumentalNativeBPM)
    }

    // MARK: - control

    /// Carga el sample de scratch (mono). Se copia a un buffer propio que vive
    /// mientras el motor lo use.
    /// Numero de frames del sample de scratch cargado (0 si no hay).
    public private(set) var scratchFrameCount: Int = 0

    public func loadSample(_ mono: [Float]) {
        let buf = UnsafeMutableBufferPointer<Float>.allocate(capacity: max(2, mono.count))
        _ = buf.initialize(from: mono)
        xf_engine_load_sample(engine, buf.baseAddress, Int64(mono.count))

        retiredSample?.deallocate()   // el de hace 2 generaciones ya no lo usa el RT
        retiredSample = currentSample
        currentSample = buf
        scratchFrameCount = mono.count
    }

    public func clearSample() {
        xf_engine_load_sample(engine, nil, 0)
        retiredSample?.deallocate()
        retiredSample = currentSample
        currentSample = nil
        scratchFrameCount = 0
    }

    /// Cabezal del reproductor de scratch en frames (0 si no hay sample).
    public var scratchPlayhead: Double { xf_engine_scratch_playhead(engine) }

    /// Cabezal normalizado 0…1 sobre el sample cargado.
    public var scratchProgress: Double {
        scratchFrameCount > 1 ? scratchPlayhead / Double(scratchFrameCount - 1) : 0
    }

    /// Carga la base instrumental (mono). `nativeBPM` = tempo al que se grabo;
    /// el motor la reproduce en bucle a `bpm/nativeBPM`.
    public func loadInstrumental(_ mono: [Float], nativeBPM: Double) {
        let buf = UnsafeMutableBufferPointer<Float>.allocate(capacity: max(2, mono.count))
        _ = buf.initialize(from: mono)
        xf_engine_load_instrumental(engine, buf.baseAddress, Int64(mono.count), nativeBPM)

        retiredInstrumental?.deallocate()
        retiredInstrumental = currentInstrumental
        currentInstrumental = buf
        instrumentalFrameCount = mono.count
        instrumentalNativeBPM = nativeBPM
    }

    /// Reinstala la MISMA base pero con otro `nativeBPM` (botones x2 / /2): el
    /// bucle vuelve a empezar (cabezal a 0) y el ratio de reproduccion se
    /// recalcula con el BPM de sesion actual. Corrige la deteccion de tempo sin
    /// cambiar la velocidad real de la base (solo la rejilla).
    /// Reinterpreta el tempo nativo de la base **sin reiniciarla** (no toca el
    /// cabezal). Para TAP tempo / editar el BPM: la rejilla cambia en caliente y
    /// la base sigue sonando donde estaba, a su velocidad real.
    public func setInstrumentalNativeBPM(_ nativeBPM: Double) {
        guard nativeBPM > 0 else { return }
        xf_engine_set_instrumental_native_bpm(engine, nativeBPM)
        instrumentalNativeBPM = nativeBPM
    }

    public func replayInstrumental(nativeBPM: Double) {
        guard let buf = currentInstrumental, instrumentalFrameCount >= 2, nativeBPM > 0 else { return }
        xf_engine_load_instrumental(engine, buf.baseAddress, Int64(instrumentalFrameCount), nativeBPM)
        instrumentalNativeBPM = nativeBPM
    }

    public func clearInstrumental() {
        xf_engine_load_instrumental(engine, nil, 0, 0)
        retiredInstrumental?.deallocate()
        retiredInstrumental = currentInstrumental
        currentInstrumental = nil
        instrumentalFrameCount = 0
        instrumentalNativeBPM = 0
    }

    public func setInstrumentalGain(_ g: Float) { xf_engine_set_instrumental_gain(engine, g) }

    public func setTransport(bpm: Double, ppq: Int, playing: Bool) {
        xf_engine_set_transport(engine, bpm, Int32(ppq), playing)
    }
    public func seek(tick: Double)          { xf_engine_seek_tick(engine, tick) }
    public func seekScratch(_ frame: Double) { xf_engine_seek_scratch(engine, frame) }
    /// Ancla de posicion del scratch: trim anti-deriva acotado (ADR-042), no
    /// mueve el cabezal. `nil` = suelto.
    public func setScratchTarget(_ frame: Double?) {
        xf_engine_set_scratch_target(engine, frame ?? -1)
    }
    public func setVelocity(_ v: Double)    { xf_engine_set_velocity(engine, v) }
    public func setMasterGain(_ g: Float)   { xf_engine_set_master_gain(engine, g) }
    /// Ganancia solo del scratch (0…1). La base instrumental no se ve afectada.
    public func setScratchGain(_ g: Float)  { xf_engine_set_scratch_gain(engine, g) }

    /// EQ de 3 bandas (Lo/Mid/Hi) **solo del sample de scratch**, en dB
    /// ([-24, +12]). 0/0/0 = plano (el motor se salta el filtrado). No toca ni la
    /// base instrumental ni el metrónomo. El cambio se ramplea ~20 ms (sin click).
    public func setSampleEQ(lowDb: Float, midDb: Float, highDb: Float) {
        xf_engine_set_sample_eq(engine, lowDb, midDb, highDb)
    }

    /// "Tacto" del plato (ventana Debug). `glideMs`: suavizado de la velocidad —
    /// menos = más seco y el audio sigue mejor al gesto, más = más suave pero con
    /// retardo. `speedGate`: |v| por debajo de la cual el scratch no suena. Se
    /// aplican al vuelo.
    public func setScratchGlideMs(_ ms: Double) { xf_engine_set_scratch_glide_ms(engine, ms) }
    public func setScratchSpeedGate(_ v: Double) { xf_engine_set_scratch_speed_gate(engine, v) }

    public var sampleRateHz: Double { sampleRate }

    public var tick: Double { xf_engine_tick(engine) }
    public var overloadCount: UInt64 { xf_engine_overload_count(engine) }
    public var renderErrorCount: UInt64 { xf_engine_render_error_count(engine) }
    /// Pico de salida antes de limitar. > 1 = la mezcla clipea.
    public var outputPeak: Double { xf_engine_output_peak(engine) }

    public var metronomeEnabled: Bool {
        get { xf_metronome_enabled(xf_engine_metronome(engine)) }
        set { xf_metronome_set_enabled(xf_engine_metronome(engine), newValue) }
    }

    // MARK: - entrada capturada

    /// Drena el ring de entrada: PCM **estereo intercalado de 16 bits** que ha
    /// capturado el callback. Se lo pasa a `TimecodeMotionSource` /
    /// `AudioReturnFaderSource`.
    public func drainInput(maxFrames: Int = 8192) -> [Int16] {
        let ring = xf_engine_input_ring(engine)
        var buf = [Int16](repeating: 0, count: maxFrames * 2)
        let bytes = buf.withUnsafeMutableBytes { xf_ring_read(ring, $0.baseAddress, $0.count) }
        return Array(buf.prefix(bytes / MemoryLayout<Int16>.size))
    }

    // MARK: - host CoreAudio

    /// Arranca la AudioUnit sobre `deviceUID` (nil = salida por defecto).
    /// Devuelve `true` si arranco.
    public func start(deviceUID: String? = nil) -> Bool {
        if let deviceUID {
            return deviceUID.withCString { xf_engine_start(engine, $0) == 0 }
        }
        return xf_engine_start(engine, nil) == 0
    }

    /// Arranca **solo salida** (sin capturar la entrada): para practicar con la
    /// mesa desconectada. Suena el scratch + la base + el metronomo.
    public func startOutput(deviceUID: String? = nil) -> Bool {
        if let deviceUID {
            return deviceUID.withCString { xf_engine_start_output(engine, $0) == 0 }
        }
        return xf_engine_start_output(engine, nil) == 0
    }

    public func stop() { xf_engine_stop(engine) }

    /// Reabre el motor con OTRO tamano de buffer sin reiniciar la app: crea el
    /// motor nuevo, para y destruye el viejo, **recarga** el sample y la base
    /// desde los buffers que este `EngineHandle` ya retiene, y arranca solo-
    /// salida. NO re-aplica ganancias / transporte / metronomo: eso lo hace quien
    /// llama (tiene el estado de la vista). Devuelve `true` si arranco.
    ///
    /// El nuevo se crea **antes** de tocar el viejo: si `xf_engine_create` falla
    /// (p. ej. sin memoria), no se cambia nada y el audio actual sigue sonando.
    @discardableResult
    public func restartOutput(maxFrames newMax: Int, deviceUID: String? = nil) -> Bool {
        let clamped = max(16, min(8192, newMax))
        guard let fresh = xf_engine_create(sampleRate, UInt32(clamped)) else { return false }

        xf_engine_stop(engine)
        xf_engine_destroy(engine)
        engine = fresh
        maxFrames = clamped

        // recargar audio desde los buffers retenidos
        if let s = currentSample, scratchFrameCount >= 2 {
            xf_engine_load_sample(engine, s.baseAddress, Int64(scratchFrameCount))
            xf_engine_seek_scratch(engine, 0)
        }
        if let i = currentInstrumental, instrumentalFrameCount >= 2 {
            xf_engine_load_instrumental(engine, i.baseAddress,
                                       Int64(instrumentalFrameCount), instrumentalNativeBPM)
        }
        return startOutput(deviceUID: deviceUID)
    }

    // MARK: - nucleo RT (para tests / render offline; CoreAudio lo llama solo)

    @discardableResult
    public func renderBlock(inL: [Float]? = nil, inR: [Float]? = nil,
                            count: Int, hostTime: UInt64 = 0) -> (l: [Float], r: [Float]) {
        var outL = [Float](repeating: 0, count: count)
        var outR = [Float](repeating: 0, count: count)
        outL.withUnsafeMutableBufferPointer { ol in
            outR.withUnsafeMutableBufferPointer { or in
                func go(_ il: UnsafePointer<Float>?, _ ir: UnsafePointer<Float>?) {
                    xf_engine_render(engine, il, ir, ol.baseAddress, or.baseAddress,
                                     Int32(count), hostTime)
                }
                if let inL, let inR {
                    inL.withUnsafeBufferPointer { il in inR.withUnsafeBufferPointer { ir in
                        go(il.baseAddress, ir.baseAddress)
                    }}
                } else { go(nil, nil) }
            }
        }
        return (outL, outR)
    }
}
