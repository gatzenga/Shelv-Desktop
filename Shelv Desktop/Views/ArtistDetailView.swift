import SwiftUI
import Combine

struct ArtistDetailView: View {
    let artistId: String
    let artistName: String
    @StateObject private var vm = ArtistDetailViewModel()
    @EnvironmentObject var appState: AppState

    var body: some View {
        Group {
            if vm.isLoading {
                ProgressView("Alben laden…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        // Header
                        HStack(alignment: .center, spacing: 20) {
                            CoverArtView(url: coverURL, size: 120, cornerRadius: 60)
                                .shadow(color: .black.opacity(0.2), radius: 10)
                            VStack(alignment: .leading, spacing: 6) {
                                Text(vm.artist?.name ?? artistName)
                                    .font(.title.bold())
                                if let count = vm.artist?.albumCount {
                                    Text("\(count) Alben")
                                        .foregroundStyle(.secondary)
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
        .task { await vm.load(artistId: artistId) }
    }

    private var coverURL: URL? {
        guard let id = vm.artist?.coverArt else { return nil }
        return SubsonicAPIService.shared.coverArtURL(id: id, size: 240)
    }
}

// MARK: - ViewModel

@MainActor
class ArtistDetailViewModel: ObservableObject {
    @Published var artist: ArtistDetail?
    @Published var albums: [Album] = []
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?

    private let api = SubsonicAPIService.shared

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
}

#Preview {
    NavigationStack {
        ArtistDetailView(artistId: "1", artistName: "Vorschau Künstler")
    }
    .frame(width: 700, height: 550)
    .environmentObject(AppState.shared)
}
