import SwiftUI
import Combine

struct SearchView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var libraryStore: LibraryViewModel
    @StateObject private var vm = SearchViewModel()
    @FocusState private var isSearchFocused: Bool
    @AppStorage("enableFavorites") private var enableFavorites = true
    @AppStorage("enablePlaylists") private var enablePlaylists = true
    @State private var lyricsResults: [LyricsSearchResult] = []
    @State private var lyricsTask: Task<Void, Never>?

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField(tr("Search artists, albums, tracks…", "Künstler, Alben, Titel suchen…"), text: $vm.query)
                    .textFieldStyle(.plain)
                    .focused($isSearchFocused)
                    .onSubmit { Task { await vm.search() } }
                if !vm.query.isEmpty {
                    Button { vm.query = ""; vm.clearResults() } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(10)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
            .padding(16)

            Divider()

            if vm.isLoading {
                ProgressView(tr("Searching…", "Suchen…"))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if vm.isEmpty && lyricsResults.isEmpty && !vm.query.isEmpty {
                ContentUnavailableView.search(text: vm.query)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if vm.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 48))
                        .foregroundStyle(.secondary)
                    Text(tr("Enter a search term", "Suchbegriff eingeben"))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 28) {
                        if !vm.artists.isEmpty {
                            SearchSection(title: tr("Artists", "Künstler")) {
                                ForEach(vm.artists) { artist in
                                    NavigationLink(value: artist) {
                                        SearchArtistRow(artist: artist)
                                    }
                                    .buttonStyle(.plain)
                                    .artistContextMenu(artist)
                                }
                            }
                        }
                        if !vm.albums.isEmpty {
                            SearchSection(title: tr("Albums", "Alben")) {
                                ForEach(vm.albums) { album in
                                    NavigationLink(value: album) {
                                        SearchAlbumRow(album: album)
                                    }
                                    .buttonStyle(.plain)
                                    .albumContextMenu(album)
                                    .environmentObject(libraryStore)
                                }
                            }
                        }
                        if !vm.songs.isEmpty {
                            SearchSection(title: tr("Tracks", "Titel")) {
                                ForEach(vm.songs) { song in
                                    SearchSongRow(
                                        song: song,
                                        showFavorite: enableFavorites,
                                        showPlaylist: enablePlaylists,
                                        isStarred: libraryStore.isSongStarred(song)
                                    ) {
                                        let idx = vm.songs.firstIndex(where: { $0.id == song.id }) ?? 0
                                        appState.player.play(songs: vm.songs, startIndex: idx)
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
                        }
                        if !lyricsResults.isEmpty {
                            SearchSection(title: tr("Lyrics", "Lyrics")) {
                                ForEach(lyricsResults) { item in
                                    LyricsSearchRow(item: item, onPlay: { playLyricsResult(item) })
                                }
                            }
                        }
                    }
                    .padding(.vertical, 20)
                }
            }
        }
        .navigationTitle(tr("Search", "Suche"))
        .onAppear { isSearchFocused = true }
        .onChange(of: vm.query) { _, newValue in
            if newValue.count >= 2 {
                Task { await vm.search() }
                lyricsTask?.cancel()
                lyricsTask = Task { await performLyricsSearch(query: newValue) }
            } else {
                lyricsResults = []
                vm.clearResults()
            }
        }
    }

    private func performLyricsSearch(query: String) async {
        let serverId = appState.serverStore.activeServerID?.uuidString ?? ""
        guard !serverId.isEmpty else { return }
        var results = await LyricsService.shared.searchLyrics(text: query, serverId: serverId)
        guard !Task.isCancelled else { return }
        lyricsResults = results
        let missing = results.filter { $0.songTitle == nil }
        for item in missing {
            guard !Task.isCancelled else { return }
            guard let song = try? await SubsonicAPIService.shared.getSong(id: item.songId) else { continue }
            await LyricsService.shared.updateMetadata(
                songId: item.songId, serverId: serverId,
                title: song.title, artist: song.artist, coverArt: song.coverArt
            )
            if let idx = results.firstIndex(where: { $0.songId == item.songId }) {
                results[idx] = LyricsSearchResult(
                    songId: item.songId, songTitle: song.title,
                    artistName: song.artist, coverArt: song.coverArt,
                    snippet: item.snippet
                )
                lyricsResults = results
            }
        }
    }

    private func playLyricsResult(_ item: LyricsSearchResult) {
        Task {
            let serverId = appState.serverStore.activeServerID?.uuidString ?? ""
            if let song = try? await SubsonicAPIService.shared.getSong(id: item.songId) {
                appState.player.play(songs: [song], startIndex: 0)
                if (item.songTitle == nil || item.artistName == nil || item.coverArt == nil) && !serverId.isEmpty {
                    Task.detached(priority: .utility) {
                        await LyricsService.shared.updateMetadata(
                            songId: item.songId, serverId: serverId,
                            title: song.title, artist: song.artist, coverArt: song.coverArt
                        )
                    }
                }
            } else {
                let fallback = Song(
                    id: item.songId, title: item.songTitle ?? item.songId,
                    artist: item.artistName, artistId: nil, album: nil, albumId: nil,
                    coverArt: item.coverArt, duration: nil, track: nil, discNumber: nil,
                    year: nil, genre: nil, starred: nil, playCount: nil,
                    bitRate: nil, contentType: nil, suffix: nil
                )
                appState.player.play(songs: [fallback], startIndex: 0)
            }
        }
    }
}

struct SearchSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(.title3.bold())
                .padding(.horizontal, 20)
                .padding(.bottom, 8)
            content
        }
    }
}

struct SearchArtistRow: View {
    let artist: Artist
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 12) {
            CoverArtView(url: artist.coverArt.flatMap { SubsonicAPIService.shared.coverArtURL(id: $0, size: 50) }, size: 44, isCircle: true)
                .padding(.leading, 20)
            VStack(alignment: .leading) {
                Text(artist.name).font(.callout.bold())
                if let count = artist.albumCount {
                    Text(tr("\(count) Albums", "\(count) Alben")).font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                .padding(.trailing, 20)
        }
        .padding(.vertical, 4)
        .background { if isHovered { Color.primary.opacity(0.07) } }
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
    }
}

struct SearchAlbumRow: View {
    let album: Album
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 12) {
            CoverArtView(url: album.coverArt.flatMap { SubsonicAPIService.shared.coverArtURL(id: $0, size: 50) }, size: 44, cornerRadius: 6)
                .padding(.leading, 20)
            VStack(alignment: .leading) {
                Text(album.name).font(.callout.bold())
                if let artist = album.artist { Text(artist).font(.caption).foregroundStyle(.secondary) }
            }
            Spacer()
            if let year = album.year { Text(String(year)).font(.caption).foregroundStyle(.tertiary) }
            Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                .padding(.trailing, 20)
        }
        .padding(.vertical, 4)
        .background { if isHovered { Color.primary.opacity(0.07) } }
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
    }
}

struct SearchSongRow: View {
    let song: Song
    var showFavorite: Bool = false
    var showPlaylist: Bool = false
    var isStarred: Bool = false
    let onPlay: () -> Void
    var onPlayNext: (() -> Void)? = nil
    var onAddToQueue: (() -> Void)? = nil
    var onFavorite: (() -> Void)? = nil
    var onAddToPlaylist: (() -> Void)? = nil

    @Environment(\.themeColor) private var themeColor
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 12) {
            CoverArtView(url: song.coverArt.flatMap { SubsonicAPIService.shared.coverArtURL(id: $0, size: 50) }, size: 44, cornerRadius: 6)
                .padding(.leading, 20)
            VStack(alignment: .leading) {
                Text(song.title).font(.callout.bold())
                if let artist = song.artist { Text(artist).font(.caption).foregroundStyle(.secondary) }
            }
            Spacer()
            Text(song.durationString).font(.caption).foregroundStyle(.tertiary).monospacedDigit()
            Button { onPlay() } label: {
                Image(systemName: "play.circle")
                    .font(.title2)
                    .foregroundStyle(themeColor)
            }
            .buttonStyle(.plain)
            .padding(.trailing, 20)
        }
        .padding(.vertical, 4)
        .background { if isHovered { Color.primary.opacity(0.07) } }
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .onTapGesture(count: 2) { onPlay() }
        .contextMenu {
            Button(tr("Play", "Abspielen")) { onPlay() }
            Divider()
            if let onPlayNext {
                Button(tr("Play Next", "Als nächstes abspielen")) { onPlayNext() }
            }
            if let onAddToQueue {
                Button(tr("Add to Queue", "Zur Warteschlange hinzufügen")) { onAddToQueue() }
            }
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
        }
    }
}

@MainActor
class SearchViewModel: ObservableObject {
    @Published var query: String = ""
    @Published var artists: [Artist] = []
    @Published var albums: [Album] = []
    @Published var songs: [Song] = []
    @Published var isLoading: Bool = false

    private let api = SubsonicAPIService.shared
    private var searchTask: Task<Void, Never>?

    var isEmpty: Bool { artists.isEmpty && albums.isEmpty && songs.isEmpty }

    func search() async {
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        searchTask?.cancel()
        searchTask = Task {
            isLoading = true
            do {
                let result = try await api.search(query: query)
                guard !Task.isCancelled else { return }
                artists = (result.artist ?? []).filter { ($0.albumCount ?? 0) > 0 }
                albums = result.album ?? []
                songs = result.song ?? []
            } catch {
                guard !Task.isCancelled else { return }
                NotificationCenter.default.post(name: .showToast, object: tr("Search failed", "Suche fehlgeschlagen"))
            }
            isLoading = false
        }
        await searchTask?.value
    }

    func clearResults() {
        artists = []
        albums = []
        songs = []
    }
}

struct LyricsSearchRow: View {
    let item: LyricsSearchResult
    let onPlay: () -> Void
    @Environment(\.themeColor) private var themeColor
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 12) {
            CoverArtView(
                url: item.coverArt.flatMap { SubsonicAPIService.shared.coverArtURL(id: $0, size: 80) },
                size: 44, cornerRadius: 6
            )
            .padding(.leading, 20)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.songTitle ?? tr("Unknown Song", "Unbekannter Titel"))
                    .font(.callout.bold())
                    .foregroundStyle(item.songTitle != nil ? Color.primary : Color.secondary)
                    .lineLimit(1)
                if let artist = item.artistName {
                    Text(artist)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Text(item.snippet)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .italic()
            }
            Spacer()
            Button { onPlay() } label: {
                Image(systemName: "play.circle")
                    .font(.title2)
                    .foregroundStyle(themeColor)
            }
            .buttonStyle(.plain)
            .padding(.trailing, 20)
        }
        .padding(.vertical, 4)
        .background { if isHovered { Color.primary.opacity(0.07) } }
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .onTapGesture(count: 2) { onPlay() }
    }
}

#Preview {
    SearchView()
        .frame(width: 700, height: 600)
        .environmentObject(AppState.shared)
        .environmentObject(LibraryViewModel())
}
