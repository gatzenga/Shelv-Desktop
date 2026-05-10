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
                    "Pre-cache Original File recommended.\nTranscoded streams are pre-cached automatically.",
                    "Pre-cache Originaldatei empfohlen.\nTranskodierte Streams werden automatisch pre-gecached."
                ))
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}
