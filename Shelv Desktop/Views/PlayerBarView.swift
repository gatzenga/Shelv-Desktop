import SwiftUI
import AVKit

struct PlayerBarView: View {
    @EnvironmentObject var appState: AppState
    @ObservedObject var libraryStore = LibraryViewModel.shared
    @EnvironmentObject var lyricsStore: LyricsStore
    @ObservedObject var downloadStore = DownloadStore.shared
    @ObservedObject private var player = AudioPlayerService.shared

    private var audioBadge: String? {
        player.actualStreamFormat?.displayString
    }
    @Environment(\.themeColor) private var themeColor
    @AppStorage("enableFavorites") private var enableFavorites = true
    @AppStorage("enablePlaylists") private var enablePlaylists = true
    @AppStorage("autoFetchLyrics") private var autoFetchLyrics = true
    @State private var isDragging: Bool = false
    @State private var dragValue: Double = 0
    @State private var showQueue: Bool = false
    @State private var showLyrics: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            Divider()
            HStack(spacing: 0) {
                HStack(spacing: 14) {
                    Group {
                        if let song = player.currentSong, let coverID = song.coverArt,
                           let url = SubsonicAPIService.shared.coverArtURL(id: coverID, size: 120) {
                            CoverArtView(url: url, size: 62, cornerRadius: 8)
                        } else {
                            ZStack {
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(.secondary.opacity(0.15))
                                Image(systemName: "music.note")
                                    .font(.title3)
                                    .foregroundStyle(.secondary)
                            }
                            .frame(width: 62, height: 62)
                        }
                    }

                    if let song = player.currentSong {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(song.title)
                                .font(.body.bold())
                                .lineLimit(1)
                            HStack(spacing: 0) {
                                if let id = song.artistId, let name = song.artist {
                                    Button(name) {
                                        appState.selectedPlaylist = nil
                                        appState.selectedSidebar = .artists
                                        appState.navigationPath = NavigationPath()
                                        appState.navigationPath.append(
                                            Artist(id: id, name: name, albumCount: nil, coverArt: nil, starred: nil)
                                        )
                                    }
                                    .buttonStyle(.plain)
                                    .foregroundStyle(themeColor)
                                    .onHover { inside in
                                        if inside { NSCursor.pointingHand.push() } else { NSCursor.pop() }
                                    }
                                } else if let name = song.artist {
                                    Text(name).foregroundStyle(.secondary)
                                }
                                if song.artist != nil && song.album != nil {
                                    Text(" · ").foregroundStyle(.secondary)
                                }
                                if let id = song.albumId, let name = song.album {
                                    Button(name) {
                                        appState.selectedPlaylist = nil
                                        appState.selectedSidebar = .albums
                                        appState.navigationPath = NavigationPath()
                                        appState.navigationPath.append(
                                            Album(id: id, name: name, artist: song.artist,
                                                  artistId: song.artistId, coverArt: song.coverArt,
                                                  songCount: nil, duration: nil, year: nil,
                                                  genre: nil, starred: nil, playCount: nil,
                                                  created: nil)
                                        )
                                    }
                                    .buttonStyle(.plain)
                                    .foregroundStyle(themeColor)
                                    .onHover { inside in
                                        if inside { NSCursor.pointingHand.push() } else { NSCursor.pop() }
                                    }
                                } else if let name = song.album {
                                    Text(name).foregroundStyle(.secondary)
                                }
                            }
                            .font(.callout)
                            .lineLimit(1)
                        }
                    } else {
                        Text(tr("No track", "Kein Titel"))
                            .font(.body)
                            .foregroundStyle(.secondary)
                    }

                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 20)

                VStack(spacing: 10) {
                    HStack(spacing: 22) {
                        Group {
                            if enablePlaylists, let song = player.currentSong {
                                Button {
                                    NotificationCenter.default.post(name: .addSongsToPlaylist, object: [song.id])
                                } label: {
                                    Image(systemName: "music.note.list")
                                        .foregroundStyle(AnyShapeStyle(.primary.opacity(0.35)))
                                }
                                .buttonStyle(.plain)
                                .help(tr("Add to Playlist…", "Zur Wiedergabeliste hinzufügen…"))
                            } else {
                                Image(systemName: "music.note.list")
                                    .hidden()
                            }
                        }
                        .font(.title2)

                        Button { player.toggleShuffle() } label: {
                            Image(systemName: "shuffle")
                                .foregroundStyle(player.isShuffled ? AnyShapeStyle(themeColor) : AnyShapeStyle(.primary.opacity(0.35)))
                        }
                        .buttonStyle(.plain)
                        .font(.title2)
                        .help(player.isShuffled ? tr("Shuffle off", "Zufallsmodus aus") : tr("Shuffle on", "Zufallsmodus an"))

                        Button { player.playPrevious() } label: {
                            Image(systemName: "backward.fill")
                        }
                        .buttonStyle(.plain)
                        .font(.title2)
                        .disabled(player.queue.isEmpty)

                        Button { player.togglePlayPause() } label: {
                            ZStack {
                                Circle().fill(themeColor)
                                Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                                    .foregroundStyle(.white)
                                    .font(.system(size: 17, weight: .semibold))
                                    .offset(x: player.isPlaying ? 0 : 1.5)
                            }
                            .frame(width: 46, height: 46)
                        }
                        .buttonStyle(.plain)
                        .disabled(player.currentSong == nil)

                        Button { player.playNext() } label: {
                            Image(systemName: "forward.fill")
                        }
                        .buttonStyle(.plain)
                        .font(.title2)
                        .disabled(player.repeatMode == .off
                            && player.currentIndex >= player.queue.count - 1
                            && player.playNextQueue.isEmpty
                            && player.userQueue.isEmpty)

                        Button { player.cycleRepeatMode() } label: {
                            Image(systemName: player.repeatMode.systemImage)
                                .foregroundStyle(player.repeatMode == .off ? AnyShapeStyle(.primary.opacity(0.35)) : AnyShapeStyle(themeColor))
                        }
                        .buttonStyle(.plain)
                        .font(.title2)
                        .help(repeatHelpText)

                        Group {
                            if enableFavorites, let song = player.currentSong {
                                let isStarred = libraryStore.isSongStarred(song)
                                Button {
                                    Task {
                                        await libraryStore.toggleStarSong(song)
                                        player.setCurrentSongStarred(!isStarred)
                                    }
                                } label: {
                                    Image(systemName: isStarred ? "heart.fill" : "heart")
                                        .foregroundStyle(isStarred ? AnyShapeStyle(themeColor) : AnyShapeStyle(.primary.opacity(0.35)))
                                }
                                .buttonStyle(.plain)
                                .help(isStarred
                                      ? tr("Remove from Favorites", "Aus Favoriten entfernen")
                                      : tr("Add to Favorites", "Zu Favoriten hinzufügen"))
                            } else {
                                Image(systemName: "heart")
                                    .hidden()
                            }
                        }
                        .font(.title2)
                    }

                    HStack(spacing: 10) {
                        Text(formatTime(isDragging ? dragValue : player.currentTime))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                            .frame(width: 42, alignment: .trailing)

                        Slider(
                            value: Binding(
                                get: { isDragging ? dragValue : player.currentTime },
                                set: { newVal in dragValue = newVal }
                            ),
                            in: 0...max(player.duration, 1)
                        ) { editing in
                            if editing {
                                isDragging = true
                            } else {
                                player.seek(to: dragValue)
                                isDragging = false
                            }
                        }
                        .frame(maxWidth: 360)
                        .disabled(player.currentSong == nil || player.duration <= 0)

                        Text(formatTime(player.duration))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                            .frame(width: 42, alignment: .leading)
                    }
                }
                .frame(maxWidth: 560)

                HStack(spacing: 16) {
                    HStack(spacing: 5) {
                        if player.showBufferingIndicator {
                            ProgressView()
                                .controlSize(.mini)
                                .frame(width: 14, height: 14)
                        }
                        Text(player.showBufferingIndicator ? tr("Loading…", "Lädt…") : (audioBadge ?? ""))
                            .monospacedDigit()
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(height: 14)
                    .padding(.trailing, 8)

                    Button { showLyrics.toggle() } label: {
                        Image(systemName: "text.quote")
                            .font(.system(size: 16))
                            .foregroundStyle(showLyrics ? themeColor : Color.secondary)
                    }
                    .buttonStyle(.plain)
                    .frame(width: 20, height: 20)
                    .help(tr("Lyrics", "Lyrics"))
                    .popover(isPresented: $showLyrics) {
                        LyricsPanel()
                            .environmentObject(lyricsStore)
                            .environment(\.themeColor, themeColor)
                    }

                    AVRoutePickerViewRepresentable()
                        .frame(width: 20, height: 20)
                        .help(tr("AirPlay", "AirPlay"))

                    Image(systemName: player.volume < 0.01 ? "speaker.slash.fill"
                                    : player.volume < 0.5  ? "speaker.wave.1.fill"
                                                           : "speaker.wave.3.fill")
                        .foregroundStyle(.secondary)
                        .font(.body)
                    Slider(value: Binding(
                        get: { Double(player.volume) },
                        set: { player.volume = Float($0) }
                    ), in: 0...1)
                    .frame(width: 100)

                    Button { showQueue.toggle() } label: {
                        Image(systemName: "list.bullet")
                            .font(.body)
                            .foregroundStyle(showQueue ? themeColor : Color.secondary)
                    }
                    .buttonStyle(.plain)
                    .popover(isPresented: $showQueue) {
                        QueuePopover()
                            .frame(width: 380, height: 520)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.trailing, 20)
            }
            .frame(height: 100)
        }
        .background(.bar)
        .task(id: player.currentSong?.id) {
            guard autoFetchLyrics,
                  let song = player.currentSong,
                  let serverId = appState.serverStore.activeServerID?.uuidString
            else {
                lyricsStore.currentLyrics = nil
                lyricsStore.isLoadingLyrics = false
                return
            }
            lyricsStore.loadLyrics(for: song, serverId: serverId)
        }
    }

    private var repeatHelpText: String {
        switch player.repeatMode {
        case .off: return tr("Repeat: Off", "Wiederholen: Aus")
        case .all: return tr("Repeat: All", "Wiederholen: Alle")
        case .one: return tr("Repeat: One", "Wiederholen: Einer")
        }
    }

    private func formatTime(_ seconds: Double) -> String {
        guard seconds.isFinite && seconds >= 0 else { return "0:00" }
        let m = Int(seconds) / 60
        let s = Int(seconds) % 60
        return String(format: "%d:%02d", m, s)
    }

}

private struct QueueEntry: Identifiable {
    let id: String
    let index: Int
    let song: Song
}

struct QueuePopover: View {
    @ObservedObject private var player = AudioPlayerService.shared
    @State private var showClearConfirm = false

    private var playNextEntries: [QueueEntry] {
        player.playNextQueue.enumerated().map {
            QueueEntry(id: "pn-\($0.offset)", index: $0.offset, song: $0.element)
        }
    }

    private var albumEntries: [QueueEntry] {
        let start = player.currentIndex + 1
        guard start < player.queue.count else { return [] }
        return player.queue[start...].enumerated().map { offset, item in
            QueueEntry(id: "alb-\(start + offset)", index: start + offset, song: item.song)
        }
    }

    private var userQueueEntries: [QueueEntry] {
        player.userQueue.enumerated().map {
            QueueEntry(id: "uq-\($0.offset)", index: $0.offset, song: $0.element)
        }
    }

    private var hasUpcoming: Bool {
        if player.isShuffled {
            return player.currentIndex + 1 < player.queue.count
        }
        return !player.playNextQueue.isEmpty
            || player.currentIndex + 1 < player.queue.count
            || !player.userQueue.isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(tr("Queue", "Warteschlange")).font(.headline)
                Spacer()
                if hasUpcoming {
                    Button(tr("Clear", "Leeren")) { showClearConfirm = true }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)

            Divider()

            if !hasUpcoming {
                VStack(spacing: 10) {
                    Image(systemName: "list.bullet").font(.title2).foregroundStyle(.tertiary)
                    Text(tr("No upcoming tracks", "Keine weiteren Titel")).font(.callout).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    if player.isShuffled {
                        queueSection(tr("Shuffled Queue", "Gemischte Warteschlange"), entries: albumEntries,
                            onTap:   { player.jumpToAlbumTrack(at: $0.index) },
                            onDelete: { player.removeFromQueue(at: $0.index) },
                            onMove:  { player.moveInAlbumQueue(from: $0, to: $1) })
                    } else {
                        queueSection(tr("Play Next", "Als nächstes"), entries: playNextEntries,
                            onTap:   { player.jumpToPlayNextTrack(at: $0.index) },
                            onDelete: { player.removeFromPlayNextQueue(at: $0.index) },
                            onMove:  { player.moveInPlayNextQueue(from: $0, to: $1) })

                        queueSection(tr("Up Next", "Nächste Titel"), entries: albumEntries,
                            onTap:   { player.jumpToAlbumTrack(at: $0.index) },
                            onDelete: { player.removeFromQueue(at: $0.index) },
                            onMove:  { player.moveInAlbumQueue(from: $0, to: $1) })

                        queueSection(tr("Your Queue", "Deine Warteschlange"), entries: userQueueEntries,
                            onTap:   { player.jumpToUserQueueTrack(at: $0.index) },
                            onDelete: { player.removeFromUserQueue(at: $0.index) },
                            onMove:  { player.moveInUserQueue(from: $0, to: $1) })
                    }
                }
                .listStyle(.inset)
            }
        }
        .alert(tr("Clear Queue?", "Warteschlange leeren?"), isPresented: $showClearConfirm) {
            Button(tr("Clear", "Leeren"), role: .destructive) {
                player.clearAllQueues()
            }
            Button(tr("Cancel", "Abbrechen"), role: .cancel) {}
        } message: {
            Text(tr(
                "All upcoming songs will be removed from the queue.",
                "Alle kommenden Songs werden aus der Warteschlange entfernt."
            ))
        }
    }

    @ViewBuilder
    private func queueSection(
        _ title: String,
        entries: [QueueEntry],
        onTap: @escaping (QueueEntry) -> Void,
        onDelete: @escaping (QueueEntry) -> Void,
        onMove: @escaping (IndexSet, Int) -> Void
    ) -> some View {
        if !entries.isEmpty {
            Section(title) {
                ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                    QueueSongRow(
                        song: entry.song,
                        canMoveUp: index > 0,
                        canMoveDown: index < entries.count - 1,
                        onMoveUp: { onMove(IndexSet(integer: index), index - 1) },
                        onMoveDown: { onMove(IndexSet(integer: index), index + 2) },
                        onDelete: { onDelete(entry) }
                    )
                    .onTapGesture { onTap(entry) }
                }
            }
        }
    }
}

struct QueueSongRow: View {
    let song: Song
    var canMoveUp: Bool = false
    var canMoveDown: Bool = false
    var onMoveUp: () -> Void = {}
    var onMoveDown: () -> Void = {}
    var onDelete: (() -> Void)? = nil

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 10) {
            CoverArtView(
                url: song.coverArt.flatMap { SubsonicAPIService.shared.coverArtURL(id: $0, size: 80) },
                size: 36,
                cornerRadius: 4
            )
            VStack(alignment: .leading, spacing: 2) {
                Text(song.title).font(.callout).lineLimit(1)
                if let artist = song.artist {
                    Text(artist).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Spacer()
            if isHovered {
                HStack(spacing: 2) {
                    Button { onMoveUp() } label: {
                        Image(systemName: "chevron.up")
                            .font(.caption2.bold())
                            .frame(width: 22, height: 22)
                    }
                    .buttonStyle(.borderless)
                    .disabled(!canMoveUp)
                    Button { onMoveDown() } label: {
                        Image(systemName: "chevron.down")
                            .font(.caption2.bold())
                            .frame(width: 22, height: 22)
                    }
                    .buttonStyle(.borderless)
                    .disabled(!canMoveDown)
                    if let onDelete {
                        Button { onDelete() } label: {
                            Image(systemName: "trash")
                                .font(.caption2.bold())
                                .frame(width: 22, height: 22)
                                .foregroundStyle(.red)
                        }
                        .buttonStyle(.borderless)
                    }
                }
            }
            Text(song.durationString).font(.caption2).foregroundStyle(.tertiary).monospacedDigit()
        }
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
    }
}

struct AVRoutePickerViewRepresentable: NSViewRepresentable {
    func makeNSView(context: Context) -> AVRoutePickerView { AVRoutePickerView() }
    func updateNSView(_ nsView: AVRoutePickerView, context: Context) {}
}

#Preview {
    PlayerBarView()
        .environmentObject(AppState.shared)
        .environmentObject(LibraryViewModel())
        .frame(width: 1000)
}
