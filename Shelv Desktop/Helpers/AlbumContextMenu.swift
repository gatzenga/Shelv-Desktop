import SwiftUI

struct AlbumContextMenuModifier: ViewModifier {
    let album: Album
    @ObservedObject var libraryStore = LibraryViewModel.shared
    @ObservedObject private var downloadStore = DownloadStore.shared
    @ObservedObject private var offlineMode = OfflineModeService.shared
    @AppStorage("enableFavorites") private var enableFavorites = true
    @AppStorage("enablePlaylists") private var enablePlaylists = true
    @AppStorage("enableDownloads") private var enableDownloads = false
    @State private var showDeleteConfirm = false

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
            Button(tr("Play Next", "Als nächstes")) {
                withAlbumSongs(errorMsg: tr("Action failed", "Aktion fehlgeschlagen")) { songs in
                    AudioPlayerService.shared.addPlayNext(songs)
                    NotificationCenter.default.post(name: .showToast, object: tr("Added to Play Next", "Als nächstes hinzugefügt"))
                }
            }
            Button(tr("Add to Queue", "Zur Warteschlange")) {
                withAlbumSongs(errorMsg: tr("Action failed", "Aktion fehlgeschlagen")) { songs in
                    AudioPlayerService.shared.addToUserQueue(songs)
                    NotificationCenter.default.post(name: .showToast, object: tr("Added to Queue", "Zur Warteschlange"))
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
                    Button(tr("Add to Playlist…", "Zur Playlist hinzufügen…")) {
                        withAlbumSongs(errorMsg: tr("Action failed", "Aktion fehlgeschlagen")) { songs in
                            guard !songs.isEmpty else { return }
                            NotificationCenter.default.post(name: .addSongsToPlaylist, object: songs.map(\.id))
                        }
                    }
                }
            }
            if enableDownloads {
                Divider()
                let status = downloadStore.albumDownloadStatus(albumId: album.id, totalSongs: album.songCount ?? 0)
                switch status {
                case .none:
                    if !offlineMode.isOffline {
                        Button(tr("Download Album", "Album herunterladen")) {
                            DownloadStore.shared.enqueueAlbum(album)
                        }
                    }
                case .partial:
                    if !offlineMode.isOffline {
                        Button(tr("Download Remaining", "Rest herunterladen")) {
                            DownloadStore.shared.enqueueAlbum(album)
                        }
                    }
                    Button(role: .destructive) { showDeleteConfirm = true } label: { Label { Text(tr("Delete Downloads", "Downloads löschen")) } icon: { DeleteDownloadIcon(tint: .red) } }
                case .complete:
                    Button(role: .destructive) { showDeleteConfirm = true } label: { Label { Text(tr("Delete Downloads", "Downloads löschen")) } icon: { DeleteDownloadIcon(tint: .red) } }
                }
            }
        }
        .alert(tr("Delete Downloads?", "Downloads löschen?"), isPresented: $showDeleteConfirm) {
            Button(tr("Delete", "Löschen"), role: .destructive) {
                DownloadStore.shared.deleteAlbum(album.id)
            }
            Button(tr("Cancel", "Abbrechen"), role: .cancel) {}
        } message: {
            Text(tr("The downloads will be removed from this device.", "Die Downloads werden von diesem Gerät entfernt."))
        }
    }

    private func withAlbumSongs(errorMsg: String, _ action: @MainActor @escaping ([Song]) -> Void) {
        Task {
            if offlineMode.isOffline {
                let songs = DownloadStore.shared.albums
                    .first { $0.albumId == album.id }?
                    .songs.map { $0.asSong() } ?? []
                await MainActor.run { action(songs) }
                return
            }
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
