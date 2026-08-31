// SPDX-License-Identifier: GPL-3.0-only
//
// Pantalla de inicio MAQUETADA (andamiaje). Reproduce la estructura de
// docs/UI_DESIGN.md secciones 2 y 3.2 con los tokens de color reales, pero
// NADA responde: es un cascaron para poder abrir la app y ver el menu.
// La version real vive en XFApp a partir del bloque B11.

import SwiftUI

// MARK: - Tokens (copiados de docs/UI_DESIGN.md §2; migraran a XFDesign en B7.1)

private enum XF {
    static let bg            = Color(hex: 0x0B0D10)
    static let surface       = Color(hex: 0x14181D)
    static let surfaceRaised = Color(hex: 0x1E242B)
    static let stroke        = Color(hex: 0x2A323B)
    static let text          = Color(hex: 0xF2F5F7)
    static let textMuted     = Color(hex: 0x9AA5B1)
    static let accent        = Color(hex: 0x34E1C4)
    static let grid          = Color(hex: 0x232A32)
    static let gridBeat      = Color(hex: 0x3A444F)
    static let ok            = Color(hex: 0x8ED44A)
    static let warn          = Color(hex: 0xF5C542)
    static let late          = Color(hex: 0xFF7A45)
}

extension Color {
    init(hex: UInt32) {
        self.init(.sRGB,
                  red:   Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue:  Double(hex & 0xFF) / 255,
                  opacity: 1)
    }
}

// MARK: - Secciones del menu (docs/UI_DESIGN.md §3)

private struct Section: Identifiable {
    let id = UUID()
    let name: String
    let symbol: String
    let hint: String
}

private let sections: [Section] = [
    .init(name: "Calibracion", symbol: "dot.radiowaves.left.and.right",
          hint: "Audio, latencia, timecode y fader. La pantalla mas importante."),
    .init(name: "Practicar",   symbol: "waveform.path",
          hint: "La autopista: patron fantasma y tu curva encima."),
    .init(name: "Libre",       symbol: "record.circle",
          hint: "Sin evaluar. Graba los ultimos 30 s."),
    .init(name: "Libreria",    symbol: "square.grid.3x3",
          hint: "La matriz de scratches con su notacion XFN."),
    .init(name: "Progreso",    symbol: "chart.xyaxis.line",
          hint: "Historico por tecnica y variante, con sesgo firmado."),
    .init(name: "Mi mesa",     symbol: "pianokeys",
          hint: "Perfiles .conf, insignias de verificacion y prueba en vivo."),
    .init(name: "Ajustes",     symbol: "slider.horizontal.3",
          hint: "Todo local: sin cuenta, sin nube, sin telemetria."),
]

// MARK: - Vista

struct HomeScaffoldView: View {
    @State private var selection: UUID?

    var body: some View {
        NavigationView {
            sidebar
            home
        }
        .frame(minWidth: 900, minHeight: 620)
        .background(XF.bg)
    }

    // Barra lateral: el "menu" que el autor quiere ver.
    private var sidebar: some View {
        VStack(spacing: 0) {
            List(selection: $selection) {
                ForEach(sections) { s in
                    HStack(spacing: 10) {
                        Image(systemName: s.symbol)
                            .frame(width: 20)
                            .foregroundColor(XF.accent)
                        Text(s.name).foregroundColor(XF.text)
                    }
                    .padding(.vertical, 4)
                    .tag(s.id)
                }
            }
            .listStyle(SidebarListStyle())

            Rectangle().fill(XF.stroke).frame(height: 1)
            Text("andamiaje visual · nada funciona todavia (B11)")
                .font(.footnote)
                .foregroundColor(XF.textMuted)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(minWidth: 220)
        .background(XF.surface)
    }

    // Contenido: maqueta del Home (docs/UI_DESIGN.md §3.2).
    private var home: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {

                VStack(alignment: .leading, spacing: 4) {
                    Text("xFlare")
                        .font(.system(size: 40, weight: .semibold))
                        .foregroundColor(XF.text)
                    Text("entrenador de scratch y turntablism")
                        .foregroundColor(XF.textMuted)
                }

                continueCard

                HStack(spacing: 16) {
                    stat("Racha", "0 dias")
                    stat("Hoy", "0 min")
                    stat("Mejor BPM 3★", "—")
                }

                Text("Mapa de la matriz")
                    .font(.headline)
                    .foregroundColor(XF.text)
                matrixGrid

                Text("Placeholder. La cuadricula real se ilumina segun lo dominado; "
                     + "la tarjeta Continuar lleva al ejercicio en curso. Todo eso es B9-B11.")
                    .font(.footnote)
                    .foregroundColor(XF.textMuted)
            }
            .padding(32)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(XF.bg)
    }

    private var continueCard: some View {
        HStack {
            VStack(alignment: .leading, spacing: 6) {
                Text("CONTINUAR").font(.caption).foregroundColor(XF.textMuted)
                Text("2-Click Flare").font(.title2.bold()).foregroundColor(XF.text)
                Text("Nivel 4 · 80 BPM · serie 2/3").foregroundColor(XF.textMuted)
            }
            Spacer()
            Image(systemName: "play.fill")
                .font(.title)
                .foregroundColor(XF.bg)
                .padding(18)
                .background(Circle().fill(XF.accent))
        }
        .padding(20)
        .background(RoundedRectangle(cornerRadius: 16).fill(XF.surfaceRaised))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(XF.stroke))
    }

    private func stat(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.caption).foregroundColor(XF.textMuted)
            Text(value)
                .font(.system(.title3, design: .monospaced))
                .foregroundColor(XF.text)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12).fill(XF.surface))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(XF.stroke))
    }

    private var matrixGrid: some View {
        let cols = Array(repeating: GridItem(.fixed(44), spacing: 8), count: 10)
        return LazyVGrid(columns: cols, spacing: 8) {
            ForEach(0..<40, id: \.self) { i in
                RoundedRectangle(cornerRadius: 8)
                    .fill(i < 6 ? XF.accent.opacity(0.9)
                          : i < 14 ? XF.surfaceRaised
                          : XF.surface)
                    .frame(height: 44)
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(XF.stroke))
            }
        }
    }
}

struct HomeScaffoldView_Previews: PreviewProvider {
    static var previews: some View { HomeScaffoldView() }
}
