import SwiftUI

struct AlbumsView: View {
    @EnvironmentObject var appState: AppState
    @StateObject private var vm = LibraryViewModel()
    @State private var searchText: String = ""

    private var filteredAlbums: [Album] {
        if searchText.isEmpty { return vm.albums }
        return vm.albums.filter {
            $0.name.localizedCaseInsensitiveContains(searchText) ||
            ($0.artist?.localizedCaseInsensitiveContains(searchText) ?? false)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            HStack {
                TextField("Filter…", text: $searchText)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 220)
                Spacer()
                Picker("Sortieren", selection: $vm.sortOption) {
                    ForEach(LibrarySortOption.allCases, id: \.self) { opt in
                        Text(opt.rawValue).tag(opt)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 180)
                .onChange(of: vm.sortOption) {
                    Task { await vm.loadAlbums() }
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            .background(.bar)

            Divider()

            if vm.isLoadingAlbums {
                ProgressView("Alben laden…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
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
            }

            if let err = vm.errorMessage {
                Label(err, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.red)
                    .padding()
            }
        }
        .navigationTitle("Alben (\(vm.albums.count))")
        .task { await vm.loadAlbums() }
    }
}

// MARK: - Album Grid Item

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
            if let year = album.year {
                Text(String(year))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(width: 160)
        .onHover { isHovered = $0 }
    }
}

#Preview {
    AlbumsView()
        .frame(width: 900, height: 700)
}
