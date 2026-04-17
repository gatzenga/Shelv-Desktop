import SwiftUI

struct CrossfadePanel: View {
    @AppStorage("crossfadeEnabled") private var crossfadeEnabled = false
    @AppStorage("crossfadeDuration") private var crossfadeDuration = 5
    @Environment(\.themeColor) private var themeColor

    var body: some View {
        Form {
            Section {
                Toggle(isOn: $crossfadeEnabled) {
                    Label(tr("Crossfade", "Crossfade"), systemImage: "waveform")
                }
                .tint(themeColor)

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
        .frame(width: 300)
        .fixedSize()
    }
}
