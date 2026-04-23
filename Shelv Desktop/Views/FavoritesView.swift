import SwiftUI

struct FavoritesView: View {
    @ObservedObject var libraryStore = LibraryViewModel.shared
    @EnvironmentObject var appState: AppState
    @ObservedObject var downloadStore = DownloadStore.shared
    @ObservedObject var offlineMode = OfflineModeService.shared
    @AppStorage("enablePlaylists") private var enablePlaylists = true
    @AppStorage("downloadsOnlyFilter") private var showDownloadsOnly: Bool = false
    @Environment(\.themeColor) private var themeColor

    private var effectiveShowDownloadsOnly: Bool {
        offlineMode.isOffline || showDownloadsOnly
    }

    private var visibleArtists: [Artist] {
        guard effectiveShowDownloadsOnly else { return libraryStore.starredArtists }
        let downloadedNames = Set(downloadStore.artists.map(\.name))
        return libraryStore.starredArtists.filter { downloadedNames.contains($0.name) }
    }

    private var visibleAlbums: [Album] {
        guard effectiveShowDownloadsOnly else { return libraryStore.starredAlbums }
        let downloadedIds = Set(downloadStore.albums.map(\.albumId))
        return libraryStore.starredAlbums.filter { downloadedIds.contains($0.id) }
    }

    private var visibleSongs: [Song] {
        guard effectiveShowDownloadsOnly else { return libraryStore.starredSongs }
        return libraryStore.starredSongs.filter { downloadStore.isDownloaded(songId: $0.id) }
    }

    var body: some View {
        ScrollView {
            if libraryStore.isLoadingStarred
                && visibleArtists.isEmpty
                && visibleAlbums.isEmpty
                && visibleSongs.isEmpty {
                ProgressView(tr("Loading favorites…", "Favoriten laden…"))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 60)
            } else if visibleArtists.isEmpty
                        && visibleAlbums.isEmpty
                        && visibleSongs.isEmpty {
                ContentUnavailableView(
                    tr("No Favorites", "Keine Favoriten"),
                    systemImage: "heart",
                    description: Text(tr("Mark tracks, albums and artists as favorites.",
                                        "Markiere Titel, Alben und Künstler als Favoriten."))
                )
                .padding(.vertical, 60)
            } else {
                VStack(alignment: .leading, spacing: 28) {
                    if !visibleArtists.isEmpty {
                        FavoritesSection(title: tr("Artists", "Künstler")) {
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 130, maximum: 170), spacing: 16)], spacing: 20) {
                                ForEach(visibleArtists) { artist in
                                    NavigationLink(value: artist) {
                                        ArtistGridItem(artist: artist)
                                    }
                                    .buttonStyle(.plain)
                                    .artistContextMenu(artist)
                                    .environmentObject(libraryStore)
                                }
                            }
                        }
                    }

                    if !visibleAlbums.isEmpty {
                        FavoritesSection(title: tr("Albums", "Alben")) {
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150, maximum: 190), spacing: 16)], spacing: 20) {
                                ForEach(visibleAlbums) { album in
                                    NavigationLink(value: album) {
                                        AlbumGridItem(album: album)
                                    }
                                    .buttonStyle(.plain)
                                    .albumContextMenu(album)
                                    .environmentObject(libraryStore)
                                }
                            }
                        }
                    }

                    if !visibleSongs.isEmpty {
                        FavoritesSection(title: tr("Tracks", "Titel")) {
                            VStack(spacing: 0) {
                                ForEach(Array(visibleSongs.enumerated()), id: \.element.id) { index, song in
                                    FavoriteSongRow(
                                        song: song,
                                        isPlaying: appState.player.currentSong?.id == song.id,
                                        showPlaylist: enablePlaylists,
                                        themeColor: themeColor
                                    ) {
                                        appState.player.play(songs: visibleSongs, startIndex: index)
                                    } onPlayNext: {
                                        appState.player.addPlayNext(song)
                                        NotificationCenter.default.post(name: .showToast, object: tr("Added to Play Next", "Als nächstes hinzugefügt"))
                                    } onAddToQueue: {
                                        appState.player.addToUserQueue(song)
                                        NotificationCenter.default.post(name: .showToast, object: tr("Added to Queue", "Zur Warteschlange hinzugefügt"))
                                    } onRemoveFavorite: {
                                        Task { await libraryStore.toggleStarSong(song) }
                                    } onAddToPlaylist: {
                                        NotificationCenter.default.post(name: .addSongsToPlaylist, object: [song.id])
                                    }
                                }
                            }
                        }
                    }
                }
                .padding(20)
            }
        }
        .navigationTitle(tr("Favorites", "Favoriten"))
        .task { await libraryStore.loadStarred() }
    }
}

struct FavoritesSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.title2.bold())
            content
        }
    }
}

struct FavoriteSongRow: View {
    let song: Song
    let isPlaying: Bool
    var showPlaylist: Bool = false
    let themeColor: Color
    let onPlay: () -> Void
    let onPlayNext: () -> Void
    let onAddToQueue: () -> Void
    let onRemoveFavorite: () -> Void
    let onAddToPlaylist: () -> Void

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 12) {
            CoverArtView(
                url: song.coverArt.flatMap { SubsonicAPIService.shared.coverArtURL(id: $0, size: 80) },
                size: 40,
                cornerRadius: 6
            )

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

            Spacer()

            if let album = song.album {
                Text(album)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .frame(maxWidth: 150, alignment: .trailing)
            }

            Text(song.durationString)
                .font(.callout)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .frame(height: 52)
        .padding(.horizontal, 12)
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
            Button(tr("Remove from Favorites", "Aus Favoriten entfernen")) { onRemoveFavorite() }
            if showPlaylist {
                Button(tr("Add to Playlist…", "Zur Wiedergabeliste hinzufügen…")) { onAddToPlaylist() }
            }
        }
    }
}
