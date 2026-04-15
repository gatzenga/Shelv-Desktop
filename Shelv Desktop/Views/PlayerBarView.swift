import SwiftUI
import AVKit

struct PlayerBarView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var libraryStore: LibraryViewModel
    // @ObservedObject direkt auf den Service: AppState.objectWillChange feuert bei Player-Änderungen NICHT.
    @ObservedObject private var player = AudioPlayerService.shared
    @Environment(\.themeColor) private var themeColor
    @AppStorage("enableFavorites") private var enableFavorites = true
    @AppStorage("enablePlaylists") private var enablePlaylists = true
    @State private var isDragging: Bool = false
    @State private var dragValue: Double = 0
    @State private var showQueue: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            Divider()
            HStack(spacing: 0) {
                // MARK: Left – Song Info
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
                    .overlay(alignment: .bottomTrailing) {
                        if player.isBuffering || player.isPlaying {
                            Circle()
                                .fill(player.isBuffering ? Color.orange : Color.green)
                                .frame(width: 10, height: 10)
                                .overlay(Circle().stroke(Color(NSColor.windowBackgroundColor), lineWidth: 2))
                                .offset(x: 3, y: 3)
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
                                        appState.navigationPath.append(
                                            Artist(id: id, name: name, albumCount: nil, coverArt: nil, starred: nil)
                                        )
                                    }
                                    .buttonStyle(.plain)
                                    .foregroundStyle(themeColor)
                                } else if let name = song.artist {
                                    Text(name).foregroundStyle(.secondary)
                                }
                                if song.artist != nil && song.album != nil {
                                    Text(" · ").foregroundStyle(.secondary)
                                }
                                if let id = song.albumId, let name = song.album {
                                    Button(name) {
                                        appState.navigationPath.append(
                                            Album(id: id, name: name, artist: song.artist,
                                                  artistId: song.artistId, coverArt: song.coverArt,
                                                  songCount: nil, duration: nil, year: nil,
                                                  genre: nil, starred: nil, playCount: nil)
                                        )
                                    }
                                    .buttonStyle(.plain)
                                    .foregroundStyle(themeColor)
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

                    // Favorites / Playlist buttons next to song info
                    if let song = player.currentSong {
                        HStack(spacing: 10) {
                            if enableFavorites {
                                let isStarred = libraryStore.isSongStarred(song)
                                Button {
                                    Task { await libraryStore.toggleStarSong(song) }
                                } label: {
                                    Image(systemName: isStarred ? "heart.fill" : "heart")
                                        .font(.body)
                                        .foregroundStyle(isStarred ? .red : .secondary)
                                }
                                .buttonStyle(.plain)
                                .help(isStarred
                                      ? tr("Remove from Favorites", "Aus Favoriten entfernen")
                                      : tr("Add to Favorites", "Zu Favoriten hinzufügen"))
                            }
                            if enablePlaylists {
                                Button {
                                    NotificationCenter.default.post(name: .addSongsToPlaylist, object: [song.id])
                                } label: {
                                    Image(systemName: "music.note.list")
                                        .font(.body)
                                        .foregroundStyle(.secondary)
                                }
                                .buttonStyle(.plain)
                                .help(tr("Add to Playlist…", "Zur Wiedergabeliste hinzufügen…"))
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 20)

                // MARK: Center – Transport + Progress
                VStack(spacing: 10) {
                    // Controls
                    HStack(spacing: 22) {
                        // Shuffle
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
                                if player.isBuffering {
                                    ProgressView()
                                        .controlSize(.regular)
                                        .tint(.white)
                                } else {
                                    Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                                        .foregroundStyle(.white)
                                        .font(.system(size: 17, weight: .semibold))
                                        .offset(x: player.isPlaying ? 0 : 1.5)
                                }
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
                        .disabled(player.repeatMode == .off && player.currentIndex >= player.queue.count - 1)

                        // Repeat
                        Button { player.cycleRepeatMode() } label: {
                            Image(systemName: player.repeatMode.systemImage)
                                .foregroundStyle(player.repeatMode == .off ? AnyShapeStyle(.primary.opacity(0.35)) : AnyShapeStyle(themeColor))
                        }
                        .buttonStyle(.plain)
                        .font(.title2)
                        .help(repeatHelpText)
                    }

                    // Seekbar + Time
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
                                // seek() setzt currentTime sofort → danach isDragging = false,
                                // sodass der Slider den neuen Wert liest und nicht bounct
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

                // MARK: Right – AirPlay + Volume + Queue
                HStack(spacing: 16) {
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

// MARK: - Queue Entry

// Prefixed IDs ("pn-0", "alb-3", "uq-1") prevent SwiftUI List ID collisions across sections.
// `index` is the position in the respective source array for all three queue types.
private struct QueueEntry: Identifiable {
    let id: String
    let index: Int
    let song: Song
}

// MARK: - Queue Popover

struct QueuePopover: View {
    @ObservedObject private var player = AudioPlayerService.shared

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
                    Button(tr("Clear", "Leeren")) { player.clearAllQueues() }
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

                        queueSection(tr("From this album", "Von diesem Album"), entries: albumEntries,
                            onTap:   { player.jumpToAlbumTrack(at: $0.index) },
                            onDelete: { player.removeFromQueue(at: $0.index) },
                            onMove:  { player.moveInAlbumQueue(from: $0, to: $1) })

                        queueSection(tr("Queue", "Warteschlange"), entries: userQueueEntries,
                            onTap:   { player.jumpToUserQueueTrack(at: $0.index) },
                            onDelete: { player.removeFromUserQueue(at: $0.index) },
                            onMove:  { player.moveInUserQueue(from: $0, to: $1) })
                    }
                }
                .listStyle(.inset)
            }
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
                ForEach(entries) { entry in
                    QueueSongRow(song: entry.song)
                        .onTapGesture { onTap(entry) }
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) { onDelete(entry) } label: {
                                Label(tr("Remove", "Entfernen"), systemImage: "trash")
                            }
                        }
                }
                .onMove { onMove($0, $1) }
            }
        }
    }
}

// MARK: - Queue Song Row

struct QueueSongRow: View {
    let song: Song

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
            Text(song.durationString).font(.caption2).foregroundStyle(.tertiary).monospacedDigit()
        }
        .contentShape(Rectangle())
    }
}

// MARK: - AirPlay Button

struct AVRoutePickerViewRepresentable: NSViewRepresentable {
    func makeNSView(context: Context) -> AVRoutePickerView {
        AVRoutePickerView()
    }
    func updateNSView(_ nsView: AVRoutePickerView, context: Context) {}
}

#Preview {
    PlayerBarView()
        .environmentObject(AppState.shared)
        .environmentObject(LibraryViewModel())
        .frame(width: 1000)
}
