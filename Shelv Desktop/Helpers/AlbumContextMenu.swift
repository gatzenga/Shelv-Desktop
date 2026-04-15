import SwiftUI

// MARK: - Album Context Menu Modifier

struct AlbumContextMenuModifier: ViewModifier {
    let album: Album
    @EnvironmentObject var libraryStore: LibraryViewModel
    @AppStorage("enableFavorites") private var enableFavorites = false
    @AppStorage("enablePlaylists") private var enablePlaylists = false

    func body(content: Content) -> some View {
        content.contextMenu {
            Button(tr("Play", "Abspielen")) {
                Task {
                    guard let detail = try? await SubsonicAPIService.shared.getAlbum(id: album.id) else { return }
                    await MainActor.run { AudioPlayerService.shared.play(songs: detail.song) }
                }
            }
            Button(tr("Shuffle", "Zufällig abspielen")) {
                Task {
                    guard let detail = try? await SubsonicAPIService.shared.getAlbum(id: album.id) else { return }
                    await MainActor.run { AudioPlayerService.shared.playShuffled(songs: detail.song) }
                }
            }
            Divider()
            Button(tr("Play Next", "Als nächstes abspielen")) {
                Task {
                    guard let detail = try? await SubsonicAPIService.shared.getAlbum(id: album.id) else { return }
                    await MainActor.run { AudioPlayerService.shared.addPlayNext(detail.song) }
                }
            }
            Button(tr("Add to Queue", "Zur Warteschlange hinzufügen")) {
                Task {
                    guard let detail = try? await SubsonicAPIService.shared.getAlbum(id: album.id) else { return }
                    await MainActor.run { AudioPlayerService.shared.addToUserQueue(detail.song) }
                }
            }
            if enableFavorites || enablePlaylists {
                Divider()
                if enableFavorites {
                    Button(libraryStore.isAlbumStarred(album)
                           ? tr("Remove from Favorites", "Aus Favoriten entfernen")
                           : tr("Add to Favorites", "Zu Favoriten hinzufügen")) {
                        Task { await libraryStore.toggleStarAlbum(album) }
                    }
                }
                if enablePlaylists {
                    Button(tr("Add to Playlist…", "Zur Wiedergabeliste hinzufügen…")) {
                        Task {
                            guard let detail = try? await SubsonicAPIService.shared.getAlbum(id: album.id),
                                  !detail.song.isEmpty else { return }
                            let ids = detail.song.map(\.id)
                            await MainActor.run {
                                NotificationCenter.default.post(name: .addSongsToPlaylist, object: ids)
                            }
                        }
                    }
                }
            }
        }
    }
}

extension View {
    func albumContextMenu(_ album: Album) -> some View {
        modifier(AlbumContextMenuModifier(album: album))
    }
}
