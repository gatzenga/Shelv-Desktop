import SwiftUI

struct RecapDetailView: View {
    let entry: RecapRegistryRecord
    let serverId: String

    @ObservedObject private var libraryStore = LibraryViewModel.shared
    @ObservedObject private var downloadStore = DownloadStore.shared
    @ObservedObject private var offlineMode = OfflineModeService.shared
    @Environment(\.themeColor) private var themeColor
    @Environment(\.dismiss) private var dismiss
    @AppStorage("enableFavorites") private var enableFavorites = true
    @AppStorage("enablePlaylists") private var enablePlaylists = true
    @AppStorage("enableDownloads") private var enableDownloads = false
    @State private var songs: [SongWithCount] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var showDeleteRecapConfirm = false
    @State private var showDeleteDownloadConfirm = false

    private struct SongWithCount: Identifiable {
        let id: String
        let song: Song
        let playCount: Int
        let originalRank: Int
    }

    private var period: RecapPeriod {
        let type = RecapPeriod.PeriodType(rawValue: entry.periodType) ?? .week
        return RecapPeriod(
            type: type,
            start: Date(timeIntervalSince1970: entry.periodStart),
            end: Date(timeIntervalSince1970: entry.periodEnd)
        )
    }

    var body: some View {
        Group {
            if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let err = errorMessage {
                VStack(spacing: 16) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 40))
                        .foregroundStyle(.secondary)
                    Text(err)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, 32)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if songs.isEmpty {
                ContentUnavailableView(
                    tr("No Songs", "Keine Titel"),
                    systemImage: "music.note",
                    description: Text(tr("No songs found for this period.", "Keine Titel für diesen Zeitraum gefunden."))
                )
            } else {
                List {
                    Section {
                        HStack(spacing: 10) {
                            Button {
                                AudioPlayerService.shared.play(songs: songs.map { $0.song }, startIndex: 0)
                            } label: {
                                Label(tr("Play", "Abspielen"), systemImage: "play.fill")
                                    .frame(minWidth: 100)
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(themeColor)
                            .controlSize(.large)

                            Button {
                                AudioPlayerService.shared.playShuffled(songs: songs.map { $0.song })
                            } label: {
                                Label(tr("Shuffle", "Zufällig"), systemImage: "shuffle")
                                    .frame(minWidth: 100)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.large)

                            if enableDownloads {
                                recapDownloadContentButtons
                            }
                        }
                        .listRowInsets(EdgeInsets(top: 12, leading: 12, bottom: 8, trailing: 12))
                        .listRowSeparator(.hidden)
                    }

                    ForEach(Array(songs.enumerated()), id: \.element.id) { idx, entry in
                        Button {
                            AudioPlayerService.shared.play(
                                songs: songs.map { $0.song },
                                startIndex: idx
                            )
                        } label: {
                            songRow(rank: entry.originalRank, entry: entry)
                        }
                        .buttonStyle(.plain)
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(top: 4, leading: 12, bottom: 4, trailing: 12))
                        .contextMenu {
                            Button(tr("Play", "Abspielen")) {
                                AudioPlayerService.shared.play(songs: songs.map { $0.song }, startIndex: idx)
                            }
                            Divider()
                            Button(tr("Play Next", "Als nächstes abspielen")) {
                                AudioPlayerService.shared.addPlayNext(entry.song)
                                NotificationCenter.default.post(name: .showToast, object: tr("Added to Play Next", "Als nächstes hinzugefügt"))
                            }
                            Button(tr("Add to Queue", "Zur Warteschlange hinzufügen")) {
                                AudioPlayerService.shared.addToUserQueue(entry.song)
                                NotificationCenter.default.post(name: .showToast, object: tr("Added to Queue", "Zur Warteschlange hinzugefügt"))
                            }
                            if enableFavorites || enablePlaylists {
                                Divider()
                                if enableFavorites {
                                    Button(tr("Add to Favorites", "Zu Favoriten hinzufügen")) {
                                        Task { await libraryStore.toggleStarSong(entry.song) }
                                    }
                                }
                                if enablePlaylists {
                                    Button(tr("Add to Playlist…", "Zur Playlist hinzufügen…")) {
                                        NotificationCenter.default.post(name: .addSongsToPlaylist, object: [entry.song.id])
                                    }
                                }
                            }
                        }
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
        .navigationTitle(period.playlistName)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button(tr("Play Next", "Als nächstes")) {
                        AudioPlayerService.shared.addPlayNext(songs.map { $0.song })
                        NotificationCenter.default.post(name: .showToast, object: tr("Added to Play Next", "Als nächstes hinzugefügt"))
                    }
                    .disabled(songs.isEmpty)
                    Button(tr("Add to Queue", "Zur Warteschlange")) {
                        AudioPlayerService.shared.addToUserQueue(songs.map { $0.song })
                        NotificationCenter.default.post(name: .showToast, object: tr("Added to Queue", "Zur Warteschlange hinzugefügt"))
                    }
                    .disabled(songs.isEmpty)
                    Divider()
                    Button(tr("Delete Recap", "Recap löschen"), role: .destructive) {
                        showDeleteRecapConfirm = true
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .disabled(isLoading)
            }
        }
        .task { await load() }
        .alert(tr("Delete Downloads?", "Downloads löschen?"), isPresented: $showDeleteDownloadConfirm) {
            Button(tr("Delete", "Löschen"), role: .destructive) {
                let allSongs = songs.map { $0.song }
                for song in allSongs {
                    downloadStore.deleteSong(song.id)
                }
                downloadStore.unmarkPlaylistDownloaded(id: entry.playlistId)
                NotificationCenter.default.post(name: .showToast, object: tr("Downloads deleted", "Downloads gelöscht"))
            }
            Button(tr("Cancel", "Abbrechen"), role: .cancel) {}
        } message: {
            Text(tr("The downloads will be removed from this device.", "Die Downloads werden von diesem Gerät entfernt."))
        }
        .alert(tr("Delete Recap?", "Recap löschen?"), isPresented: $showDeleteRecapConfirm) {
            Button(tr("Delete", "Löschen"), role: .destructive) {
                Task {
                    do {
                        try await RecapStore.shared.deleteEntry(playlistId: entry.playlistId, serverId: serverId)
                        dismiss()
                    } catch {
                        if !(error is CancellationError) {
                            NotificationCenter.default.post(name: .showToast, object: tr("Could not delete recap", "Recap konnte nicht gelöscht werden"))
                        }
                    }
                }
            }
            Button(tr("Cancel", "Abbrechen"), role: .cancel) {}
        } message: {
            Text(period.playlistName)
        }
    }

    private func songRow(rank: Int, entry: SongWithCount) -> some View {
        let isTop3 = rank <= 3
        return HStack(spacing: 12) {
            Text("\(rank)")
                .font(isTop3 ? .title3.bold() : .callout.bold())
                .foregroundStyle(isTop3 ? AnyShapeStyle(themeColor) : AnyShapeStyle(.secondary))
                .monospacedDigit()
                .frame(width: 28, alignment: .trailing)

            CoverArtView(
                url: entry.song.coverArt.flatMap { SubsonicAPIService.shared.coverArtURL(id: $0, size: 100) },
                size: 44, cornerRadius: 6
            )
            .overlay {
                NowPlayingOverlay(songId: entry.song.id, size: 44, cornerRadius: 6)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(entry.song.title)
                    .font(isTop3 ? .body.bold() : .body)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                if let artist = entry.song.artist {
                    Text(artist)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
            if enableDownloads {
                DownloadStatusIcon(songId: entry.song.id)
            }
            HStack(spacing: 3) {
                Image(systemName: "play.fill").font(.caption2)
                Text("\(entry.playCount)").font(.caption.monospacedDigit())
            }
            .foregroundStyle(isTop3 ? AnyShapeStyle(themeColor) : AnyShapeStyle(.secondary))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background((isTop3 ? themeColor : Color.secondary).opacity(0.12))
            .clipShape(Capsule())
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(isTop3 ? themeColor.opacity(0.08) : Color(NSColor.controlBackgroundColor))
        )
        .overlay {
            if isTop3 {
                RoundedRectangle(cornerRadius: 12)
                    .stroke(themeColor.opacity(0.25), lineWidth: 1)
            }
        }
    }

    @ViewBuilder
    private var recapDownloadContentButtons: some View {
        let isMarked = downloadStore.downloadedPlaylistIds.contains(entry.playlistId)
        let totalCount = downloadStore.playlistSongIds[entry.playlistId]?.count ?? songs.count
        let downloadedCount = isMarked ? (downloadStore.playlistSongIds[entry.playlistId]?.filter { downloadStore.isDownloaded(songId: $0) }.count ?? 0) : 0
        let remaining = max(0, totalCount - downloadedCount)
        if !isMarked && !offlineMode.isOffline {
            Button {
                let allSongs = songs.map { $0.song }
                let missing = allSongs.filter { !downloadStore.isDownloaded(songId: $0.id) }
                if !missing.isEmpty { downloadStore.enqueueSongs(missing) }
                downloadStore.markPlaylistDownloaded(id: entry.playlistId, name: period.playlistName, songIds: allSongs.map(\.id))
                NotificationCenter.default.post(name: .showToast, object: tr("Download started", "Download gestartet"))
            } label: {
                Label(tr("Download", "Herunterladen"), systemImage: "arrow.down.circle")
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
        }
        if isMarked && remaining > 0 && !offlineMode.isOffline {
            Button {
                let allSongs = songs.map { $0.song }
                let missing = allSongs.filter { !downloadStore.isDownloaded(songId: $0.id) }
                if !missing.isEmpty { downloadStore.enqueueSongs(missing) }
                NotificationCenter.default.post(name: .showToast, object: tr("Download started", "Download gestartet"))
            } label: {
                Label(tr("Rest (\(remaining))", "Rest (\(remaining))"), systemImage: "arrow.down.circle")
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
        }
        if isMarked {
            Button {
                showDeleteDownloadConfirm = true
            } label: {
                Label(tr("Delete Downloads", "Downloads löschen"), systemImage: "arrow.down.circle")
                    .foregroundStyle(.red)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
        }
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }

        guard let playlist = await libraryStore.loadPlaylistDetail(id: entry.playlistId) else {
            errorMessage = tr("Playlist could not be loaded.", "Playlist konnte nicht geladen werden.")
            return
        }
        let playlistSongs = playlist.songs ?? []

        let counts = await PlayLogService.shared.topSongs(
            serverId: serverId,
            from: Date(timeIntervalSince1970: entry.periodStart),
            to: Date(timeIntervalSince1970: entry.periodEnd),
            limit: period.type.songLimit
        )
        let countMap = Dictionary(uniqueKeysWithValues: counts.map { ($0.songId, $0.count) })

        let ranked = playlistSongs.enumerated().map { (idx, song) in
            (rank: idx + 1, song: song, playCount: countMap[song.id] ?? 0)
        }
        let filtered = offlineMode.isOffline
            ? ranked.filter { downloadStore.isDownloaded(songId: $0.song.id) }
            : ranked
        songs = filtered.map { SongWithCount(id: $0.song.id, song: $0.song, playCount: $0.playCount, originalRank: $0.rank) }
    }
}
