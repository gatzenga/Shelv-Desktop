import SwiftUI

struct AlbumsView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject private var vm: LibraryViewModel
    @AppStorage("albumViewIsGrid") private var isGrid: Bool = true
    @State private var searchText: String = ""

    private var filteredAlbums: [Album] {
        let source = vm.sortedAlbums
        if searchText.isEmpty { return source }
        return source.filter {
            $0.name.localizedCaseInsensitiveContains(searchText) ||
            ($0.artist?.localizedCaseInsensitiveContains(searchText) ?? false)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                TextField(tr("Filter…", "Filtern…"), text: $searchText)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 220)
                Spacer()
                Picker(tr("Sort", "Sortieren"), selection: $vm.sortOption) {
                    ForEach(LibrarySortOption.allCases, id: \.self) { opt in
                        Text(opt.label).tag(opt)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 180)
                .onChange(of: vm.sortOption) {
                    Task { await vm.loadAlbums() }
                }
                if vm.sortOption != .name {
                    Button {
                        vm.albumSortDirection = vm.albumSortDirection == .ascending ? .descending : .ascending
                    } label: {
                        Image(systemName: vm.albumSortDirection == .ascending ? "arrow.up" : "arrow.down")
                            .font(.title3)
                    }
                    .buttonStyle(.borderless)
                    .help(vm.albumSortDirection == .ascending ? tr("Ascending", "Aufsteigend") : tr("Descending", "Absteigend"))
                }
                Button { isGrid.toggle() } label: {
                    Image(systemName: isGrid ? "list.bullet" : "square.grid.2x2")
                        .font(.title3)
                }
                .buttonStyle(.borderless)
                .help(isGrid ? tr("List view", "Listenansicht") : tr("Grid view", "Rasteransicht"))
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            .background(.bar)

            Divider()

            if vm.isLoadingAlbums {
                ProgressView(tr("Loading albums…", "Alben laden…"))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if isGrid {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 160, maximum: 200), spacing: 16)], spacing: 20) {
                        ForEach(filteredAlbums) { album in
                            NavigationLink(value: album) {
                                AlbumGridItem(album: album)
                            }
                            .buttonStyle(.plain)
                            .albumContextMenu(album)
                        }
                    }
                    .padding(20)
                }
                .overlay {
                    if filteredAlbums.isEmpty && !vm.albums.isEmpty {
                        ContentUnavailableView.search(text: searchText)
                    }
                }
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(filteredAlbums) { album in
                            NavigationLink(value: album) {
                                AlbumListRow(album: album)
                            }
                            .buttonStyle(.plain)
                            .albumContextMenu(album)
                            if album.id != filteredAlbums.last?.id {
                                Divider().padding(.leading, 76)
                            }
                        }
                    }
                    .padding(.vertical, 8)
                }
                .overlay {
                    if filteredAlbums.isEmpty && !vm.albums.isEmpty {
                        ContentUnavailableView.search(text: searchText)
                    }
                }
            }

            if let err = vm.errorMessage {
                Label(err, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.red)
                    .padding()
            }
        }
        .navigationTitle(tr("Albums (\(vm.albums.count))", "Alben (\(vm.albums.count))"))
        .task { await vm.loadAlbums() }
    }
}

struct AlbumGridItem: View {
    let album: Album
    @State private var isHovered = false

    private var coverURL: URL? {
        guard let id = album.coverArt else { return nil }
        return SubsonicAPIService.shared.coverArtURL(id: id, size: 200)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            CoverArtView(url: coverURL, size: 160, cornerRadius: 8)
                .shadow(color: .black.opacity(isHovered ? 0.3 : 0.12), radius: isHovered ? 10 : 4)
                .scaleEffect(isHovered ? 1.03 : 1.0)
                .animation(.easeInOut(duration: 0.15), value: isHovered)
            Text(album.name)
                .font(.caption.bold())
                .lineLimit(1)
            if let artist = album.artist {
                Text(artist)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Text(album.year.map(String.init) ?? " ")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .frame(width: 160, alignment: .topLeading)
        .onHover { isHovered = $0 }
    }
}

struct AlbumListRow: View {
    let album: Album
    @State private var isHovered = false

    private var coverURL: URL? {
        guard let id = album.coverArt else { return nil }
        return SubsonicAPIService.shared.coverArtURL(id: id, size: 120)
    }

    var body: some View {
        HStack(spacing: 12) {
            CoverArtView(url: coverURL, size: 52, cornerRadius: 6)
            VStack(alignment: .leading, spacing: 2) {
                Text(album.name)
                    .font(.body)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    if let artist = album.artist {
                        Text(artist)
                            .lineLimit(1)
                    }
                    if album.artist != nil, album.year != nil {
                        Text("·").foregroundStyle(.tertiary)
                    }
                    if let year = album.year {
                        Text(String(year))
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            Color(NSColor.windowBackgroundColor)
            if isHovered {
                Color.primary.opacity(0.05)
            }
        }
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
    }
}

#Preview {
    AlbumsView()
        .frame(width: 900, height: 700)
        .environmentObject(AppState.shared)
        .environmentObject(LibraryViewModel())
}
