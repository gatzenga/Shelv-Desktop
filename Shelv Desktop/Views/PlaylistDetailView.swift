import SwiftUI

struct PlaylistDetailView: View {
    let playlist: Playlist
    @ObservedObject var libraryStore = LibraryViewModel.shared
    @EnvironmentObject var appState: AppState
    @ObservedObject var downloadStore = DownloadStore.shared
    @ObservedObject var offlineMode = OfflineModeService.shared
    @AppStorage("enableFavorites") private var enableFavorites = true
    @AppStorage("enablePlaylists") private var enablePlaylists = true
    @AppStorage("enableDownloads") private var enableDownloads = false

    @ViewBuilder
    private var playlistDownloadButtons: some View {
        let isMarked = downloadStore.downloadedPlaylistIds.contains(playlist.id)
        if !isMarked && !offlineMode.isOffline {
            Button {
                let missing = songs.filter { !downloadStore.isDownloaded(songId: $0.id) }
                if !missing.isEmpty { downloadStore.enqueueSongs(missing) }
                downloadStore.markPlaylistDownloaded(id: playlist.id, name: playlist.name, songIds: songs.map { $0.id })
                NotificationCenter.default.post(name: .showToast, object: tr("Download started", "Download gestartet"))
            } label: {
                Label(tr("Download", "Herunterladen"), systemImage: "arrow.down.circle")
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
        }
        if isMarked {
            Button {
                for song in songs {
                    downloadStore.deleteSong(song.id)
                }
                downloadStore.unmarkPlaylistDownloaded(id: playlist.id)
            } label: {
                Label(tr("Delete Downloads", "Downloads löschen"), systemImage: "arrow.down.circle")
                    .foregroundStyle(.red)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
        }
    }
    @Environment(\.themeColor) private var themeColor

    @State private var detail: PlaylistDetail?
    @State private var songs: [Song] = []
    @State private var isLoading = true
    @State private var showDeleteConfirm = false
    @State private var isSyncingOrder = false
    @State private var isEditMode = false
    @State private var editName: String = ""
    @State private var editComment: String = ""
    @State private var displayName: String = ""
    @State private var displayComment: String = ""

    var body: some View {
        List {
            Section {
                headerView
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .moveDisabled(true)
                    .deleteDisabled(true)
            }

            PlaylistTracksList(
                playlist: playlist,
                songs: $songs,
                isLoading: isLoading,
                isEditMode: isEditMode,
                enableFavorites: enableFavorites,
                enablePlaylists: enablePlaylists,
                themeColor: themeColor,
                currentSongId: appState.player.currentSong?.id,
                libraryStore: libraryStore,
                onPlayAt: { index in appState.player.play(songs: songs, startIndex: index) },
                onPlayNext: { song in
                    appState.player.addPlayNext(song)
                    NotificationCenter.default.post(name: .showToast, object: tr("Added to Play Next", "Als nächstes hinzugefügt"))
                },
                onAddToQueue: { song in
                    appState.player.addToUserQueue(song)
                    NotificationCenter.default.post(name: .showToast, object: tr("Added to Queue", "Zur Warteschlange hinzugefügt"))
                },
                onRemoveAt: { index in removeSong(at: index) },
                onMove: moveSongs,
                onDelete: deleteSongs
            )
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .navigationTitle(displayName.isEmpty ? playlist.name : displayName)
        .toolbar(content: toolbarContent)
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
        .task(id: playlist.id) {
            displayName = playlist.name
            displayComment = playlist.comment ?? ""
            await loadDetail()
        }
        .onChange(of: offlineMode.isOffline) { _, _ in
            songs = []
            Task { await loadDetail() }
        }
        .onChange(of: downloadStore.songs.count) { _, _ in
            guard offlineMode.isOffline else { return }
            Task { await loadDetail() }
        }
        .refreshable {
            async let detail: Void = loadDetail()
            async let sync:   Void = CloudKitSyncService.shared.syncNow()
            _ = await (detail, sync)
        }
    }

    @ToolbarContentBuilder
    private func toolbarContent() -> some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Button {
                if isEditMode {
                    commitEdits()
                } else {
                    editName = displayName
                    editComment = displayComment
                }
                isEditMode.toggle()
            } label: {
                Label(
                    isEditMode ? tr("Done", "Fertig") : tr("Edit", "Bearbeiten"),
                    systemImage: isEditMode ? "checkmark" : "pencil"
                )
            }
            .help(isEditMode ? tr("Finish Editing", "Bearbeiten beenden") : tr("Edit Playlist", "Wiedergabeliste bearbeiten"))
            .disabled(isLoading)
        }
        ToolbarItem(placement: .primaryAction) {
            Button(role: .destructive) {
                showDeleteConfirm = true
            } label: {
                Label(tr("Delete", "Löschen"), systemImage: "trash")
            }
            .help(tr("Delete Playlist", "Wiedergabeliste löschen"))
            .tint(.red)
        }
    }

    @ViewBuilder
    private var headerView: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 24) {
                CoverArtView(
                    url: playlist.coverArt.flatMap { SubsonicAPIService.shared.coverArtURL(id: $0, size: 320) },
                    size: 160,
                    cornerRadius: 12
                )
                .shadow(color: .black.opacity(0.25), radius: 14)

                VStack(alignment: .leading, spacing: 8) {
                    if isEditMode {
                        TextField(tr("Name", "Name"), text: $editName)
                            .font(.title.bold())
                            .textFieldStyle(.roundedBorder)
                        TextField(tr("Comment (optional)", "Kommentar (optional)"), text: $editComment, axis: .vertical)
                            .font(.body)
                            .textFieldStyle(.roundedBorder)
                            .lineLimit(1...3)
                    } else {
                        Text(displayName)
                            .font(.title.bold())
                            .lineLimit(2)
                        if !displayComment.isEmpty {
                            Text(displayComment)
                                .font(.body)
                                .foregroundStyle(.secondary)
                        }
                    }

                    HStack(spacing: 10) {
                        Text(tr("\(songs.count) Tracks", "\(songs.count) Titel"))
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

                        if enableDownloads && !songs.isEmpty {
                            playlistDownloadButtons
                        }
                    }
                }

                Spacer()
            }
            .padding(28)

            Divider()
                .padding(.horizontal, 28)
                .padding(.bottom, 8)
        }
    }

    private func loadDetail() async {
        isLoading = true
        if let loaded = await libraryStore.loadPlaylistDetail(id: playlist.id) {
            detail = loaded
            let allSongs = loaded.songs ?? []
            songs = offlineMode.isOffline
                ? allSongs.filter { downloadStore.isDownloaded(songId: $0.id) }
                : allSongs
            displayName = loaded.name
            displayComment = loaded.comment ?? ""
        }
        if songs.isEmpty && !offlineMode.isOffline && downloadStore.downloadedPlaylistIds.contains(playlist.id) {
            let ids = downloadStore.playlistSongIds[playlist.id] ?? []
            songs = ids.compactMap { id in downloadStore.songs.first { $0.songId == id }?.asSong() }
        }
        if !offlineMode.isOffline && downloadStore.downloadedPlaylistIds.contains(playlist.id) {
            if songs.contains(where: { !downloadStore.isDownloaded(songId: $0.id) }) {
                downloadStore.unmarkPlaylistDownloaded(id: playlist.id)
            }
        }
        isLoading = false
    }

    private func moveSongs(from: IndexSet, to: Int) {
        songs.move(fromOffsets: from, toOffset: to)
        Task { await syncOrder() }
    }

    private func deleteSongs(at offsets: IndexSet) {
        Task {
            let indices = Array(offsets)
            await libraryStore.removeSongsFromPlaylist(playlist, indices: indices)
            songs.remove(atOffsets: offsets)
        }
    }

    private func removeSong(at index: Int) {
        guard songs.indices.contains(index) else { return }
        let songId = songs[index].id
        Task {
            await libraryStore.removeSongsFromPlaylist(playlist, indices: [index])
            songs.removeAll { $0.id == songId }
        }
    }

    private func commitEdits() {
        let name = editName.trimmingCharacters(in: .whitespaces)
        let comment = editComment.trimmingCharacters(in: .whitespaces)
        let nameChanged = !name.isEmpty && name != displayName
        let commentChanged = comment != displayComment
        guard nameChanged || commentChanged else { return }

        let newName = nameChanged ? name : displayName
        let newComment = commentChanged ? comment : displayComment
        displayName = newName
        displayComment = newComment

        Task {
            do {
                try await SubsonicAPIService.shared.updatePlaylist(
                    id: playlist.id,
                    name: nameChanged ? name : nil,
                    comment: commentChanged ? comment : nil
                )
                await libraryStore.loadPlaylists()
            } catch {
                NotificationCenter.default.post(
                    name: .showToast,
                    object: tr("Changes could not be saved", "Änderungen konnten nicht gespeichert werden")
                )
                await loadDetail()
            }
        }
    }

    private func syncOrder() async {
        guard !isSyncingOrder else { return }
        isSyncingOrder = true
        let newIds = songs.map(\.id)
        let allOldIndices = Array(0..<newIds.count)
        do {
            try await SubsonicAPIService.shared.updatePlaylist(
                id: playlist.id,
                songIdsToAdd: newIds,
                songIndicesToRemove: allOldIndices
            )
        } catch {
            NotificationCenter.default.post(
                name: .showToast,
                object: tr("Order could not be saved", "Reihenfolge konnte nicht gespeichert werden")
            )
            await loadDetail()
        }
        isSyncingOrder = false
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
    var isEditMode: Bool = false
    var canMoveUp: Bool = false
    var canMoveDown: Bool = false
    let onPlay: () -> Void
    let onPlayNext: () -> Void
    let onAddToQueue: () -> Void
    let onFavorite: () -> Void
    let onAddToPlaylist: () -> Void
    let onRemoveFromPlaylist: () -> Void
    var onMoveUp: () -> Void = {}
    var onMoveDown: () -> Void = {}

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 0) {
            Group {
                if isEditMode {
                    Image(systemName: "line.3.horizontal")
                        .foregroundStyle(.secondary)
                } else if isPlaying {
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

            CoverArtView(
                url: song.coverArt.flatMap { SubsonicAPIService.shared.coverArtURL(id: $0, size: 80) },
                size: 40,
                cornerRadius: 4
            )
            .padding(.leading, 14)

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
            .padding(.leading, 12)

            Spacer()

            if isEditMode {
                HStack(spacing: 4) {
                    Button { onMoveUp() } label: {
                        Image(systemName: "chevron.up")
                            .font(.body.bold())
                            .frame(width: 28, height: 28)
                    }
                    .buttonStyle(.bordered)
                    .disabled(!canMoveUp)

                    Button { onMoveDown() } label: {
                        Image(systemName: "chevron.down")
                            .font(.body.bold())
                            .frame(width: 28, height: 28)
                    }
                    .buttonStyle(.bordered)
                    .disabled(!canMoveDown)

                    Button(role: .destructive) { onRemoveFromPlaylist() } label: {
                        Image(systemName: "trash")
                            .font(.body)
                            .foregroundStyle(.red)
                            .frame(width: 28, height: 28)
                    }
                    .buttonStyle(.borderless)
                }
                .padding(.trailing, 12)
            }

            HStack(spacing: 8) {
                DownloadStatusIcon(songId: song.id)
                Text(song.durationString)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
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

struct PlaylistTracksList: View {
    let playlist: Playlist
    @Binding var songs: [Song]
    let isLoading: Bool
    let isEditMode: Bool
    let enableFavorites: Bool
    let enablePlaylists: Bool
    let themeColor: Color
    let currentSongId: String?
    @ObservedObject var libraryStore: LibraryViewModel
    let onPlayAt: (Int) -> Void
    let onPlayNext: (Song) -> Void
    let onAddToQueue: (Song) -> Void
    let onRemoveAt: (Int) -> Void
    let onMove: (IndexSet, Int) -> Void
    let onDelete: (IndexSet) -> Void

    var body: some View {
        if isLoading {
            ProgressView(tr("Loading tracks…", "Titel laden…"))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 60)
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                .moveDisabled(true)
                .deleteDisabled(true)
        } else if songs.isEmpty {
            ContentUnavailableView(
                tr("Empty Playlist", "Leere Wiedergabeliste"),
                systemImage: "music.note.list",
                description: Text(tr("Add songs to this playlist.", "Füge Titel zu dieser Wiedergabeliste hinzu."))
            )
            .padding(.vertical, 40)
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .moveDisabled(true)
            .deleteDisabled(true)
        } else {
            Section {
                ForEach(Array(songs.enumerated()), id: \.element.id) { index, song in
                    PlaylistTrackRow(
                        song: song,
                        index: index,
                        isPlaying: currentSongId == song.id,
                        showFavorite: enableFavorites,
                        showPlaylist: enablePlaylists,
                        isStarred: libraryStore.isSongStarred(song),
                        themeColor: themeColor,
                        isEditMode: isEditMode,
                        canMoveUp: index > 0,
                        canMoveDown: index < songs.count - 1,
                        onPlay: { onPlayAt(index) },
                        onPlayNext: { onPlayNext(song) },
                        onAddToQueue: { onAddToQueue(song) },
                        onFavorite: { Task { await libraryStore.toggleStarSong(song) } },
                        onAddToPlaylist: {
                            NotificationCenter.default.post(name: .addSongsToPlaylist, object: [song.id])
                        },
                        onRemoveFromPlaylist: { onRemoveAt(index) },
                        onMoveUp: { onMove(IndexSet(integer: index), index - 1) },
                        onMoveDown: { onMove(IndexSet(integer: index), index + 2) }
                    )
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                }
                .onMove(perform: isEditMode ? onMove : nil)
                .onDelete(perform: isEditMode ? onDelete : nil)
            }
        }
    }
}
