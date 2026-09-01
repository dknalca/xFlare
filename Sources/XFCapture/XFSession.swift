// SPDX-License-Identifier: GPL-3.0-only

import Foundation
import XFClock
import XFPrimitives

/// Una sesion grabada: la cabecera de calibracion + las muestras crudas de disco
/// y de fader. Serializa a **JSON Lines** (`.xfsession`): una linea por objeto,
/// la primera es la cabecera (docs/ARCHITECTURE.md §4).
///
/// Es la pieza que mas rentabiliza el esfuerzo: los tests de `XFAnalysis` corren
/// contra sesiones grabadas, y ademas es funcionalidad de usuario ("revisar tu
/// toma").
public struct XFSession: Equatable, Sendable {

    /// Metadatos suficientes para reconstruir el `ClockMap` de la toma.
    public struct Header: Equatable, Sendable {
        public var formatVersion: Int
        public var tempoBPM: Double
        public var anchorHostTime: UInt64
        public var anchorTick: Int
        public var hostNumer: UInt64
        public var hostDenom: UInt64
        public var notes: String

        public init(formatVersion: Int = 1, tempoBPM: Double,
                    anchorHostTime: UInt64, anchorTick: Int,
                    hostNumer: UInt64, hostDenom: UInt64, notes: String = "") {
            self.formatVersion = formatVersion
            self.tempoBPM = tempoBPM
            self.anchorHostTime = anchorHostTime
            self.anchorTick = anchorTick
            self.hostNumer = hostNumer
            self.hostDenom = hostDenom
            self.notes = notes
        }
    }

    public var header: Header
    public var motion: [MotionSample]
    public var fader: [FaderSample]

    public init(header: Header, motion: [MotionSample], fader: [FaderSample]) {
        self.header = header
        self.motion = motion
        self.fader = fader
    }

    /// El `ClockMap` de esta toma, para llevar los `hostTime` a ticks.
    public var clockMap: ClockMap {
        ClockMap(anchorHostTime: header.anchorHostTime,
                 anchorTick: header.anchorTick,
                 tempo: Tempo(bpm: header.tempoBPM),
                 host: HostClock(numer: header.hostNumer, denom: header.hostDenom))
    }

    // MARK: - serializacion JSON Lines

    public enum SessionError: Error, Equatable, CustomStringConvertible {
        case empty
        case badLine(Int, String)
        case missingHeader

        public var description: String {
            switch self {
            case .empty:            return "sesion vacia"
            case .badLine(let n, let why): return "linea \(n): \(why)"
            case .missingHeader:    return "la primera linea no es una cabecera valida"
            }
        }
    }

    // DTOs de linea. `kind` distingue el tipo. Claves cortas: son millones de
    // lineas en una toma larga.
    //
    // Los numeros de coma flotante se guardan como **cadena** (`"\(x)"`), no como
    // numero JSON: el `JSONEncoder` de Foundation en esta toolchain no siempre
    // escribe un `Double` con una representacion que re-parsee al MISMO bit
    // (es justo el problema de ADR-028). La interpolacion de Swift si da la
    // representacion minima con ida y vuelta exacta, y `Double(_: String)` la
    // lee sin perdida. Los enteros (`hostTime`) van como numero normal.
    private struct KindOnly: Decodable { let kind: String }
    private struct HeaderLine: Codable {
        let kind: String; let v: Int; let bpm: String
        let aht: UInt64; let atk: Int; let hn: UInt64; let hd: UInt64; let notes: String
    }
    private struct MotionLine: Codable {
        let kind: String; let t: UInt64; let p: String; let vel: String; let c: String
    }
    private struct FaderLine: Codable {
        let kind: String; let t: UInt64; let val: String; let o: Bool
    }

    public func encodedJSONLines() -> String {
        let enc = JSONEncoder()
        enc.outputFormatting = [.sortedKeys]   // determinista
        func line<T: Encodable>(_ v: T) -> String {
            String(data: (try? enc.encode(v)) ?? Data(), encoding: .utf8) ?? "{}"
        }
        var out: [String] = []
        out.append(line(HeaderLine(kind: "header", v: header.formatVersion, bpm: "\(header.tempoBPM)",
                                   aht: header.anchorHostTime, atk: header.anchorTick,
                                   hn: header.hostNumer, hd: header.hostDenom, notes: header.notes)))
        for m in motion {
            out.append(line(MotionLine(kind: "m", t: m.hostTime, p: "\(m.position)",
                                       vel: "\(m.velocity)", c: "\(m.confidence)")))
        }
        for f in fader {
            out.append(line(FaderLine(kind: "f", t: f.hostTime, val: "\(f.value)", o: f.isOpen)))
        }
        return out.joined(separator: "\n") + "\n"
    }

    public init(jsonLines text: String) throws {
        let dec = JSONDecoder()
        let lines = text.split(separator: "\n", omittingEmptySubsequences: true)
        guard !lines.isEmpty else { throw SessionError.empty }

        var header: Header? = nil
        var motion: [MotionSample] = []
        var fader: [FaderSample] = []

        for (i, raw) in lines.enumerated() {
            let data = Data(raw.utf8)
            guard let kind = try? dec.decode(KindOnly.self, from: data).kind else {
                throw SessionError.badLine(i + 1, "no es JSON con campo 'kind'")
            }
            switch kind {
            case "header":
                guard let h = try? dec.decode(HeaderLine.self, from: data),
                      let bpm = Double(h.bpm) else {
                    throw SessionError.badLine(i + 1, "cabecera mal formada")
                }
                header = Header(formatVersion: h.v, tempoBPM: bpm,
                                anchorHostTime: h.aht, anchorTick: h.atk,
                                hostNumer: h.hn, hostDenom: h.hd, notes: h.notes)
            case "m":
                guard let m = try? dec.decode(MotionLine.self, from: data),
                      let p = Double(m.p), let vel = Double(m.vel), let c = Float(m.c) else {
                    throw SessionError.badLine(i + 1, "muestra de disco mal formada")
                }
                motion.append(MotionSample(hostTime: m.t, position: p,
                                           velocity: vel, confidence: c))
            case "f":
                guard let f = try? dec.decode(FaderLine.self, from: data),
                      let val = Float(f.val) else {
                    throw SessionError.badLine(i + 1, "muestra de fader mal formada")
                }
                fader.append(FaderSample(hostTime: f.t, value: val, isOpen: f.o))
            default:
                throw SessionError.badLine(i + 1, "kind desconocido: \(kind)")
            }
        }

        guard let h = header else { throw SessionError.missingHeader }
        self.init(header: h, motion: motion, fader: fader)
    }
}
