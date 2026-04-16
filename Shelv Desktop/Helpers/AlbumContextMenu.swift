import SwiftUI

struct AlbumContextMenuModifier: ViewModifier {
    let album: Album
    @EnvironmentObject var libraryStore: LibraryViewModel
    @AppStorage("enableFavorites") private var enableFavorites = true
    @AppStorage("enablePlaylists") private var enablePlaylists = true

    func body(content: Content) -> some View {
        content.contextMenu {
            Button(tr("Play", "Abspielen")) {
                withAlbumSongs(errorMsg: tr("Playback failed", "Wiedergabe fehlgeschlagen")) { songs in
                    AudioPlayerService.shared.play(songs: songs)
                }
            }
            Button(tr("Shuffle", "Zufällig abspielen")) {
                withAlbumSongs(errorMsg: tr("Playback failed", "Wiedergabe fehlgeschlagen")) { songs in
                    AudioPlayerService.shared.playShuffled(songs: songs)
                }
            }
            Divider()
            Button(tr("Play Next", "Als nächstes abspielen")) {
                withAlbumSongs(errorMsg: tr("Action failed", "Aktion fehlgeschlagen")) { songs in
                    AudioPlayerService.shared.addPlayNext(songs)
                    NotificationCenter.default.post(name: .showToast, object: tr("Added to Play Next", "Als nächstes hinzugefügt"))
                }
            }
            Button(tr("Add to Queue", "Zur Warteschlange hinzufügen")) {
                withAlbumSongs(errorMsg: tr("Action failed", "Aktion fehlgeschlagen")) { songs in
                    AudioPlayerService.shared.addToUserQueue(songs)
                    NotificationCenter.default.post(name: .showToast, object: tr("Added to Queue", "Zur Warteschlange hinzugefügt"))
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
                        withAlbumSongs(errorMsg: tr("Action failed", "Aktion fehlgeschlagen")) { songs in
                            guard !songs.isEmpty else { return }
                            NotificationCenter.default.post(name: .addSongsToPlaylist, object: songs.map(\.id))
                        }
                    }
                }
            }
        }
    }

    private func withAlbumSongs(errorMsg: String, _ action: @MainActor @escaping ([Song]) -> Void) {
        Task {
            do {
                let detail = try await SubsonicAPIService.shared.getAlbum(id: album.id)
                await MainActor.run { action(detail.song) }
            } catch {
                NotificationCenter.default.post(name: .showToast, object: errorMsg)
            }
        }
    }
}

extension View {
    func albumContextMenu(_ album: Album) -> some View {
        modifier(AlbumContextMenuModifier(album: album))
    }
}
