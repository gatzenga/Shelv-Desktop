import SwiftUI
import Combine

struct AlbumDetailView: View {
    let albumId: String
    let albumName: String
    @StateObject private var vm = AlbumDetailViewModel()
    @EnvironmentObject var appState: AppState
    @ObservedObject var libraryStore = LibraryViewModel.shared
    @ObservedObject var downloadStore = DownloadStore.shared
    @ObservedObject var offlineMode = OfflineModeService.shared
    @ObservedObject private var player = AudioPlayerService.shared
    @AppStorage("enableFavorites") private var enableFavorites = true
    @AppStorage("enablePlaylists") private var enablePlaylists = true
    @AppStorage("enableDownloads") private var enableDownloads = false
    @Environment(\.themeColor) private var themeColor

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {

                HStack(alignment: .top, spacing: 24) {
                    CoverArtView(url: coverURL, size: 160, cornerRadius: 12)
                        .shadow(color: .black.opacity(0.25), radius: 14)

                    VStack(alignment: .leading, spacing: 8) {
                        Text(vm.album?.name ?? albumName)
                            .font(.title.bold())
                            .lineLimit(2)

                        if let artist = vm.album?.artist {
                            if let artistId = vm.album?.artistId {
                                Button {
                                    appState.selectedPlaylist = nil
                                    appState.selectedSidebar = .artists
                                    appState.navigationPath = NavigationPath()
                                    appState.navigationPath.append(Artist(id: artistId, name: artist, albumCount: nil, coverArt: nil, starred: nil))
                                } label: {
                                    Text(artist)
                                        .font(.title3)
                                        .foregroundStyle(themeColor)
                                }
                                .buttonStyle(.plain)
                                .help(tr("Go to Artist", "Zum Künstler"))
                                .onHover { inside in
                                    if inside { NSCursor.pointingHand.push() } else { NSCursor.pop() }
                                }
                            } else {
                                Text(artist)
                                    .font(.title3)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        HStack(spacing: 10) {
                            if let year  = vm.album?.year     { Text(String(year)) }
                            if let genre = vm.album?.genre    { Text("·"); Text(genre) }
                            if let count = vm.album?.songCount { Text("·"); Text(tr("\(count) Tracks", "\(count) Titel")) }
                            if let dur   = vm.album?.duration  { Text("·"); Text(formatDuration(dur)) }
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.top, 2)

                        Spacer(minLength: 12)

                        HStack(spacing: 10) {
                            Button {
                                if let songs = vm.album?.song { appState.player.play(songs: songs) }
                            } label: {
                                Label(tr("Play", "Abspielen"), systemImage: "play.fill")
                                    .frame(minWidth: 110)
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(themeColor)
                            .controlSize(.large)
                            .disabled(vm.isLoading)

                            Button {
                                if let songs = vm.album?.song {
                                    appState.player.playShuffled(songs: songs)
                                }
                            } label: {
                                Label(tr("Shuffle", "Zufall"), systemImage: "shuffle")
                                    .frame(minWidth: 100)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.large)
                            .disabled(vm.isLoading)

                            if enableDownloads, let album = vm.album {
                                downloadHeaderButton(for: album)
                            }

                            if enableFavorites && !offlineMode.isOffline, let album = vm.album {
                                let albumModel = Album(id: album.id, name: album.name, artist: album.artist,
                                                       artistId: album.artistId, coverArt: album.coverArt,
                                                       songCount: album.songCount, duration: album.duration,
                                                       year: album.year, genre: album.genre,
                                                       starred: album.starred, playCount: nil,
                                                       created: nil)
                                let isStarred = libraryStore.isAlbumStarred(albumModel)
                                Button {
                                    Task { await libraryStore.toggleStarAlbum(albumModel) }
                                } label: {
                                    Image(systemName: isStarred ? "heart.fill" : "heart")
                                        .font(.title3)
                                        .foregroundStyle(isStarred ? .red : .secondary)
                                }
                                .buttonStyle(.plain)
                                .help(isStarred
                                      ? tr("Remove from Favorites", "Aus Favoriten entfernen")
                                      : tr("Add to Favorites", "Zu Favoriten hinzufügen"))
                            }
                        }
                    }

                    Spacer()
                }
                .padding(28)

                Divider()
                    .padding(.horizontal, 28)
                    .padding(.bottom, 8)

                if vm.isLoading {
                    ProgressView(tr("Loading tracks…", "Titel laden…"))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 60)
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(vm.songs.enumerated()), id: \.element.id) { index, song in
                            TrackRow(
                                song: song,
                                isPlaying: player.currentSong?.id == song.id,
                                showFavorite: enableFavorites,
                                showPlaylist: enablePlaylists,
                                isStarred: libraryStore.isSongStarred(song)
                            ) {
                                appState.player.play(songs: vm.songs, startIndex: index)
                            } onPlayNext: {
                                appState.player.addPlayNext(song)
                                NotificationCenter.default.post(name: .showToast, object: tr("Added to Play Next", "Als nächstes hinzugefügt"))
                            } onAddToQueue: {
                                appState.player.addToUserQueue(song)
                                NotificationCenter.default.post(name: .showToast, object: tr("Added to Queue", "Zur Warteschlange hinzugefügt"))
                            } onFavorite: {
                                Task { await libraryStore.toggleStarSong(song) }
                            } onAddToPlaylist: {
                                NotificationCenter.default.post(name: .addSongsToPlaylist, object: [song.id])
                            }
                        }
                    }
                    .padding(.bottom, 20)
                }

                if let err = vm.errorMessage {
                    Label(err, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.red)
                        .padding(28)
                }
            }
        }
        .navigationTitle(vm.album?.name ?? albumName)
        .task(id: albumId) {
            let local = downloadStore.albums.first(where: { $0.albumId == albumId })
            await vm.load(albumId: albumId, fallback: local)
        }
    }

    private var coverURL: URL? {
        let id = vm.album?.coverArt ?? albumId
        return SubsonicAPIService.shared.coverArtURL(id: id, size: 320)
    }

    private func formatDuration(_ seconds: Int) -> String {
        let m = seconds / 60
        let s = seconds % 60
        return "\(m):\(String(format: "%02d", s)) min"
    }

    @ViewBuilder
    private func downloadHeaderButton(for album: AlbumDetail) -> some View {
        let total = vm.songs.count
        let albumModel = Album(id: album.id, name: album.name, artist: album.artist,
                               artistId: album.artistId, coverArt: album.coverArt,
                               songCount: album.songCount, duration: album.duration,
                               year: album.year, genre: album.genre,
                               starred: album.starred, playCount: nil, created: nil)
        let status = downloadStore.albumDownloadStatus(albumId: album.id, totalSongs: total)
        switch status {
        case .none:
            if !offlineMode.isOffline {
                Button {
                    downloadStore.enqueueAlbum(albumModel)
                } label: {
                    Label(tr("Download", "Herunterladen"), systemImage: "arrow.down.circle")
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
            }
        case .partial:
            if !offlineMode.isOffline {
                Button {
                    downloadStore.enqueueAlbum(albumModel)
                } label: {
                    Label(tr("Rest", "Rest"), systemImage: "arrow.down.circle")
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
            }
            Button {
                downloadStore.deleteAlbum(album.id)
            } label: {
                Label(tr("Delete Downloads", "Downloads löschen"), systemImage: "arrow.down.circle")
                    .foregroundStyle(.red)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
        case .complete:
            Button {
                downloadStore.deleteAlbum(album.id)
            } label: {
                Label(tr("Delete Downloads", "Downloads löschen"), systemImage: "arrow.down.circle")
                    .foregroundStyle(.red)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
        }
    }
}

struct TrackRow: View {
    let song: Song
    let isPlaying: Bool
    var showFavorite: Bool = false
    var showPlaylist: Bool = false
    var isStarred: Bool = false
    let onPlay: () -> Void
    let onPlayNext: () -> Void
    let onAddToQueue: () -> Void
    var onFavorite: (() -> Void)? = nil
    var onAddToPlaylist: (() -> Void)? = nil

    @Environment(\.themeColor) private var themeColor
    @ObservedObject private var downloadStore = DownloadStore.shared
    @ObservedObject private var offlineMode = OfflineModeService.shared
    @AppStorage("enableDownloads") private var enableDownloads = false
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 0) {
            Group {
                if isPlaying {
                    Image(systemName: "waveform")
                        .foregroundStyle(themeColor)
                        .symbolEffect(.variableColor.iterative)
                } else {
                    Text(song.displayTrack)
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
            if showFavorite || showPlaylist {
                Divider()
                if showFavorite, let onFavorite {
                    Button(isStarred
                           ? tr("Remove from Favorites", "Aus Favoriten entfernen")
                           : tr("Add to Favorites", "Zu Favoriten hinzufügen")) {
                        onFavorite()
                    }
                }
                if showPlaylist, let onAddToPlaylist {
                    Button(tr("Add to Playlist…", "Zur Wiedergabeliste hinzufügen…")) {
                        onAddToPlaylist()
                    }
                }
            }
            if enableDownloads {
                Divider()
                if downloadStore.isDownloaded(songId: song.id) {
                    Button(role: .destructive) { downloadStore.deleteSong(song.id) } label: {
                        Label { Text(tr("Delete Download", "Download löschen")) } icon: { DeleteDownloadIcon(tint: .red) }
                    }
                } else if !offlineMode.isOffline {
                    Button(tr("Download", "Herunterladen")) {
                        downloadStore.enqueueSongs([song])
                    }
                }
            }
        }
    }
}

@MainActor
class AlbumDetailViewModel: ObservableObject {
    @Published var album: AlbumDetail?
    @Published var songs: [Song] = []
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?

    private let api = SubsonicAPIService.shared

    func load(albumId: String, fallback: DownloadedAlbum? = nil) async {
        isLoading = true
        errorMessage = nil
        if let fallback, OfflineModeService.shared.isOffline {
            populateFromLocal(fallback)
            isLoading = false
            return
        }
        do {
            let detail = try await api.getAlbum(id: albumId)
            album = detail
            songs = detail.song
        } catch {
            if let fallback {
                populateFromLocal(fallback)
            } else {
                errorMessage = error.localizedDescription
            }
        }
        isLoading = false
    }

    private func populateFromLocal(_ local: DownloadedAlbum) {
        let mapped = local.songs.map { $0.asSong() }
        songs = mapped
        album = AlbumDetail(
            id: local.albumId, name: local.title,
            artist: local.artistName, artistId: local.artistId,
            coverArt: local.coverArtId,
            songCount: local.songs.count,
            duration: local.songs.reduce(0) { $0 + ($1.duration ?? 0) },
            year: nil, genre: nil, starred: nil,
            song: mapped
        )
    }
}

#Preview {
    NavigationStack {
        AlbumDetailView(albumId: "1", albumName: "Vorschau Album")
    }
    .frame(width: 700, height: 600)
    .environmentObject(AppState.shared)
    .environmentObject(LibraryViewModel())
}
