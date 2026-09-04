// SPDX-License-Identifier: GPL-3.0-only

import SwiftUI
import XFDesign

/// Medidor de pico de la salida + corrección de deriva del metrónomo.
///
/// Vive en su **propia** vista para que el sondeo a 20 Hz (`Timer`) invalide
/// solo este trocito y no `LivePracticeView.body` entero (que es enorme). Antes,
/// el `.onReceive` estaba en la vista grande y la re-evaluaba 20 veces por
/// segundo aunque la práctica estuviera parada.
///
/// - El **pico** se lee de `engine.outputPeak` (lo publica el hilo de audio con
///   decaimiento lento) y pinta la barra.
/// - La **deriva** corrige que el reloj del motor (cristal de audio) y el de la
///   sesión (timer de pared) se separan a la larga: 20 veces/s se empuja una
///   corrección suavizada para que el clic siga cayendo en la línea de compás
///   dibujada (`session.tick() + gridShift`). Acotada a ±1 negra.
struct ClipMeterView: View {

    let engine: EngineHandle?
    let session: PracticeSession
    /// Desfase manual de la rejilla (botones ◀/▶); entra en la corrección.
    let gridShift: Double
    /// PPQ del patrón activo, para acotar la corrección a ±1 negra.
    let ppq: Int

    @State private var peak: Double = 0
    @State private var drift: Double = 0

    private let pulse = Timer.publish(every: 0.05, on: .main, in: .common).autoconnect()

    var body: some View {
        let clip = peak >= 1.0
        return VStack(spacing: 2) {
            GeometryReader { geo in
                let h = geo.size.height
                let level = CGFloat(min(1.2, peak)) / 1.2
                ZStack(alignment: .bottom) {
                    RoundedRectangle(cornerRadius: 2).fill(XFColor.bg)
                    RoundedRectangle(cornerRadius: 2)
                        .fill(clip ? Color(hex: 0xFF4D5E)
                              : peak > 0.8 ? Color(hex: 0xF5C542) : XFColor.accent)
                        .frame(height: max(1, h * level))
                }
            }
            .frame(height: 70)
            Text(clip ? "CLIP" : "\(Int(peak * 100))")
                .font(XFFont.mono(9))
                .foregroundColor(clip ? Color(hex: 0xFF4D5E) : XFColor.textMuted)
        }
        .onReceive(pulse) { _ in
            let p = engine?.outputPeak ?? 0
            if p != peak { peak = p }
            if let e = engine {
                let lim = Double(ppq)
                let target = min(lim, max(-lim, session.tick() + gridShift - e.tick))
                drift += (target - drift) * 0.25
                e.setMetronomeDrift(drift)
            }
        }
    }
}
