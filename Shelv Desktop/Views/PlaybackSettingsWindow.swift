import SwiftUI

struct PlaybackSettingsWindow: View {
    var body: some View {
        TabView {
            CrossfadePanel()
                .tabItem {
                    Label(tr("Crossfade & Gapless", "Crossfade & Gapless"), systemImage: "waveform")
                }
            LyricsSettingsPanel()
                .tabItem {
                    Label(tr("Lyrics", "Lyrics"), systemImage: "music.note.list")
                }
            TranscodingPanel()
                .tabItem {
                    Label(tr("Transcoding", "Transcoding"), systemImage: "waveform.badge.magnifyingglass")
                }
        }
    }
}
