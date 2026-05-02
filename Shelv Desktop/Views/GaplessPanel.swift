import SwiftUI

struct GaplessPanel: View {
    @AppStorage("gaplessEnabled") private var gaplessEnabled = false
    @Environment(\.themeColor) private var themeColor

    var body: some View {
        Form {
            Section {
                Toggle(isOn: $gaplessEnabled) {
                    Label(tr("Gapless Playback", "Lückenloses Abspielen"), systemImage: "music.note.list")
                }
                .tint(themeColor)
                Text(tr(
                    "Gapless and transcoding are not fully compatible — a short gap between tracks is expected.",
                    "Gapless und Transcoding sind nicht vollständig kompatibel – ein kurzer Übergang zwischen Titeln ist normal."
                ))
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}
