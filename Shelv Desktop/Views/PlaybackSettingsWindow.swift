import SwiftUI

struct PlaybackSettingsWindow: View {
    var body: some View {
        TabView {
            GaplessPanel()
                .tabItem {
                    Image(systemName: "music.note.list")
                    Text(tr("Gapless", "Gapless"))
                }
            TranscodingPanel()
                .tabItem {
                    Image(systemName: "waveform.badge.magnifyingglass")
                    Text(tr("Transcoding", "Transcoding"))
                }
            LyricsSettingsPanel()
                .tabItem {
                    Image(systemName: "text.quote")
                    Text(tr("Lyrics", "Lyrics"))
                }
        }
        .frame(width: 820, height: 660)
        .transaction { $0.animation = nil }
    }
}
