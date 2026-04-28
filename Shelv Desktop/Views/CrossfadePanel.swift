import SwiftUI

struct CrossfadePanel: View {
    @AppStorage("crossfadeEnabled") private var crossfadeEnabled = false
    @AppStorage("crossfadeDuration") private var crossfadeDuration = 5
    @AppStorage("gaplessEnabled") private var gaplessEnabled = false
    @Environment(\.themeColor) private var themeColor

    var body: some View {
        Form {
            Section {
                Toggle(isOn: $gaplessEnabled) {
                    Label(tr("Gapless Playback", "Lückenloses Abspielen"), systemImage: "music.note.list")
                }
                .tint(themeColor)
                .disabled(crossfadeEnabled)
                .onChange(of: gaplessEnabled) { _, newValue in
                    if newValue { crossfadeEnabled = false }
                }

                Toggle(isOn: $crossfadeEnabled) {
                    Label(tr("Crossfade", "Crossfade"), systemImage: "waveform")
                }
                .tint(themeColor)
                .disabled(gaplessEnabled)
                .onChange(of: crossfadeEnabled) { _, newValue in
                    if newValue { gaplessEnabled = false }
                }

                if crossfadeEnabled {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Label(tr("Duration", "Dauer"), systemImage: "timer")
                            Spacer()
                            Text("\(crossfadeDuration)s")
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }
                        Slider(
                            value: Binding(
                                get: { Double(crossfadeDuration) },
                                set: { crossfadeDuration = Int($0.rounded()) }
                            ),
                            in: 1...12,
                            step: 1
                        )
                        .tint(themeColor)
                    }
                }
            }
        }
        .formStyle(.grouped)
    }
}
