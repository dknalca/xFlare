// SPDX-License-Identifier: GPL-3.0-only

import XFNotation

/// Texto de contexto para la ventana de detalle de un truco: una descripción de
/// qué es y una nota de historia (quién lo introdujo / popularizó).
///
/// PROVISIONAL: vive en código para no tocar `CatalogLoader` ni el esquema. A
/// futuro esto debería ser `data/scratches/lore.json` cargado en `Catalog`.
///
/// Los datos de historia son **hechos** sacados del manual TTM
/// (Carluccio / Imboden / Pirtle) — ver `docs/MATRIX_MAPPING.md §3b`. No se
/// reproduce su prosa; son atribuciones de técnica, terminología común.
public enum ScratchLore {

    /// Descripción corta. Se compone de la familia + lo que hace la mano y el
    /// fader; si no se reconoce nada, cae a una frase genérica.
    public static func description(for s: Scratch) -> String {
        var parts: [String] = []
        if let h = hand[s.hand] { parts.append(h) }
        if let f = fader[s.fader], s.fader != "open" { parts.append(f) }
        if parts.isEmpty {
            parts.append("Patrón de \(s.family): \(s.technique).")
        }
        if s.clickCount > 0 {
            parts.append("\(s.clickCount) clicks de fader en el patrón.")
        }
        if !s.notes.isEmpty { parts.append(s.notes) }
        return parts.joined(separator: " ")
    }

    /// Nota de historia, si la hay para esta familia. `nil` = no tenemos.
    public static func history(for s: Scratch) -> String? {
        history[s.hand] ?? history[s.fader] ?? history[s.family]
    }

    // MARK: - tablas

    /// Qué hace la MANO (movimiento del disco).
    private static let hand: [String: String] = [
        "baby": "Movimiento simétrico del vinilo adelante y atrás, sin parar.",
        "stab": "Empujón corto y rápido hacia delante; la vuelta no se oye.",
        "drag": "Movimiento lento y muy controlado del disco.",
        "tear2": "El movimiento se parte en dos tramos de velocidad distinta, con una parada.",
        "tear3": "El movimiento se parte en tres tramos, con paradas entre ellos.",
        "scribble": "Baby muy rápido y corto, con tensión del antebrazo y vibración de la yema.",
        "chirp_hand": "Empujones cortos y rápidos alternando ida y vuelta.",
        "hydroplane": "Se fricciona el dedo contra el disco que gira: textura, no un movimiento limpio.",
    ]

    /// Qué hace el FADER.
    private static let fader: [String: String] = [
        "forward_cut": "El fader corta la vuelta: solo se oye la ida.",
        "reverse_cut": "El fader corta la ida: solo se oye la vuelta.",
        "chirp": "El fader abre al arrancar y cierra al frenar, en las dos direcciones.",
        "transformer_2": "El fader trocea el movimiento en 2 cortes por tramo.",
        "transformer_3": "El fader trocea el movimiento en 3 cortes por tramo.",
        "transformer_4": "El fader trocea el movimiento en 4 cortes por tramo.",
        "flare_1c": "Fader abierto, con un click en mitad de la ida y otro en mitad de la vuelta.",
        "flare_1c_lo": "Flare con el click en la primera mitad del trazo.",
        "flare_1c_hi": "Flare con el click en la segunda mitad del trazo.",
        "flare_2c": "Fader abierto con dos clicks por tramo.",
        "flare_3c": "Fader abierto con tres clicks por tramo.",
        "orbit_1c": "Flare aplicado también en la vuelta: el click cae en las dos direcciones.",
        "orbit_2c": "Orbit con dos clicks por dirección.",
        "twiddle_2c": "Clicks alternando dos dedos contra el pulgar.",
        "crab_4c": "El pulgar contra los cuatro dedos en secuencia (meñique a índice): ráfaga de 4 clicks.",
    ]

    /// Historia por familia / mano / fader (lo primero que encaje).
    private static let history: [String: String] = [
        "baby": "El scratch fundamental. Todo lo demás se construye encima de él.",
        "forward_cut": "El Forward lo originó G.W. Theodore y lo hizo famoso Grandmaster Flash.",
        "chirp": "El pitch del chirp sube o baja según el vinilo se mueva más o menos rápido.",
        "transformer_2": "Popularizado por Jazzy Jeff y Cash Money. El nombre viene del sonido de Optimus Prime.",
        "transformer_3": "Popularizado por Jazzy Jeff y Cash Money.",
        "transformer_4": "Popularizado por Jazzy Jeff y Cash Money.",
        "flare_1c": "Lo introdujo DJ Flare y lo popularizó DJ Q-bert. El cambio de dirección se oye "
            + "(phantom click) y crea la ilusión del doble de cortes.",
        "flare_2c": "Con dos clicks reales, los phantom clicks del cambio de dirección hacen que suene a cuatro.",
        "flare_3c": "Introducido por DJ Flare, popularizado por DJ Q-bert.",
        "orbit_1c": "Un flare ejecutado en círculo continuo: el click también cae en la vuelta.",
        "crab_4c": "Inventado por DJ Q-bert.",
        "scribble": "Se suele hacer aplicando vibración con la yema del dedo en un punto concreto del vinilo.",
    ]
}
