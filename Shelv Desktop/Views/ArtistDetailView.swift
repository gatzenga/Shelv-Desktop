import SwiftUI
import Combine

struct ArtistDetailView: View {
    let artistId: String
    let artistName: String
    @StateObject private var vm = ArtistDetailViewModel()
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var libraryStore: LibraryViewModel
    @AppStorage("enableFavorites") private var enableFavorites = true
    @Environment(\.themeColor) private var themeColor

    var body: some View {
        Group {
            if vm.isLoading {
                ProgressView(tr("Loading albums…", "Alben laden…"))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        HStack(alignment: .top, spacing: 24) {
                            CoverArtView(url: coverURL, size: 120, cornerRadius: 60)
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
                            LazyVGrid(
                                columns: [GridItem(.adaptive(minimum: 150, maximum: 190), spacing: 16)],
                                spacing: 20
                            ) {
                                ForEach(vm.albums) { album in
                                    NavigationLink(value: album) {
                                        AlbumGridItem(album: album)
                                    }
                                    .buttonStyle(.plain)
                                    .albumContextMenu(album)
                                }
                            }
                            .padding(.horizontal, 24)
                            .padding(.bottom, 24)
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
