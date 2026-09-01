// SPDX-License-Identifier: GPL-3.0-only

/// Coincidencia de comodines para el `[match]` de los perfiles: `*` casa con
/// cualquier secuencia (incluida la vacia), el resto es literal. Sin distinguir
/// mayusculas (los nombres de puerto varian en capitalizacion segun el sistema).
///
/// Ejemplo: `"*Seventy-Two*"` casa con `"Rane Seventy-Two MIDI 1"`.
public enum GlobMatch {

    public static func matches(pattern: String, _ text: String) -> Bool {
        let p = Array(pattern.lowercased())
        let s = Array(text.lowercased())

        // Algoritmo clasico de dos punteros para glob con un solo comodin `*`:
        // cuando algo no casa, se retrocede al ultimo `*` y se le da una letra mas.
        var pi = 0, si = 0
        var lastStar = -1          // posicion del ultimo `*` visto en el patron
        var matchAfterStar = 0     // cuanto de la cadena ya consumio ese `*`

        while si < s.count {
            if pi < p.count && p[pi] == s[si] {
                pi += 1; si += 1
            } else if pi < p.count && p[pi] == "*" {
                lastStar = pi
                matchAfterStar = si
                pi += 1
            } else if lastStar != -1 {
                pi = lastStar + 1
                matchAfterStar += 1
                si = matchAfterStar
            } else {
                return false
            }
        }
        // se acabo la cadena: solo quedan `*` sueltos en el patron?
        while pi < p.count && p[pi] == "*" { pi += 1 }
        return pi == p.count
    }
}
