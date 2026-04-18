import SwiftUI

struct ArtistsView: View {
    @EnvironmentObject private var vm: LibraryViewModel
    @State private var searchText: String = ""

    private var filteredArtists: [Artist] {
        if searchText.isEmpty { return vm.artists }
        return vm.artists.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            HStack {
                TextField(tr("Filter…", "Filtern…"), text: $searchText)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 220)
                Spacer()
                Text(tr("\(vm.artists.count) Artists", "\(vm.artists.count) Künstler"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
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
            } else {
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
            }

            if let err = vm.errorMessage {
                Label(err, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.red)
                    .padding()
            }
        }
        .navigationTitle(tr("Artists", "Künstler"))
        .task { await vm.loadArtists() }
    }
}

// MARK: - Artist Grid Item

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

#Preview {
    ArtistsView()
        .frame(width: 900, height: 700)
        .environmentObject(LibraryViewModel())
}
