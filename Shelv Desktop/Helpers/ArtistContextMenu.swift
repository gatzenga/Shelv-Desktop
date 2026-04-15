import SwiftUI

// MARK: - Artist Context Menu Modifier

struct ArtistContextMenuModifier: ViewModifier {
    let artist: Artist
    @EnvironmentObject var libraryStore: LibraryViewModel
    @AppStorage("enableFavorites") private var enableFavorites = false
    @AppStorage("enablePlaylists") private var enablePlaylists = false

    func body(content: Content) -> some View {
        content.contextMenu {
            Button(tr("Play", "Abspielen")) {
                Task {
                    guard let songs = await fetchSongs(), !songs.isEmpty else { return }
                    await MainActor.run { AudioPlayerService.shared.play(songs: songs) }
                }
            }
            Button(tr("Shuffle", "Zufällig abspielen")) {
                Task {
                    guard let songs = await fetchSongs(), !songs.isEmpty else { return }
                    await MainActor.run { AudioPlayerService.shared.playShuffled(songs: songs) }
                }
            }
            Divider()
            Button(tr("Play Next", "Als nächstes abspielen")) {
                Task {
                    guard let songs = await fetchSongs(), !songs.isEmpty else { return }
                    await MainActor.run { AudioPlayerService.shared.addPlayNext(songs) }
                }
            }
            Button(tr("Add to Queue", "Zur Warteschlange hinzufügen")) {
                Task {
                    guard let songs = await fetchSongs(), !songs.isEmpty else { return }
                    await MainActor.run { AudioPlayerService.shared.addToUserQueue(songs) }
                }
            }
            if enableFavorites || enablePlaylists {
                Divider()
                if enableFavorites {
                    Button(libraryStore.isArtistStarred(artist)
                           ? tr("Remove from Favorites", "Aus Favoriten entfernen")
                           : tr("Add to Favorites", "Zu Favoriten hinzufügen")) {
                        Task { await libraryStore.toggleStarArtist(artist) }
                    }
                }
                if enablePlaylists {
                    Button(tr("Add to Playlist…", "Zur Wiedergabeliste hinzufügen…")) {
                        Task {
                            guard let songs = await fetchSongs(), !songs.isEmpty else { return }
                            let ids = songs.map(\.id)
                            await MainActor.run {
                                NotificationCenter.default.post(name: .addSongsToPlaylist, object: ids)
                            }
                        }
                    }
                }
            }
        }
    }

    private func fetchSongs() async -> [Song]? {
        guard let detail = try? await SubsonicAPIService.shared.getArtist(id: artist.id) else { return nil }
        var songs: [Song] = []
        if let fetched = try? await withThrowingTaskGroup(of: [Song].self) { group -> [Song] in
            for album in detail.album {
                group.addTask { try await SubsonicAPIService.shared.getAlbum(id: album.id).song }
            }
            var result: [Song] = []
            for try await albumSongs in group { result.append(contentsOf: albumSongs) }
            return result
        } {
            songs = fetched
        }
        return songs
    }
}

extension View {
    func artistContextMenu(_ artist: Artist) -> some View {
        modifier(ArtistContextMenuModifier(artist: artist))
    }
}
