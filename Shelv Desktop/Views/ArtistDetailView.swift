import SwiftUI
import Combine

struct ArtistDetailView: View {
    let artistId: String
    let artistName: String
    @StateObject private var vm = ArtistDetailViewModel()
    @EnvironmentObject var appState: AppState
    @ObservedObject var libraryStore = LibraryViewModel.shared
    @ObservedObject var downloadStore = DownloadStore.shared
    @ObservedObject private var offlineMode = OfflineModeService.shared
    @AppStorage("enableFavorites") private var enableFavorites = true
    @AppStorage("enableDownloads") private var enableDownloads = false
    @AppStorage("artistDetailAlbumSort") private var sortRaw: String = LibrarySortOption.recentlyAdded.rawValue
    @AppStorage("artistDetailAlbumDirection") private var directionRaw: String = SortDirection.descending.rawValue
    @AppStorage("artistDetailAlbumIsGrid") private var isGrid: Bool = true
    @AppStorage("downloadsOnlyFilter") private var showDownloadsOnly: Bool = false
    @Environment(\.themeColor) private var themeColor

    private var effectiveShowDownloadsOnly: Bool {
        offlineMode.isOffline || showDownloadsOnly
    }

    private var sortOption: LibrarySortOption {
        LibrarySortOption(rawValue: sortRaw) ?? .recentlyAdded
    }

    private var direction: SortDirection {
        SortDirection(rawValue: directionRaw) ?? .descending
    }

    private var displayAlbums: [Album] {
        let base: [Album]
        if effectiveShowDownloadsOnly {
            let downloadedIds = Set(downloadStore.albums.map { $0.albumId })
            base = vm.albums.filter { downloadedIds.contains($0.id) }
        } else {
            base = vm.albums
        }
        switch sortOption {
        case .name:
            return base.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        case .mostPlayed:
            let sorted = base.sorted { ($0.playCount ?? 0) < ($1.playCount ?? 0) }
            return direction == .ascending ? sorted : Array(sorted.reversed())
        case .recentlyAdded:
            let sorted = base.sorted { ($0.created ?? "") < ($1.created ?? "") }
            return direction == .ascending ? sorted : Array(sorted.reversed())
        case .year:
            let sorted = base.sorted { ($0.year ?? 0) < ($1.year ?? 0) }
            return direction == .ascending ? sorted : Array(sorted.reversed())
        }
    }

    var body: some View {
        Group {
            if vm.isLoading {
                ProgressView(tr("Loading albums…", "Alben laden…"))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        HStack(alignment: .top, spacing: 24) {
                            CoverArtView(url: coverURL, size: 120, isCircle: true)
                                .shadow(color: .black.opacity(0.2), radius: 10)

                            VStack(alignment: .leading, spacing: 8) {
                                Text(vm.artist?.name ?? artistName)
                                    .font(.title.bold())
                                if let count = vm.artist?.albumCount {
                                    Text(tr("\(count) Albums", "\(count) Alben"))
                                        .foregroundStyle(.secondary)
                                }

                                Spacer(minLength: 8)

                                HStack(spacing: 10) {
                                    Button {
                                        Task { await vm.playAll(player: appState.player, albums: displayAlbums, shuffle: false) }
                                    } label: {
                                        Group {
                                            if vm.isLoadingSongs {
                                                ProgressView().controlSize(.small).tint(.white)
                                            } else {
                                                Label(tr("Play", "Abspielen"), systemImage: "play.fill")
                                                    .frame(minWidth: 100)
                                            }
                                        }
                                    }
                                    .buttonStyle(.borderedProminent)
                                    .tint(themeColor)
                                    .controlSize(.large)
                                    .disabled(displayAlbums.isEmpty || vm.isLoadingSongs)

                                    Button {
                                        Task { await vm.playAll(player: appState.player, albums: displayAlbums, shuffle: true) }
                                    } label: {
                                        Label(tr("Shuffle", "Zufall"), systemImage: "shuffle")
                                            .frame(minWidth: 100)
                                    }
                                    .buttonStyle(.bordered)
                                    .controlSize(.large)
                                    .disabled(displayAlbums.isEmpty || vm.isLoadingSongs)

                                    Button {
                                        Task {
                                            let songs = await vm.fetchSongs(albums: displayAlbums)
                                            guard !songs.isEmpty else { return }
                                            appState.player.addPlayNext(songs)
                                            NotificationCenter.default.post(name: .showToast, object: tr("Added to Play Next", "Als nächstes hinzugefügt"))
                                        }
                                    } label: {
                                        Label(tr("Play Next", "Als nächstes"), systemImage: "text.insert")
                                    }
                                    .buttonStyle(.bordered)
                                    .controlSize(.large)
                                    .disabled(displayAlbums.isEmpty || vm.isLoadingSongs)

                                    Button {
                                        Task {
                                            let songs = await vm.fetchSongs(albums: displayAlbums)
                                            guard !songs.isEmpty else { return }
                                            appState.player.addToUserQueue(songs)
                                            NotificationCenter.default.post(name: .showToast, object: tr("Added to Queue", "Zur Warteschlange hinzugefügt"))
                                        }
                                    } label: {
                                        Label(tr("Add to Queue", "Zur Warteschlange"), systemImage: "text.badge.plus")
                                    }
                                    .buttonStyle(.bordered)
                                    .controlSize(.large)
                                    .disabled(displayAlbums.isEmpty || vm.isLoadingSongs)

                                    if enableDownloads, let detail = vm.artist {
                                        artistDownloadButton(for: detail)
                                    }

                                    if enableFavorites, let detail = vm.artist {
                                        let isStarred = libraryStore.starredArtists.contains { $0.id == detail.id }
                                        Button {
                                            Task {
                                                await libraryStore.toggleStarArtist(
                                                    Artist(id: detail.id, name: detail.name,
                                                           albumCount: detail.albumCount, coverArt: detail.coverArt,
                                                           starred: isStarred ? "1" : nil)
                                                )
                                            }
                                        } label: {
                                            Image(systemName: isStarred ? "heart.fill" : "heart")
                                                .font(.title2)
                                                .foregroundStyle(isStarred ? AnyShapeStyle(.red) : AnyShapeStyle(.secondary))
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
                        .padding(.horizontal, 24)
                        .padding(.top, 20)

                        if !vm.albums.isEmpty {
                            HStack(spacing: 8) {
                                Picker(tr("Sort", "Sortieren"), selection: $sortRaw) {
                                    ForEach(LibrarySortOption.allCases.filter { !offlineMode.isOffline || !$0.requiresServer }, id: \.self) { opt in
                                        Text(opt.label).tag(opt.rawValue)
                                    }
                                }
                                .pickerStyle(.menu)
                                .frame(width: 180)
                                if sortOption != .name {
                                    Button {
                                        directionRaw = direction == .ascending
                                            ? SortDirection.descending.rawValue
                                            : SortDirection.ascending.rawValue
                                    } label: {
                                        Image(systemName: direction == .ascending ? "arrow.up" : "arrow.down")
                                            .font(.title3)
                                    }
                                    .buttonStyle(.borderless)
                                    .help(direction == .ascending ? tr("Ascending", "Aufsteigend") : tr("Descending", "Absteigend"))
                                }
                                Spacer()
                                Button { isGrid.toggle() } label: {
                                    Image(systemName: isGrid ? "list.bullet" : "square.grid.2x2")
                                        .font(.title3)
                                }
                                .buttonStyle(.borderless)
                                .help(isGrid ? tr("List view", "Listenansicht") : tr("Grid view", "Rasteransicht"))
                            }
                            .padding(.horizontal, 20)

                            if isGrid {
                                LazyVGrid(
                                    columns: [GridItem(.adaptive(minimum: 160, maximum: 200), spacing: 16)],
                                    spacing: 20
                                ) {
                                    ForEach(displayAlbums) { album in
                                        NavigationLink(value: album) {
                                            AlbumGridItem(album: album)
                                        }
                                        .buttonStyle(.plain)
                                        .albumContextMenu(album)
                                    }
                                }
                                .padding(20)
                            } else {
                                LazyVStack(spacing: 0) {
                                    ForEach(displayAlbums) { album in
                                        NavigationLink(value: album) {
                                            AlbumListRow(album: album)
                                        }
                                        .buttonStyle(.plain)
                                        .albumContextMenu(album)
                                        if album.id != displayAlbums.last?.id {
                                            Divider().padding(.leading, 92)
                                        }
                                    }
                                }
                                .padding(.bottom, 24)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle(vm.artist?.name ?? artistName)
        .onChange(of: offlineMode.isOffline) { _, isOffline in
            if isOffline && sortOption.requiresServer {
                sortRaw = LibrarySortOption.name.rawValue
            }
            Task { await vm.load(artistId: artistId, artistName: artistName) }
        }
        .onChange(of: downloadStore.songs.count) { _, _ in
            guard offlineMode.isOffline else { return }
            Task { await vm.load(artistId: artistId, artistName: artistName) }
        }
        .task(id: artistId) { await vm.load(artistId: artistId, artistName: artistName) }
    }

    private var coverURL: URL? {
        guard let id = vm.artist?.coverArt else { return nil }
        return SubsonicAPIService.shared.coverArtURL(id: id, size: 240)
    }

    private var totalArtistSongs: Int {
        vm.albums.compactMap(\.songCount).reduce(0, +)
    }

    private var downloadedArtistSongs: Int {
        downloadStore.songs.filter { $0.artistName == artistName }.count
    }

    private var artistDownloadStatus: AlbumDownloadStatus {
        let total = totalArtistSongs
        let done = downloadedArtistSongs
        guard total > 0 else { return .none }
        if done == 0 { return .none }
        if done >= total { return .complete }
        return .partial(downloaded: done, total: total)
    }

    @ViewBuilder
    private func artistDownloadButton(for detail: ArtistDetail) -> some View {
        let artistModel = Artist(id: detail.id, name: detail.name,
                                 albumCount: detail.albumCount, coverArt: detail.coverArt,
                                 starred: nil)
        switch artistDownloadStatus {
        case .none:
            if !offlineMode.isOffline {
                Button {
                    downloadStore.enqueueArtist(artistModel)
                } label: {
                    Label(tr("Download", "Herunterladen"), systemImage: "arrow.down.circle")
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
            }
        case .partial(let done, let tot):
            if !offlineMode.isOffline {
                Button {
                    downloadStore.enqueueArtist(artistModel)
                } label: {
                    Label(tr("Rest (\(tot - done))", "Rest (\(tot - done))"), systemImage: "arrow.down.circle")
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
            }
            if let match = downloadStore.artists.first(where: { $0.name == detail.name }) {
                Button {
                    downloadStore.deleteArtist(match.artistId)
                } label: {
                    Label { Text(tr("Delete", "Löschen")) } icon: { DeleteDownloadIcon(tint: .red) }
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .tint(.red)
            }
        case .complete:
            if let match = downloadStore.artists.first(where: { $0.name == detail.name }) {
                Button {
                    downloadStore.deleteArtist(match.artistId)
                } label: {
                    Label { Text(tr("Delete Downloads", "Downloads löschen")) } icon: { DeleteDownloadIcon(tint: .red) }
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .tint(.red)
            }
        }
    }
}

@MainActor
class ArtistDetailViewModel: ObservableObject {
    @Published var artist: ArtistDetail?
    @Published var albums: [Album] = []
    @Published var isLoading: Bool = false
    @Published var isLoadingSongs: Bool = false
    @Published var errorMessage: String?

    private let api = SubsonicAPIService.shared
    private let maxSongs = 200

    func load(artistId: String, artistName: String) async {
        isLoading = true
        errorMessage = nil
        if OfflineModeService.shared.isOffline {
            populateFromLocal(artistId: artistId, artistName: artistName)
            isLoading = false
            return
        }
        do {
            let detail = try await api.getArtist(id: artistId)
            artist = detail
            albums = detail.album.sorted { ($0.year ?? 0) > ($1.year ?? 0) }
        } catch {
            populateFromLocal(artistId: artistId, artistName: artistName)
            if artist == nil { errorMessage = error.localizedDescription }
        }
        isLoading = false
    }

    private func populateFromLocal(artistId: String, artistName: String) {
        let local = DownloadStore.shared.artists.first(where: { $0.artistId == artistId })
            ?? DownloadStore.shared.artists.first(where: { $0.name == artistName })
        guard let local else { return }
        let albumsAsModel = local.albums.map { $0.asAlbum() }
        artist = ArtistDetail(id: local.artistId, name: local.name,
                              albumCount: albumsAsModel.count,
                              coverArt: local.coverArtId,
                              album: albumsAsModel)
        albums = albumsAsModel
    }

    func fetchSongs(albums: [Album]) async -> [Song] {
        guard !albums.isEmpty else { return [] }
        isLoadingSongs = true
        defer { isLoadingSongs = false }
        if OfflineModeService.shared.isOffline {
            let albumOrder = albums.map { $0.id }
            let albumIds = Set(albumOrder)
            let songsByAlbum = Dictionary(
                grouping: DownloadStore.shared.songs.filter { albumIds.contains($0.albumId) },
                by: { $0.albumId }
            )
            return albumOrder.flatMap { id in
                (songsByAlbum[id] ?? []).sorted { ($0.track ?? 0) < ($1.track ?? 0) }.map { $0.asSong() }
            }
        }
        do {
            let indexed = Array(albums.enumerated())
            return try await withThrowingTaskGroup(of: (Int, [Song]).self) { group in
                for (i, album) in indexed {
                    group.addTask {
                        let s = try await SubsonicAPIService.shared.getAlbum(id: album.id).song
                        return (i, s)
                    }
                }
                var results: [(Int, [Song])] = []
                for try await result in group { results.append(result) }
                return results.sorted { $0.0 < $1.0 }.flatMap { $0.1 }
            }
        } catch {
            NotificationCenter.default.post(name: .showToast, object: tr("Playback failed", "Wiedergabe fehlgeschlagen"))
            return []
        }
    }

    func playAll(player: AudioPlayerService, albums: [Album], shuffle: Bool) async {
        var songs = await fetchSongs(albums: albums)
        guard !songs.isEmpty else { return }
        if songs.count > maxSongs { songs = Array(songs.shuffled().prefix(maxSongs)) }
        if shuffle { player.playShuffled(songs: songs) } else { player.play(songs: songs) }
    }
}

#Preview {
    NavigationStack {
        ArtistDetailView(artistId: "1", artistName: "Vorschau Künstler")
    }
    .frame(width: 700, height: 550)
    .environmentObject(AppState.shared)
    .environmentObject(LibraryViewModel())
}
