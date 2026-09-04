// SPDX-License-Identifier: GPL-3.0-only

/// Detecta CUÁL Control Change es el crossfader observando el tráfico MIDI
/// mientras el usuario lo mueve de un tope al otro ("aprender MIDI del
/// fader"), en vez de exigir que el perfil `.conf` ya declare `cc`/canal —
/// así cualquier mesa o controlador funciona sin que alguien tenga que
/// aislar el tráfico a mano con un monitor externo (lo que hizo ADR-021 para
/// la Rane 72: una captura de 5 minutos moviendo *solo* el crossfader).
///
/// Puro: se alimenta con `ingest(...)`, sin CoreMIDI de por medio — se prueba
/// con bytes sintéticos como el resto de `XFCapture`.
public final class MidiFaderLearner {

    private struct Candidate {
        var channel: Int
        var cc: Int
        var minRaw: Int = 127
        var maxRaw: Int = 0
        var count: Int = 0

        var span: Int { maxRaw - minRaw }
    }

    private var candidates: [Int: Candidate] = [:]   // clave = canal*128 + cc

    public init() {}

    /// Empieza (o reinicia) un intento de "aprender": olvida lo observado
    /// hasta ahora.
    public func reset() { candidates.removeAll() }

    /// Procesa un mensaje MIDI de 3 bytes. Ignora todo lo que no sea un
    /// Control Change (`0xB_`) — el resto del tráfico (notas, comandos de
    /// transporte…) no aporta nada a "qué CC es el fader".
    public func ingest(status: UInt8, data1: UInt8, data2: UInt8) {
        guard status & 0xF0 == 0xB0 else { return }
        let channel = Int(status & 0x0F) + 1        // 1..16
        let cc = Int(data1)                          // 0..127
        let raw = Int(data2)                          // 0..127
        let key = channel * 128 + cc
        var c = candidates[key] ?? Candidate(channel: channel, cc: cc)
        c.minRaw = min(c.minRaw, raw)
        c.maxRaw = max(c.maxRaw, raw)
        c.count += 1
        candidates[key] = c
    }

    /// Cuánto ha barrido hasta ahora el candidato que más se ha movido —
    /// para una barra de progreso en vivo ("40 de 127") mientras el usuario
    /// todavía está moviendo el fader. No exige `minSpan`.
    public var bestSpanSoFar: Int { candidates.values.map(\.span).max() ?? 0 }

    /// El `(canal, cc, rango)` que más ha barrido, o `nil` si ninguno supera
    /// `minSpan` — evita que el ruido de un botón o un pad cercano gane por
    /// casualidad (un fader movido de tope a tope barre casi el rango
    /// completo; un control que no se ha tocado apenas oscila). Empate: más
    /// mensajes vistos.
    public func bestGuess(minSpan: Int = 20) -> (channel: Int, cc: Int, rawMin: Int, rawMax: Int)? {
        let ranked = candidates.values
            .filter { $0.span >= minSpan }
            .sorted {
                if $0.span != $1.span { return $0.span > $1.span }
                return $0.count > $1.count
            }
        guard let top = ranked.first else { return nil }
        return (top.channel, top.cc, top.minRaw, top.maxRaw)
    }
}
