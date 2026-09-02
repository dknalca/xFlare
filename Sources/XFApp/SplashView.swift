// SPDX-License-Identifier: GPL-3.0-only

import SwiftUI
import XFDesign

/// Arranque de la app: el logo aparece grande en el centro y se encoge hacia la
/// esquina superior izquierda (donde vive el logo de la barra de navegación),
/// disolviéndose sobre la pantalla real. Llama a `onDone` cuando termina.
struct SplashView: View {

    var onDone: () -> Void

    /// 0 = entrando (invisible), 1 = grande en el centro, 2 = encogido en la esquina.
    @State private var phase = 0

    var body: some View {
        GeometryReader { geo in
            let center = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)
            let corner = CGPoint(x: 88, y: 24)   // ~ el logo de la barra de nav

            ZStack {
                XFColor.bg
                    .ignoresSafeArea()
                    .opacity(phase == 2 ? 0 : 1)

                XFWordmark(size: 60)
                    // 0.72 (entrada) -> 1 (grande) -> 0.26 (barra de nav)
                    .scaleEffect(phase == 0 ? 0.72 : (phase == 2 ? 0.26 : 1),
                                 anchor: .center)
                    .position(phase == 2 ? corner : center)
                    .opacity(phase == 0 ? 0 : (phase == 2 ? 0 : 1))
            }
            .onAppear {
                withAnimation(.easeOut(duration: 0.5)) { phase = 1 }
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    withAnimation(.easeInOut(duration: 0.55)) { phase = 2 }
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.65) { onDone() }
            }
        }
        .allowsHitTesting(false)
        .transition(.opacity)
    }
}
