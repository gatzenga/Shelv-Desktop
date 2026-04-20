import SwiftUI

struct ArtistsView: View {
    @EnvironmentObject private var vm: LibraryViewModel
    @AppStorage("artistViewIsGrid") private var isGrid: Bool = true
    @State private var searchText: String = ""

    private var filteredArtists: [Artist] {
        let source = vm.sortedArtists
        if searchText.isEmpty { return source }
        return source.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                TextField(tr("Filter…", "Filtern…"), text: $searchText)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 220)
                Spacer()
                Picker(tr("Sort", "Sortieren"), selection: $vm.artistSortOption) {
                    ForEach(ArtistSortOption.allCases, id: \.self) { opt in
                        Text(opt.label).tag(opt)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 180)
                if vm.artistSortOption != .name {
                    Button {
                        vm.artistSortDirection = vm.artistSortDirection == .ascending ? .descending : .ascending
                    } label: {
                        Image(systemName: vm.artistSortDirection == .ascending ? "arrow.up" : "arrow.down")
                            .font(.title3)
                    }
                    .buttonStyle(.borderless)
                    .help(vm.artistSortDirection == .ascending ? tr("Ascending", "Aufsteigend") : tr("Descending", "Absteigend"))
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

            if vm.isLoadingArtists {
                ProgressView(tr("Loading artists…", "Künstler laden…"))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if filteredArtists.isEmpty && !vm.artists.isEmpty {
                ContentUnavailableView.search(text: searchText)
            } else if isGrid {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 140, maximum: 180), spacing: 16)], spacing: 20) {
                        ForEach(filteredArtists) { artist in
                            NavigationLink(value: artist) {
                                ArtistGridItem(artist: artist)
                            }
                            .buttonStyle(.plain)
                            .artistContextMenu(artist)
                        }
                    }
                    .padding(20)
                }
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(filteredArtists) { artist in
                            NavigationLink(value: artist) {
                                ArtistListRow(artist: artist)
                            }
                            .buttonStyle(.plain)
                            .artistContextMenu(artist)
                            if artist.id != filteredArtists.last?.id {
                                Divider().padding(.leading, 76)
                            }
                        }
                    }
                    .padding(.vertical, 8)
                }
            }

            if let err = vm.errorMessage {
                Label(err, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.red)
                    .padding()
            }
        }
        .navigationTitle(tr("Artists (\(vm.artists.count))", "Künstler (\(vm.artists.count))"))
        .task { await vm.loadArtists() }
    }
}

struct ArtistGridItem: View {
    let artist: Artist
    @State private var isHovered = false

    private var coverURL: URL? {
        guard let id = artist.coverArt else { return nil }
        return SubsonicAPIService.shared.coverArtURL(id: id, size: 160)
    }

    var body: some View {
        VStack(spacing: 6) {
            CoverArtView(url: coverURL, size: 140, isCircle: true)
                .shadow(color: .black.opacity(isHovered ? 0.3 : 0.12), radius: isHovered ? 10 : 4)
                .scaleEffect(isHovered ? 1.03 : 1.0)
                .animation(.easeInOut(duration: 0.15), value: isHovered)
            Text(artist.name)
                .font(.caption.bold())
                .lineLimit(2)
                .multilineTextAlignment(.center)
            if let count = artist.albumCount {
                Text(tr("\(count) Albums", "\(count) Alben"))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 140)
        .onHover { isHovered = $0 }
    }
}

struct ArtistListRow: View {
    let artist: Artist
    @State private var isHovered = false

    private var coverURL: URL? {
        guard let id = artist.coverArt else { return nil }
        return SubsonicAPIService.shared.coverArtURL(id: id, size: 120)
    }

    var body: some View {
        HStack(spacing: 12) {
            CoverArtView(url: coverURL, size: 52, isCircle: true)
            VStack(alignment: .leading, spacing: 2) {
                Text(artist.name)
                    .font(.body)
                    .lineLimit(1)
                if let count = artist.albumCount {
                    Text(tr("\(count) Albums", "\(count) Alben"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
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
    ArtistsView()
        .frame(width: 900, height: 700)
        .environmentObject(LibraryViewModel())
}
