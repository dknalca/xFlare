// SPDX-License-Identifier: GPL-3.0-only

import SwiftUI
import XFDesign

/// Exportar perfil y flujo de aportación (`docs/UI_DESIGN.md` §3.11): muestra el
/// `.conf` generado, sus errores de validación y un botón para guardarlo/enviarlo.
public struct ProfileExportView: View {

    private let profile: ExportableProfile
    private let onSave: (String) -> Void      // recibe el texto .conf

    public init(profile: ExportableProfile, onSave: @escaping (String) -> Void = { _ in }) {
        self.profile = profile
        self.onSave = onSave
    }

    private var conf: String { ProfileExporter.iniText(profile) }
    private var errors: [String] { ProfileExporter.validationErrors(profile) }

    public var body: some View {
        VStack(alignment: .leading, spacing: XFSpacing.md) {
            if errors.isEmpty {
                Text("Perfil válido.").foregroundColor(XFColor.accent).font(XFFont.bodyMedium(13))
            } else {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(errors, id: \.self) { Text("• \($0)").foregroundColor(Color(hex: 0xFF4D5E)) }
                }
            }

            ScrollView {
                Text(conf).font(XFFont.mono(11)).foregroundColor(XFColor.text)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(XFSpacing.sm)
            }
            .background(XFColor.surface)

            Button("Guardar .conf") { onSave(conf) }
                .xfButton(.filled)
                .disabled(!errors.isEmpty)

            Text("Se guarda en tu carpeta de perfiles. Para aportarlo, adjúntalo a "
                 + "una incidencia; lo revisamos y lo marcamos como verificado.")
                .font(XFFont.body(12)).foregroundColor(XFColor.textMuted)
        }
        .padding(XFSpacing.xl)
        .background(XFColor.bg)
    }
}
