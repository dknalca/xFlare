// SPDX-License-Identifier: GPL-3.0-only

import Foundation
import CXFAudioCore

/// Envoltorio Swift seguro del motor de audio en C (`xf_engine`, B4.2). Gestiona
/// el ciclo de vida (RAII), copia el sample de scratch a un buffer estable (el
/// motor no lo copia), y expone el nucleo RT (`renderBlock`) para poder probar
/// el cableado sin hardware. Quien lo usa es `AppModel`.
public final class EngineHandle {

    private let engine: OpaquePointer
    private let sampleRate: Double
    private let maxFrames: Int

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
    }

    public func clearInstrumental() {
        xf_engine_load_instrumental(engine, nil, 0, 0)
        retiredInstrumental?.deallocate()
        retiredInstrumental = currentInstrumental
        currentInstrumental = nil
    }

    public func setInstrumentalGain(_ g: Float) { xf_engine_set_instrumental_gain(engine, g) }

    public func setTransport(bpm: Double, ppq: Int, playing: Bool) {
        xf_engine_set_transport(engine, bpm, Int32(ppq), playing)
    }
    public func seek(tick: Double)          { xf_engine_seek_tick(engine, tick) }
    public func setVelocity(_ v: Double)    { xf_engine_set_velocity(engine, v) }
    public func setMasterGain(_ g: Float)   { xf_engine_set_master_gain(engine, g) }

    public var tick: Double { xf_engine_tick(engine) }
    public var overloadCount: UInt64 { xf_engine_overload_count(engine) }
    public var renderErrorCount: UInt64 { xf_engine_render_error_count(engine) }

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
