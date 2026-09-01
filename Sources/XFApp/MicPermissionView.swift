// SPDX-License-Identifier: GPL-3.0-only

import SwiftUI
import XFDesign

/// Pantalla de permiso de micrófono (`docs/UI_DESIGN.md` §3.12). Texto honesto,
/// y si el usuario dice que no, los pasos para arreglarlo.
public struct MicPermissionView: View {

    private let state: MicPermission
    private let onRequest: () -> Void

    public init(state: MicPermission, onRequest: @escaping () -> Void = {}) {
        self.state = state
        self.onRequest = onRequest
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: XFSpacing.md) {
            Text("Permiso de micrófono").font(XFFont.title(20))
            Text(MicPermission.rationale)
                .font(XFFont.body(13)).foregroundColor(XFColor.textMuted)
                .fixedSize(horizontal: false, vertical: true)

            if state.canRequest {
                Button("Dar permiso", action: onRequest).xfButton(.filled)
            }

            if !state.helpSteps.isEmpty {
                XFCard(raised: true) {
                    VStack(alignment: .leading, spacing: XFSpacing.xs) {
                        Text("Está denegado. Para activarlo:").font(XFFont.bodyMedium(13))
                        ForEach(Array(state.helpSteps.enumerated()), id: \.offset) { i, step in
                            Text("\(i + 1). \(step)")
                                .font(XFFont.body(12)).foregroundColor(XFColor.textMuted)
                        }
                    }
                }
            }

            if state.canCapture {
                Text("Listo: xFlare puede oír el vinilo.").foregroundColor(XFColor.accent)
            }
        }
        .padding(XFSpacing.xl)
        .background(XFColor.bg)
    }
}
