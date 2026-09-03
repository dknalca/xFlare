// SPDX-License-Identifier: GPL-3.0-only

import SwiftUI
import XFDesign

/// Pantalla de carga que se muestra mientras la práctica decodifica el sample y
/// la instrumental (hay un retardo real antes de que suene). Logo grande y,
/// debajo, una cita de turntablism (`citas.md`).
struct LoadingView: View {

    let quote: String

    var body: some View {
        ZStack {
            XFColor.bg.ignoresSafeArea()
            VStack(spacing: XFSpacing.xl) {
                XFWordmark(size: 44)
                ProgressView()
                    .progressViewStyle(.circular)
                    .scaleEffect(0.8)
                Text(quote)
                    .font(XFFont.body(13))
                    .foregroundColor(XFColor.textMuted)
                    .italic()
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 460)
            }
            .padding(XFSpacing.xl)
        }
        .transition(.opacity)
    }
}
