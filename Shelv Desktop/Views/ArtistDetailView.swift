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
    @Environment(\.themeColor) private var themeColor

    private var sortOption: LibrarySortOption {
        LibrarySortOption(rawValue: sortRaw) ?? .recentlyAdded
    }

    private var direction: SortDirection {
        SortDirection(rawValue: directionRaw) ?? .descending
    }

    private var sortedAlbums: [Album] {
        switch sortOption {
        case .name:
            // Name immer A-Z, unabhängig von direction
            return vm.albums.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        case .mostPlayed:
            let base = vm.albums.sorted { ($0.playCount ?? 0) < ($1.playCount ?? 0) }
            return direction == .ascending ? base : Array(base.reversed())
        case .recentlyAdded:
            let base = vm.albums.sorted { ($0.created ?? "") < ($1.created ?? "") }
            return direction == .ascending ? base : Array(base.reversed())
        case .year:
            let base = vm.albums.sorted { ($0.year ?? 0) < ($1.year ?? 0) }
            return direction == .ascending ? base : Array(base.reversed())
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
                                        Task { await vm.playAll(player: appState.player, shuffle: false) }
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
                                    .disabled(vm.albums.isEmpty || vm.isLoadingSongs)

                                    Button {
                                        Task { await vm.playAll(player: appState.player, shuffle: true) }
                                    } label: {
                                        Label(tr("Shuffle", "Zufall"), systemImage: "shuffle")
                                            .frame(minWidth: 100)
                                    }
                                    .buttonStyle(.bordered)
                                    .controlSize(.large)
                                    .disabled(vm.albums.isEmpty || vm.isLoadingSongs)

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
                                    ForEach(LibrarySortOption.allCases, id: \.self) { opt in
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
                                    ForEach(sortedAlbums) { album in
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
                                    ForEach(sortedAlbums) { album in
                                        NavigationLink(value: album) {
                                            AlbumListRow(album: album)
                                        }
                                        .buttonStyle(.plain)
                                        .albumContextMenu(album)
                                        if album.id != sortedAlbums.last?.id {
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
        .task(id: artistId) { await vm.load(artistId: artistId) }
    }

    private var coverURL: URL? {
        guard let id = vm.artist?.coverArt else { return nil }
        return SubsonicAPIService.shared.coverArtURL(id: id, size: 240)
    }

    @ViewBuilder
    private func artistDownloadButton(for detail: ArtistDetail) -> some View {
        let artistModel = Artist(id: detail.id, name: detail.name,
                                 albumCount: detail.albumCount, coverArt: detail.coverArt,
                                 starred: nil)
        let downloaded = downloadStore.artists.first(where: { $0.name == detail.name })
        if let match = downloaded {
            Button {
                downloadStore.deleteArtist(match.artistId)
            } label: {
                Label { Text(tr("Delete Downloads", "Downloads löschen")) } icon: { DeleteDownloadIcon(tint: .red) }
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .tint(.red)
        } else if !offlineMode.isOffline {
            Button {
                downloadStore.enqueueArtist(artistModel)
            } label: {
                Label(tr("Download", "Herunterladen"), systemImage: "arrow.down.circle")
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
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

    func load(artistId: String) async {
        isLoading = true
        errorMessage = nil
        do {
            let detail = try await api.getArtist(id: artistId)
            artist = detail
            albums = detail.album.sorted { ($0.year ?? 0) > ($1.year ?? 0) }
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    func playAll(player: AudioPlayerService, shuffle: Bool) async {
        guard !albums.isEmpty else { return }
        isLoadingSongs = true
        do {
            var songs = try await withThrowingTaskGroup(of: [Song].self) { group in
                for album in albums {
                    group.addTask { try await SubsonicAPIService.shared.getAlbum(id: album.id).song }
                }
                var result: [Song] = []
                for try await albumSongs in group { result.append(contentsOf: albumSongs) }
                return result
            }
            if songs.count > maxSongs {
                songs = Array(songs.shuffled().prefix(maxSongs))
            }
            if shuffle {
                player.playShuffled(songs: songs)
            } else {
                player.play(songs: songs)
            }
        } catch {
            NotificationCenter.default.post(name: .showToast, object: tr("Playback failed", "Wiedergabe fehlgeschlagen"))
        }
        isLoadingSongs = false
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
