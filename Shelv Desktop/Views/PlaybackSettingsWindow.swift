import SwiftUI

struct PlaybackSettingsWindow: View {
    var body: some View {
        TabView {
            CrossfadePanel()
                .tabItem {
                    Image(systemName: "waveform")
                    Text(tr("Crossfade & Gapless", "Crossfade & Gapless"))
                }
            LyricsSettingsPanel()
                .tabItem {
                    Image(systemName: "music.note.list")
                    Text(tr("Lyrics", "Lyrics"))
                }
            TranscodingPanel()
                .tabItem {
                    Image(systemName: "waveform.badge.magnifyingglass")
                    Text(tr("Transcoding", "Transcoding"))
                }
        }
        .frame(width: 820, height: 660)
        .transaction { $0.animation = nil }
    }
}
