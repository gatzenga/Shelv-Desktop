import SwiftUI
import Combine

struct SearchView: View {
    @EnvironmentObject var appState: AppState
    @StateObject private var vm = SearchViewModel()
    @FocusState private var isSearchFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            // Search bar
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Künstler, Alben, Titel suchen…", text: $vm.query)
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
                ProgressView("Suchen…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if vm.isEmpty && !vm.query.isEmpty {
                ContentUnavailableView.search(text: vm.query)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if vm.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 48))
                        .foregroundStyle(.secondary)
                    Text("Suchbegriff eingeben")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 28) {
                        // Artists
                        if !vm.artists.isEmpty {
                            SearchSection(title: "Künstler") {
                                ForEach(vm.artists) { artist in
                                    NavigationLink(value: artist) {
                                        SearchArtistRow(artist: artist)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                        // Albums
                        if !vm.albums.isEmpty {
                            SearchSection(title: "Alben") {
                                ForEach(vm.albums) { album in
                                    NavigationLink(value: album) {
                                        SearchAlbumRow(album: album)
                                    }
                                    .buttonStyle(.plain)
                                    .albumContextMenu(album)
                                }
                            }
                        }
                        // Songs
                        if !vm.songs.isEmpty {
                            SearchSection(title: "Titel") {
                                ForEach(vm.songs) { song in
                                    SearchSongRow(song: song) {
                                        let idx = vm.songs.firstIndex(where: { $0.id == song.id }) ?? 0
                                        appState.player.play(songs: vm.songs, startIndex: idx)
                                    }
                                }
                            }
                        }
                    }
                    .padding(20)
                }
            }
        }
        .navigationTitle("Suche")
        .onAppear { isSearchFocused = true }
        .onChange(of: vm.query) { _, newValue in
            if newValue.count >= 2 {
                Task { await vm.search() }
            }
        }
    }
}

// MARK: - Search Section

struct SearchSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.title3.bold())
            content
        }
    }
}

// MARK: - Result Rows

struct SearchArtistRow: View {
    let artist: Artist

    var body: some View {
        HStack(spacing: 12) {
            CoverArtView(url: SubsonicAPIService.shared.coverArtURL(id: artist.coverArt ?? "", size: 50), size: 44, cornerRadius: 22)
            VStack(alignment: .leading) {
                Text(artist.name).font(.callout.bold())
                if let count = artist.albumCount {
                    Text("\(count) Alben").font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            Image(systemName: "chevron.right").foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
}

struct SearchAlbumRow: View {
    let album: Album

    var body: some View {
        HStack(spacing: 12) {
            CoverArtView(url: SubsonicAPIService.shared.coverArtURL(id: album.coverArt ?? "", size: 50), size: 44, cornerRadius: 6)
            VStack(alignment: .leading) {
                Text(album.name).font(.callout.bold())
                if let artist = album.artist { Text(artist).font(.caption).foregroundStyle(.secondary) }
            }
            Spacer()
            if let year = album.year { Text(String(year)).font(.caption).foregroundStyle(.tertiary) }
            Image(systemName: "chevron.right").foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
}

struct SearchSongRow: View {
    let song: Song
    let onPlay: () -> Void

    @Environment(\.themeColor) private var themeColor

    var body: some View {
        HStack(spacing: 12) {
            CoverArtView(url: SubsonicAPIService.shared.coverArtURL(id: song.coverArt ?? "", size: 50), size: 44, cornerRadius: 6)
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
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { onPlay() }
    }
}

// MARK: - ViewModel

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
                artists = result.artist ?? []
                albums = result.album ?? []
                songs = result.song ?? []
            } catch { }
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

#Preview {
    SearchView()
        .frame(width: 700, height: 600)
        .environmentObject(AppState.shared)
}
