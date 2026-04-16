import SwiftUI

struct PlaylistDetailView: View {
    let playlist: Playlist
    @EnvironmentObject var libraryStore: LibraryViewModel
    @EnvironmentObject var appState: AppState
    @AppStorage("enableFavorites") private var enableFavorites = true
    @AppStorage("enablePlaylists") private var enablePlaylists = true
    @Environment(\.themeColor) private var themeColor

    @State private var detail: PlaylistDetail?
    @State private var songs: [Song] = []
    @State private var isLoading = true
    @State private var showRenameAlert = false
    @State private var newName = ""
    @State private var showDeleteConfirm = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {

                HStack(alignment: .top, spacing: 24) {
                    CoverArtView(
                        url: playlist.coverArt.flatMap { SubsonicAPIService.shared.coverArtURL(id: $0, size: 320) },
                        size: 160,
                        cornerRadius: 12
                    )
                    .shadow(color: .black.opacity(0.25), radius: 14)

                    VStack(alignment: .leading, spacing: 8) {
                        Text(playlist.name)
                            .font(.title.bold())
                            .lineLimit(2)

                        if let comment = playlist.comment, !comment.isEmpty {
                            Text(comment)
                                .font(.body)
                                .foregroundStyle(.secondary)
                        }

                        HStack(spacing: 10) {
                            if let count = playlist.songCount {
                                Text(tr("\(count) Tracks", "\(count) Titel"))
                            }
                            if let dur = playlist.duration, dur > 0 {
                                Text("·")
                                Text(formatDuration(dur))
                            }
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.top, 2)

                        Spacer(minLength: 12)

                        HStack(spacing: 10) {
                            Button {
                                if !songs.isEmpty { appState.player.play(songs: songs) }
                            } label: {
                                Label(tr("Play", "Abspielen"), systemImage: "play.fill")
                                    .frame(minWidth: 110)
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(themeColor)
                            .controlSize(.large)
                            .disabled(isLoading || songs.isEmpty)

                            Button {
                                if !songs.isEmpty { appState.player.playShuffled(songs: songs) }
                            } label: {
                                Label(tr("Shuffle", "Zufall"), systemImage: "shuffle")
                                    .frame(minWidth: 100)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.large)
                            .disabled(isLoading || songs.isEmpty)
                        }
                    }

                    Spacer()
                }
                .padding(28)

                Divider()
                    .padding(.horizontal, 28)
                    .padding(.bottom, 8)

                if isLoading {
                    ProgressView(tr("Loading tracks…", "Titel laden…"))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 60)
                } else if songs.isEmpty {
                    ContentUnavailableView(
                        tr("Empty Playlist", "Leere Wiedergabeliste"),
                        systemImage: "music.note.list",
                        description: Text(tr("Add songs to this playlist.", "Füge Titel zu dieser Wiedergabeliste hinzu."))
                    )
                    .padding(.vertical, 40)
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(songs.enumerated()), id: \.element.id) { index, song in
                            PlaylistTrackRow(
                                song: song,
                                index: index,
                                isPlaying: appState.player.currentSong?.id == song.id,
                                showFavorite: enableFavorites,
                                showPlaylist: enablePlaylists,
                                isStarred: libraryStore.isSongStarred(song),
                                themeColor: themeColor
                            ) {
                                appState.player.play(songs: songs, startIndex: index)
                            } onPlayNext: {
                                appState.player.addPlayNext(song)
                            } onAddToQueue: {
                                appState.player.addToUserQueue(song)
                            } onFavorite: {
                                Task { await libraryStore.toggleStarSong(song) }
                            } onAddToPlaylist: {
                                NotificationCenter.default.post(name: .addSongsToPlaylist, object: [song.id])
                            } onRemoveFromPlaylist: {
                                let songId = song.id
                                Task {
                                    await libraryStore.removeSongsFromPlaylist(playlist, indices: [index])
                                    songs.removeAll { $0.id == songId }
                                }
                            }
                        }
                    }
                    .padding(.bottom, 20)
                }
            }
        }
        .navigationTitle(playlist.name)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    newName = playlist.name
                    showRenameAlert = true
                } label: {
                    Label(tr("Rename", "Umbenennen"), systemImage: "pencil")
                }
                .help(tr("Rename Playlist", "Wiedergabeliste umbenennen"))

                Button(role: .destructive) {
                    showDeleteConfirm = true
                } label: {
                    Label(tr("Delete", "Löschen"), systemImage: "trash")
                }
                .help(tr("Delete Playlist", "Wiedergabeliste löschen"))
                .tint(.red)
            }
        }
        .alert(tr("Rename Playlist", "Wiedergabeliste umbenennen"), isPresented: $showRenameAlert) {
            TextField(tr("Name", "Name"), text: $newName)
            Button(tr("Rename", "Umbenennen")) {
                let name = newName.trimmingCharacters(in: .whitespaces)
                guard !name.isEmpty else { return }
                Task { await libraryStore.renamePlaylist(playlist, newName: name) }
            }
            Button(tr("Cancel", "Abbrechen"), role: .cancel) { }
        }
        .alert(tr("Delete Playlist?", "Wiedergabeliste löschen?"), isPresented: $showDeleteConfirm) {
            Button(tr("Delete", "Löschen"), role: .destructive) {
                Task {
                    await libraryStore.deletePlaylist(playlist)
                    appState.selectedPlaylist = nil
                }
            }
            Button(tr("Cancel", "Abbrechen"), role: .cancel) { }
        } message: {
            Text(tr("This action cannot be undone.", "Diese Aktion kann nicht rückgängig gemacht werden."))
        }
        .task {
            await loadDetail()
        }
        .refreshable {
            await loadDetail()
        }
    }

    private func loadDetail() async {
        isLoading = true
        if let loaded = await libraryStore.loadPlaylistDetail(id: playlist.id) {
            detail = loaded
            songs = loaded.songs ?? []
        }
        isLoading = false
    }

    private func formatDuration(_ seconds: Int) -> String {
        let m = seconds / 60
        let s = seconds % 60
        return "\(m):\(String(format: "%02d", s)) min"
    }
}

struct PlaylistTrackRow: View {
    let song: Song
    let index: Int
    let isPlaying: Bool
    var showFavorite: Bool = false
    var showPlaylist: Bool = false
    var isStarred: Bool = false
    let themeColor: Color
    let onPlay: () -> Void
    let onPlayNext: () -> Void
    let onAddToQueue: () -> Void
    let onFavorite: () -> Void
    let onAddToPlaylist: () -> Void
    let onRemoveFromPlaylist: () -> Void

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 0) {
            Group {
                if isPlaying {
                    Image(systemName: "waveform")
                        .foregroundStyle(themeColor)
                        .symbolEffect(.variableColor.iterative)
                } else {
                    Text("\(index + 1)")
                        .foregroundStyle(.tertiary)
                }
            }
            .font(.callout)
            .frame(width: 36, alignment: .trailing)
            .padding(.leading, 20)

            VStack(alignment: .leading, spacing: 2) {
                Text(song.title)
                    .font(.body)
                    .foregroundStyle(isPlaying ? themeColor : .primary)
                    .fontWeight(isPlaying ? .semibold : .regular)
                    .lineLimit(1)
                if let artist = song.artist {
                    Text(artist)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .padding(.leading, 14)

            Spacer()

            Text(song.durationString)
                .font(.callout)
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .padding(.trailing, 24)
        }
        .frame(height: 52)
        .background {
            Color(NSColor.windowBackgroundColor)
            if isHovered {
                Color.primary.opacity(0.07)
            } else if isPlaying {
                themeColor.opacity(0.08)
            }
        }
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .gesture(TapGesture(count: 2).onEnded { onPlay() })
        .contextMenu {
            Button(tr("Play", "Abspielen")) { onPlay() }
            Divider()
            Button(tr("Play Next", "Als nächstes abspielen")) { onPlayNext() }
            Button(tr("Add to Queue", "Zur Warteschlange hinzufügen")) { onAddToQueue() }
            Divider()
            Button(tr("Remove from Playlist", "Aus Wiedergabeliste entfernen"), role: .destructive) {
                onRemoveFromPlaylist()
            }
            if showFavorite || showPlaylist {
                Divider()
                if showFavorite {
                    Button(isStarred
                           ? tr("Remove from Favorites", "Aus Favoriten entfernen")
                           : tr("Add to Favorites", "Zu Favoriten hinzufügen")) {
                        onFavorite()
                    }
                }
                if showPlaylist {
                    Button(tr("Add to Playlist…", "Zur Wiedergabeliste hinzufügen…")) {
                        onAddToPlaylist()
                    }
                }
            }
        }
    }
}
