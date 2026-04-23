import SwiftUI
import Combine

@MainActor
class LibraryViewModel: ObservableObject {
    static let shared = LibraryViewModel()

    @Published var albums: [Album] = []
    @Published var artists: [Artist] = []
    @Published var sortOption: LibrarySortOption = .name
    @Published var albumSortDirection: SortDirection = .ascending
    @Published var artistSortOption: ArtistSortOption = .name
    @Published var artistSortDirection: SortDirection = .ascending
    @Published var isLoadingAlbums: Bool = false
    @Published var isLoadingArtists: Bool = false
    @Published var errorMessage: String?

    var sortedAlbums: [Album] {
        // Name immer A-Z, unabhängig von direction
        if sortOption == .name { return albums }
        return albumSortDirection == sortOption.naturalDirection
            ? albums
            : Array(albums.reversed())
    }

    var sortedArtists: [Artist] {
        let base: [Artist]
        switch artistSortOption {
        case .name:
            return artists.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        case .mostPlayed:
            let counts = Dictionary(grouping: albums, by: { $0.artistId ?? "" })
                .mapValues { $0.compactMap { $0.playCount }.reduce(0, +) }
            base = artists.sorted { (counts[$0.id] ?? 0) > (counts[$1.id] ?? 0) }
        }
        return artistSortDirection == artistSortOption.naturalDirection
            ? base
            : Array(base.reversed())
    }

    // MARK: - Favorites
    @Published var starredSongs: [Song] = []
    @Published var starredAlbums: [Album] = []
    @Published var starredArtists: [Artist] = []
    @Published var isLoadingStarred: Bool = false

    // MARK: - Playlists
    @Published var playlists: [Playlist] = []
    @Published var isLoadingPlaylists: Bool = false

    private let api = SubsonicAPIService.shared

    // MARK: - Reset (bei Serverwechsel)

    func reset() {
        albums = []
        artists = []
        starredSongs = []
        starredAlbums = []
        starredArtists = []
        playlists = []
        errorMessage = nil
    }

    // MARK: - Albums

    func loadAlbums() async {
        guard !isLoadingAlbums else { return }
        guard !OfflineModeService.shared.isOffline else { isLoadingAlbums = false; return }
        isLoadingAlbums = true
        errorMessage = nil
        do {
            // "year" und "mostPlayed" client-seitig sortieren, damit auch Alben ohne
            // Plays/Jahr in der Liste erscheinen. "recentlyAdded" bleibt serverseitig.
            let type: AlbumListType
            switch sortOption {
            case .name, .year, .mostPlayed: type = .alphabeticalByName
            case .recentlyAdded:            type = .newest
            }
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
            } else if sortOption == .mostPlayed {
                albums = albums.sorted { ($0.playCount ?? 0) > ($1.playCount ?? 0) }
            }
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoadingAlbums = false
    }

    private func reconcileDownloadedAlbums(serverAlbumIds: Set<String>) async {
        guard let stableId = AppState.shared.serverStore.activeServer?.stableId, !stableId.isEmpty else { return }
        let downloadedAlbumIds = await DownloadDatabase.shared.allAlbumIds(serverId: stableId)
        let missing = downloadedAlbumIds.subtracting(serverAlbumIds)
        for albumId in missing {
            await DownloadService.shared.deleteAlbum(albumId: albumId, serverId: stableId)
        }
    }

    // MARK: - Artists

    func loadArtists() async {
        guard !isLoadingArtists else { return }
        guard !OfflineModeService.shared.isOffline else {
            let map = Dictionary(uniqueKeysWithValues: DownloadStore.shared.artists.compactMap { a -> (String, String)? in
                guard let cover = a.coverArtId else { return nil }
                return (a.name, cover)
            })
            if !map.isEmpty {
                NotificationCenter.default.post(name: .libraryArtistsLoaded, object: map)
            }
            isLoadingArtists = false
            return
        }
        isLoadingArtists = true
        errorMessage = nil
        do {
            artists = try await api.getAllArtists()
            artists = artists.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            let map = Dictionary(uniqueKeysWithValues: artists.compactMap { artist -> (String, String)? in
                guard let cover = artist.coverArt else { return nil }
                return (artist.name, cover)
            })
            NotificationCenter.default.post(name: .libraryArtistsLoaded, object: map)
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

    // MARK: - Starred / Favorites

    func loadStarred() async {
        guard !OfflineModeService.shared.isOffline else { isLoadingStarred = false; return }
        isLoadingStarred = true
        do {
            let result = try await api.getStarred()
            starredSongs = result.song ?? []
            starredAlbums = result.album ?? []
            starredArtists = result.artist ?? []
            if let stable = AppState.shared.serverStore.activeServer?.stableId, !stable.isEmpty {
                let starredIds = Set(starredSongs.map(\.id))
                await DownloadDatabase.shared.syncFavorites(serverId: stable, starredSongIds: starredIds)
                NotificationCenter.default.post(name: .downloadsLibraryChanged, object: nil)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoadingStarred = false
    }

    func isSongStarred(_ song: Song) -> Bool {
        starredSongs.contains { $0.id == song.id }
    }

    func isAlbumStarred(_ album: Album) -> Bool {
        starredAlbums.contains { $0.id == album.id }
    }

    func isArtistStarred(_ artist: Artist) -> Bool {
        starredArtists.contains { $0.id == artist.id }
    }

    func toggleStarSong(_ song: Song) async {
        let wasStarred = isSongStarred(song)
        // Optimistic update
        if wasStarred {
            starredSongs.removeAll { $0.id == song.id }
        } else {
            starredSongs.append(song)
        }
        do {
            if wasStarred {
                try await api.unstar(songId: song.id)
            } else {
                try await api.star(songId: song.id)
            }
        } catch {
            // Rollback
            if wasStarred {
                starredSongs.append(song)
            } else {
                starredSongs.removeAll { $0.id == song.id }
            }
            errorMessage = error.localizedDescription
        }
    }

    func toggleStarAlbum(_ album: Album) async {
        let wasStarred = isAlbumStarred(album)
        if wasStarred {
            starredAlbums.removeAll { $0.id == album.id }
        } else {
            starredAlbums.append(album)
        }
        do {
            if wasStarred {
                try await api.unstar(albumId: album.id)
            } else {
                try await api.star(albumId: album.id)
            }
        } catch {
            if wasStarred {
                starredAlbums.append(album)
            } else {
                starredAlbums.removeAll { $0.id == album.id }
            }
            errorMessage = error.localizedDescription
        }
    }

    func toggleStarArtist(_ artist: Artist) async {
        let wasStarred = isArtistStarred(artist)
        if wasStarred {
            starredArtists.removeAll { $0.id == artist.id }
        } else {
            starredArtists.append(artist)
        }
        do {
            if wasStarred {
                try await api.unstar(artistId: artist.id)
            } else {
                try await api.star(artistId: artist.id)
            }
        } catch {
            if wasStarred {
                starredArtists.append(artist)
            } else {
                starredArtists.removeAll { $0.id == artist.id }
            }
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Playlists

    func loadPlaylists() async {
        guard !OfflineModeService.shared.isOffline else { isLoadingPlaylists = false; return }
        isLoadingPlaylists = true
        do {
            playlists = try await api.getPlaylists()
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoadingPlaylists = false
    }

    func loadPlaylistDetail(id: String) async -> PlaylistDetail? {
        do {
            return try await api.getPlaylist(id: id)
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    func createPlaylist(name: String) async {
        do {
            let created = try await api.createPlaylist(name: name)
            playlists.append(created)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func deletePlaylist(_ playlist: Playlist) async {
        do {
            try await api.deletePlaylist(id: playlist.id)
            playlists.removeAll { $0.id == playlist.id }
            if let entry = await PlayLogService.shared.registryEntry(playlistId: playlist.id) {
                CloudKitSyncService.debugLog("[LibraryDelete] playlistId=\(playlist.id) was recap, deleting marker=\(entry.ckRecordName ?? "nil")")
                if let ckName = entry.ckRecordName {
                    await CloudKitSyncService.shared.deleteRecapMarker(ckRecordName: ckName)
                }
                await PlayLogService.shared.deleteRegistryEntry(playlistId: playlist.id)
                NotificationCenter.default.post(name: .recapRegistryUpdated, object: nil)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func renamePlaylist(_ playlist: Playlist, newName: String) async {
        do {
            try await api.updatePlaylist(id: playlist.id, name: newName)
            if let idx = playlists.firstIndex(where: { $0.id == playlist.id }) {
                playlists[idx] = Playlist(id: playlist.id, name: newName, comment: playlist.comment,
                                          songCount: playlist.songCount, duration: playlist.duration,
                                          coverArt: playlist.coverArt)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func addSongsToPlaylist(_ playlist: Playlist, songIds: [String]) async {
        do {
            try await api.updatePlaylist(id: playlist.id, songIdsToAdd: songIds)
            // Refresh the playlist in the list
            if let refreshed = try? await api.getPlaylists() {
                playlists = refreshed
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func removeSongsFromPlaylist(_ playlist: Playlist, indices: [Int]) async {
        do {
            try await api.updatePlaylist(id: playlist.id, songIndicesToRemove: indices)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func syncPlaylistOrder(_ playlist: Playlist, songs: [Song]) async {
        // Remove all songs and re-add in desired order
        let count = songs.count
        guard count > 0 else { return }
        let removeIndices = Array(0..<count)
        do {
            try await api.updatePlaylist(id: playlist.id, songIndicesToRemove: removeIndices)
            try await api.updatePlaylist(id: playlist.id, songIdsToAdd: songs.map(\.id))
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
