// SPDX-License-Identifier: GPL-3.0-only

/// Convierte los numeros en frases accionables (ADR-018). La clave: **distinguir
/// sesgo de dispersion**. Un sesgo (media con signo) se corrige moviendo el
/// gesto; una dispersion (sigma) se corrige practicando la regularidad.
enum Diagnoser {

    /// Umbrales (ms). Provisionales: se afinaran contra tomas reales (B8.5).
    static let biasMs = 12.0        // por encima de esto, el sesgo se considera sistematico
    static let spreadMs = 18.0      // por encima de esto, el timing se considera irregular

    static func diagnose(clickOffsets: [ClickOffset],
                         biasMs bias: Double,
                         sigmaMs sigma: Double,
                         missedClicks: Int,
                         amplitudeError: Double,
                         pitchDistance: Double) -> [Diagnostic] {
        var out: [Diagnostic] = []

        // 1) clicks perdidos: lo primero, es lo mas grave
        if missedClicks > 0 {
            out.append(Diagnostic(.missedClicks,
                "Se te han caido \(missedClicks) click\(missedClicks == 1 ? "" : "s"). En una rutina eso se oye."))
        }

        // 2) sesgo sistematico vs dispersion (excluyentes en el mensaje principal)
        let played = clickOffsets.filter { !$0.isMissed }.count
        if played >= 2 {
            if abs(bias) >= biasMs && sigma < spreadMs {
                let dir = bias > 0 ? "tarde" : "pronto"
                let verb = bias > 0 ? "Adelanta" : "Retrasa"
                out.append(Diagnostic(.timingBias, String(format:
                    "Llegas %.0f ms %@ de forma sistematica. %@ el click un pelin.",
                    abs(bias), dir, verb)))
            } else if sigma >= spreadMs {
                out.append(Diagnostic(.timingSpread, String(format:
                    "Tu timing es irregular (±%.0f ms). No es que llegues tarde: es que no llegas siempre igual. Practica con el metronomo.",
                    sigma)))
            } else if abs(bias) < biasMs && sigma < spreadMs {
                out.append(Diagnostic(.good, String(format:
                    "Timing solido: sesgo %.0f ms, dispersion ±%.0f ms.", bias, sigma)))
            }
        }

        // 3) amplitud
        if amplitudeError >= 0.20 {
            out.append(Diagnostic(.amplitude, String(format:
                "El recorrido de los trazos no es parejo (error medio %.0f%%). Iguala cuanto mueves el disco en cada empuje.",
                amplitudeError * 100)))
        }

        // 4) contorno de tono
        if pitchDistance >= 0.22 {
            out.append(Diagnostic(.pitchContour,
                "El contorno de tono no sigue el patron: revisa donde acelera y donde frena el disco."))
        }

        return out
    }
}
