import SwiftUI
import Combine

@MainActor
class LibraryViewModel: ObservableObject {
    @Published var albums: [Album] = []
    @Published var artists: [Artist] = []
    @Published var sortOption: LibrarySortOption = .name
    @Published var isLoadingAlbums: Bool = false
    @Published var isLoadingArtists: Bool = false
    @Published var errorMessage: String?

    private let api = SubsonicAPIService.shared

    // MARK: - Albums

    func loadAlbums() async {
        guard !isLoadingAlbums else { return }
        isLoadingAlbums = true
        errorMessage = nil
        do {
            let type: AlbumListType = switch sortOption {
            case .name: .alphabeticalByName
            case .mostPlayed: .frequent
            case .recentlyAdded: .newest
            case .year: .alphabeticalByName
            }
            // Subsonic API liefert max. 500 pro Anfrage → paginieren
            var all: [Album] = []
            let pageSize = 500
            var offset = 0
            while true {
                let page = try await api.getAlbumList(type: type, size: pageSize, offset: offset)
                all.append(contentsOf: page)
                if page.count < pageSize { break }
                offset += pageSize
            }
            albums = all
            if sortOption == .year {
                albums = albums.sorted { ($0.year ?? 0) > ($1.year ?? 0) }
            }
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoadingAlbums = false
    }

    // MARK: - Artists

    func loadArtists() async {
        guard !isLoadingArtists else { return }
        isLoadingArtists = true
        errorMessage = nil
        do {
            artists = try await api.getAllArtists()
            artists = artists.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoadingArtists = false
    }

    func applySortToAlbums() {
        switch sortOption {
        case .name:
            albums = albums.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        case .mostPlayed:
            albums = albums.sorted { ($0.playCount ?? 0) > ($1.playCount ?? 0) }
        case .recentlyAdded:
            break // already sorted by server
        case .year:
            albums = albums.sorted { ($0.year ?? 0) > ($1.year ?? 0) }
        }
    }
}
