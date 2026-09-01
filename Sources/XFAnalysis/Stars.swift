// SPDX-License-Identifier: GPL-3.0-only

/// Las tres estrellas por criterios ortogonales (ADR-025). No son tres umbrales
/// del mismo numero: cada una mide algo distinto, y por eso el numero de
/// estrellas ya es un diagnostico. Las apagadas dicen que falta.
enum Stars {

    struct Result {
        let count: Int
        /// Por que no se llego a la siguiente estrella.
        let reasons: [String]
    }

    static func evaluate(accuracy: Double, finished: Bool, sigmaMs: Double,
                         zeroScoredEvents: Int, atTargetBpm: Bool) -> Result {
        var reasons: [String] = []

        let s1 = accuracy >= ScoringConstants.star1Accuracy && finished
        let s2 = s1 && accuracy >= ScoringConstants.star2Accuracy && zeroScoredEvents == 0
        let s3 = s2 && accuracy >= ScoringConstants.star3Accuracy
            && sigmaMs <= ScoringConstants.star3SigmaMs && atTargetBpm

        let count = s3 ? 3 : (s2 ? 2 : (s1 ? 1 : 0))

        if !s1 {
            if !finished { reasons.append("★ Completado: no llegaste al final del patron.") }
            if accuracy < ScoringConstants.star1Accuracy {
                reasons.append(String(format: "★ Completado: necesitas al menos %.0f%% (tienes %.0f%%).",
                                      ScoringConstants.star1Accuracy * 100, accuracy * 100))
            }
        } else if !s2 {
            if accuracy < ScoringConstants.star2Accuracy {
                reasons.append(String(format: "★★ Limpio: necesitas %.0f%% (tienes %.0f%%).",
                                      ScoringConstants.star2Accuracy * 100, accuracy * 100))
            }
            if zeroScoredEvents > 0 {
                reasons.append("★★ Limpio: se te ha caido \(zeroScoredEvents) evento\(zeroScoredEvents == 1 ? "" : "s") (a 0). Limpio = ninguno a 0.")
            }
        } else if !s3 {
            if accuracy < ScoringConstants.star3Accuracy {
                reasons.append(String(format: "★★★ Solido: necesitas %.0f%% (tienes %.0f%%).",
                                      ScoringConstants.star3Accuracy * 100, accuracy * 100))
            }
            if sigmaMs > ScoringConstants.star3SigmaMs {
                reasons.append(String(format: "★★★ Solido: tu timing varia %.0f ms; hace falta <= %.0f ms.",
                                      sigmaMs, ScoringConstants.star3SigmaMs))
            }
            if !atTargetBpm {
                reasons.append("★★★ Solido: tienes que clavarlo al BPM objetivo, no por debajo.")
            }
        }
        return Result(count: count, reasons: reasons)
    }
}
