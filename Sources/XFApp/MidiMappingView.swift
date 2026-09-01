// SPDX-License-Identifier: GPL-3.0-only

import SwiftUI
import XFDesign

/// Asistente de mapeo MIDI/HID (`docs/UI_DESIGN.md` §3.9): monitor en crudo +
/// MIDI Learn del crossfader, con la propuesta de `audio_return` si no llega MIDI.
public struct MidiMappingView: View {

    @ObservedObject private var model: MidiMappingModel
    private let suggestAudioReturn: Bool
    private let onUseAudioReturn: () -> Void

    public init(model: MidiMappingModel, suggestAudioReturn: Bool = false,
                onUseAudioReturn: @escaping () -> Void = {}) {
        self.model = model
        self.suggestAudioReturn = suggestAudioReturn
        self.onUseAudioReturn = onUseAudioReturn
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: XFSpacing.md) {
            HStack {
                Button(model.learning == .crossfader ? "Escuchando…" : "Aprender crossfader") {
                    model.learn(.crossfader)
                }
                .xfButton(.filled)
                if let cc = model.crossfaderCC {
                    Text("CC \(cc)").font(XFFont.mono(13)).foregroundColor(XFColor.accent)
                }
            }

            if suggestAudioReturn {
                XFCard(raised: true) {
                    VStack(alignment: .leading, spacing: XFSpacing.xs) {
                        Text("No llega MIDI de esta mesa.").font(XFFont.bodyMedium(13))
                        Text("Muchas mesas de batalla (Rane 72) no mandan la posición del "
                             + "crossfader por MIDI. Usa el retorno de audio con tono piloto.")
                            .font(XFFont.body(12)).foregroundColor(XFColor.textMuted)
                        Button("Usar retorno de audio", action: onUseAudioReturn).xfButton(.bordered)
                    }
                }
            }

            Text("Monitor en crudo").font(XFFont.body(12)).foregroundColor(XFColor.textMuted)
            ScrollView {
                VStack(alignment: .leading, spacing: 1) {
                    ForEach(Array(model.rawLog.enumerated()), id: \.offset) { _, line in
                        Text(line).font(XFFont.mono(11)).foregroundColor(XFColor.textMuted)
                    }
                }
            }
            .frame(maxHeight: 240)
            .background(XFColor.surface)
        }
        .padding(XFSpacing.xl)
        .background(XFColor.bg)
    }
}
